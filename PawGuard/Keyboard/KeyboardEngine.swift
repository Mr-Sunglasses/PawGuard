import CoreGraphics
import Foundation

/// Everything the UI needs to know about one protection event.
struct ProtectionEvent {
    let result: DetectionResult
    /// Keystrokes that reached the frontmost app before protection engaged.
    /// These are what an undo would remove.
    let deliveredKeystrokes: Int
}

/// How the most recent lock came to an end.
///
/// The coordinator learns about an emergency unlock through a hop to the main
/// actor, and its own tick can observe the same lock ending first. Recording
/// the reason here lets whichever of the two gets there first label the lock
/// correctly, instead of the tick assuming every lock it sees end ran its
/// course.
enum LockEnding: Equatable {
    case expired
    case emergencyUnlock
    case unlocked
}

/// Serialises detection, protection state, and event disposition.
///
/// `process` runs on the event tap's thread while the monitoring timer runs on
/// the main actor, so every piece of mutable state here — including the
/// detector — is guarded by a single recursive lock.
final class KeyboardEngine {
    let detector: CatDetector
    let protectionManager: ProtectionManager

    var onCatDetected: ((ProtectionEvent) -> Void)?
    var onDetectionUpdated: ((DetectionResult) -> Void)?
    var onBlockedActivity: (() -> Void)?
    var onEmergencyUnlock: (() -> Void)?
    /// Reports how a grace window ended: committed to a lock, or replayed.
    var onGraceResolved: ((Bool) -> Void)?

    private let injector: KeyboardEventInjecting
    /// Wall-clock source for protection deadlines. Injectable so grace-window
    /// behaviour can be tested without waiting in real time.
    private let clock: () -> Date
    private let stateLock = NSRecursiveLock()

    private var extendOnActivity = true
    private var lockDuration: TimeInterval = 20
    private var graceEnabled = true
    private var graceDuration: TimeInterval = DetectionRules.graceWindow
    private var protectionSuppressed = false

    /// Keys passed through to applications whose key-up has not been seen yet.
    /// Without releasing these on lock, the frontmost app believes they are
    /// still held for the whole lock.
    private var deliveredKeys: [CGKeyCode: TimeInterval] = [:]
    private var deliveredModifiers: Set<CGKeyCode> = []
    /// Recent delivered key-downs, autorepeats included, for counting what an
    /// undo should remove. `producesText` is false for anything a backspace
    /// cannot take back: Return, Delete, navigation, and shortcuts.
    private var deliveredHistory: [(timestamp: TimeInterval, producesText: Bool)] = []
    private var lockEnding: LockEnding?
    /// Key-downs withheld from applications; their key-ups must be withheld too
    /// or apps see a key release they never saw pressed.
    private var withheldKeys: Set<CGKeyCode> = []
    private var graceBuffer: [KeyboardEventSample] = []
    private var lastGraceResult: DetectionResult = .empty

    /// How far back a keystroke counts as part of the same cat episode.
    static let undoLookback: TimeInterval = 2.5
    /// A key pressed with any of these runs a command or composes a character
    /// (Option), so one backspace is not guaranteed to take it back.
    private static let nonTextModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate]

    init(
        threshold: Int,
        extendOnActivity: Bool,
        lockDuration: TimeInterval = 20,
        graceEnabled: Bool = true,
        graceDuration: TimeInterval = DetectionRules.graceWindow,
        injector: KeyboardEventInjecting = KeyboardEventInjector(),
        clock: @escaping () -> Date = Date.init
    ) {
        detector = CatDetector(threshold: threshold)
        protectionManager = ProtectionManager()
        self.extendOnActivity = extendOnActivity
        self.lockDuration = lockDuration
        self.graceEnabled = graceEnabled
        self.graceDuration = graceDuration
        self.injector = injector
        self.clock = clock
    }

    func update(
        threshold: Int,
        extendOnActivity: Bool,
        lockDuration: TimeInterval,
        graceEnabled: Bool = true,
        protectionSuppressed: Bool = false,
        allowedKeySets: [Set<CGKeyCode>] = []
    ) {
        stateLock.lock()
        detector.updateThreshold(threshold)
        detector.allowedKeySets = allowedKeySets
        self.extendOnActivity = extendOnActivity
        self.lockDuration = lockDuration
        self.graceEnabled = graceEnabled
        self.protectionSuppressed = protectionSuppressed
        stateLock.unlock()
    }

    /// Exposed for the grace-window tests, which cannot wait in real time.
    func setGraceDuration(_ duration: TimeInterval) {
        stateLock.lock()
        graceDuration = duration
        stateLock.unlock()
    }

    // MARK: - Event handling

    /// Returns true to let the event reach applications.
    func process(_ sample: KeyboardEventSample) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }

        // A lock or cooldown that has run out ends here, on the tap thread,
        // rather than waiting for the main actor's tick. The tick can be late —
        // held off by a tracking loop or throttled by App Nap — and a keyboard
        // must not stay locked past its deadline because of it.
        let state = expireProtection()

        if isEmergencyUnlock(sample) && state.withholdsInput {
            finishLock(replayWithheld: false)
            protectionManager.unlock(now: clock())
            lockEnding = .emergencyUnlock
            detector.reset()
            onEmergencyUnlock?()
            return false
        }

        switch state {
        case .locked:
            if sample.type == .keyDown {
                protectionManager.registerBlockedActivity(now: clock(), extend: extendOnActivity)
                onBlockedActivity?()
            }
            withhold(sample)
            return false

        case .grace(let until):
            graceBuffer.append(sample)
            withhold(sample)
            let result = detector.process(sample)
            lastGraceResult = result
            onDetectionUpdated?(result)
            if result.isImmediate {
                commitLock(with: result)
            } else if clock() >= until {
                resolveGrace(commit: result.confidence == .cat)
            }
            return false

        case .cooldown:
            detector.reset()
            return deliver(sample)

        case .monitoring:
            let result = detector.process(sample)
            onDetectionUpdated?(result)

            guard sample.type == .keyDown,
                !KeyboardGeometry.isModifier(sample.keyCode),
                result.confidence == .cat,
                !protectionSuppressed
            else {
                return deliver(sample)
            }

            if result.isImmediate || !graceEnabled {
                commitLock(with: result)
                withhold(sample)
                return false
            }

            // Borderline: withhold input briefly rather than committing. If the
            // next moments look human the events are replayed, so being wrong
            // costs a barely perceptible delay instead of a locked keyboard.
            protectionManager.beginGrace(for: graceDuration, now: clock())
            graceBuffer = [sample]
            lastGraceResult = result
            withhold(sample)
            return false
        }
    }

    /// Detects a paw that has stopped generating events while several keys
    /// remain physically down. Called by the monitoring timer.
    @discardableResult
    func evaluateHeldKeys(at timestamp: TimeInterval) -> DetectionResult {
        stateLock.lock()
        defer { stateLock.unlock() }

        // Grace resolution belongs to `advance`, which the same tick calls.
        guard case .monitoring = protectionManager.state else { return .empty }
        let result = detector.evaluate(at: timestamp)
        onDetectionUpdated?(result)
        // The score is the real guard here. A count gate used to sit in front of
        // it, which meant a paw resting on one or two keys could never be acted
        // on from the timer no matter how long it stayed there.
        guard result.heldKeyCount >= 1, result.confidence == .cat, !protectionSuppressed else {
            return result
        }
        commitLock(with: result)
        return result
    }

    func resetDetectionAfterMonitorInterruption() {
        stateLock.lock()
        detector.reset()
        // A tap that stopped delivering events cannot be trusted about which
        // keys are still down, so nothing is left owing a synthetic key-up.
        deliveredKeys.removeAll()
        deliveredModifiers.removeAll()
        withheldKeys.removeAll()
        graceBuffer.removeAll()
        stateLock.unlock()
        onDetectionUpdated?(.empty)
    }

    // MARK: - Protection lifecycle

    private func commitLock(with result: DetectionResult) {
        let delivered = recentlyDeliveredKeystrokes()
        finishLock(replayWithheld: false)
        protectionManager.lockKeyboard(for: lockDuration, now: clock())
        lockEnding = nil
        detector.reset()
        onCatDetected?(ProtectionEvent(result: result, deliveredKeystrokes: delivered))
    }

    private func resolveGrace(commit: Bool) {
        if commit {
            commitLock(with: lastGraceResult)
            onGraceResolved?(true)
        } else {
            protectionManager.cancelGrace()
            let buffered = graceBuffer
            graceBuffer.removeAll()
            for sample in buffered where sample.type == .keyDown {
                withheldKeys.remove(sample.keyCode)
                noteDelivered(sample)
            }
            for sample in buffered where sample.type == .keyUp {
                withheldKeys.remove(sample.keyCode)
                noteDelivered(sample)
            }
            injector.replay(buffered)
            onGraceResolved?(false)
        }
    }

    /// Tells applications that every key they saw go down has come back up, and
    /// clears any modifier that was physically held when protection engaged.
    private func finishLock(replayWithheld: Bool) {
        let keysToRelease = Array(deliveredKeys.keys) + Array(deliveredModifiers)
        if !keysToRelease.isEmpty {
            injector.releaseKeys(keysToRelease)
        }
        deliveredKeys.removeAll()
        deliveredModifiers.removeAll()
        deliveredHistory.removeAll()
        if replayWithheld, !graceBuffer.isEmpty {
            injector.replay(graceBuffer)
        }
        graceBuffer.removeAll()
    }

    /// How many backspaces would remove what the cat typed, or zero when no
    /// number of them would.
    ///
    /// Every autorepeat is a character on screen, so repeats count. A Return,
    /// a Delete, an arrow, or a shortcut in the episode means backspacing
    /// cannot restore the text — it would delete the user's own words instead —
    /// so undo is not offered at all.
    private func recentlyDeliveredKeystrokes() -> Int {
        guard let latest = deliveredHistory.last?.timestamp else { return 0 }
        let episode = deliveredHistory.filter { latest - $0.timestamp <= Self.undoLookback }
        guard episode.allSatisfy(\.producesText) else { return 0 }
        return episode.count
    }

    /// Removes what the cat typed before protection engaged.
    func undoDeliveredKeystrokes(count: Int) {
        guard count > 0 else { return }
        injector.deleteBackward(count: count)
    }

    // MARK: - Event bookkeeping

    private func deliver(_ sample: KeyboardEventSample) -> Bool {
        // An application must never see a key-up for a press it never received.
        if sample.type == .keyUp, withheldKeys.remove(sample.keyCode) != nil {
            return false
        }
        noteDelivered(sample)
        return true
    }

    private func noteDelivered(_ sample: KeyboardEventSample) {
        switch sample.type {
        case .keyDown:
            if KeyboardGeometry.isModifier(sample.keyCode) {
                deliveredModifiers.insert(sample.keyCode)
            } else {
                if !sample.isRepeat {
                    deliveredKeys[sample.keyCode] = sample.timestamp
                }
                let producesText =
                    KeyboardGeometry.isTextKey(sample.keyCode)
                    && sample.modifiers.intersection(Self.nonTextModifiers).isEmpty
                deliveredHistory.append((sample.timestamp, producesText))
                if deliveredHistory.count > 256 { deliveredHistory.removeFirst() }
            }
        case .keyUp:
            deliveredKeys.removeValue(forKey: sample.keyCode)
            deliveredModifiers.remove(sample.keyCode)
        case .flagsChanged:
            // A modifier press arrives as a flags change; track it so it can be
            // released if protection engages while it is held.
            if KeyboardGeometry.isModifier(sample.keyCode) {
                if sample.modifiers.isEmpty {
                    deliveredModifiers.remove(sample.keyCode)
                } else {
                    deliveredModifiers.insert(sample.keyCode)
                }
            }
        }
    }

    private func withhold(_ sample: KeyboardEventSample) {
        guard sample.type == .keyDown, !sample.isRepeat else { return }
        withheldKeys.insert(sample.keyCode)
    }

    // MARK: - State

    func unlock() {
        stateLock.lock()
        finishLock(replayWithheld: false)
        protectionManager.unlock(now: clock())
        lockEnding = .unlocked
        detector.reset()
        stateLock.unlock()
    }

    /// How the most recent lock ended, or nil while one is in force or none
    /// has happened yet.
    var lastLockEnding: LockEnding? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return lockEnding
    }

    func reset() {
        stateLock.lock()
        finishLock(replayWithheld: false)
        withheldKeys.removeAll()
        protectionManager.reset()
        detector.reset()
        stateLock.unlock()
    }

    /// Advances protection state and, when a grace window has run out, decides
    /// whether the withheld input was a cat or a human.
    ///
    /// The decision re-evaluates the detector at `timestamp` rather than
    /// reusing the score that opened the window, so a paw that has since lifted
    /// gets its keystrokes back.
    func advance(at timestamp: TimeInterval = MonotonicClock.now) -> ProtectionState {
        stateLock.lock()
        defer { stateLock.unlock() }

        if case .grace(let until) = protectionManager.state, clock() >= until {
            let result = detector.evaluate(at: timestamp)
            lastGraceResult = result
            resolveGrace(commit: result.confidence == .cat)
        }

        return expireProtection()
    }

    /// Moves an expired lock into cooldown and an expired cooldown back to
    /// monitoring. Grace windows are left to their callers, which each know
    /// what evidence the window should be judged on.
    ///
    /// Caller must hold `stateLock`.
    private func expireProtection() -> ProtectionState {
        let previousState = protectionManager.state
        let state = protectionManager.advance(now: clock())
        if case .locked = previousState, !state.isLocked {
            lockEnding = .expired
        }
        if case .cooldown = previousState, case .monitoring = state {
            detector.reset()
            withheldKeys.removeAll()
            onDetectionUpdated?(.empty)
        }
        return state
    }

    var state: ProtectionState {
        protectionManager.state
    }

    private func isEmergencyUnlock(_ sample: KeyboardEventSample) -> Bool {
        guard sample.type == .keyDown, sample.keyCode == 53 else { return false }
        return sample.modifiers.contains(.maskControl) && sample.modifiers.contains(.maskAlternate)
            && sample.modifiers.contains(.maskCommand)
    }
}
