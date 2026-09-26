import AppKit
import Combine
import Foundation

/// Drives the protection lifecycle: the detection engine, the overlay, the
/// monitoring tick, and the statistics that come out of them.
///
/// Split out of `AppState` so that permission handling, profile editing, and
/// protection no longer share one object and one timer.
@MainActor
final class ProtectionCoordinator: ObservableObject {
    @Published private(set) var protectionState: ProtectionState = .monitoring
    @Published private(set) var currentDetection: DetectionResult = .empty
    @Published private(set) var overlayRemaining: TimeInterval = 0
    @Published private(set) var isTestOverlayVisible = false
    @Published private(set) var context = DetectionContext()
    /// Keystrokes the cat landed before protection engaged, available to undo
    /// while the overlay is up.
    @Published private(set) var undoableKeystrokes = 0
    /// When a pause the user asked for ends. `.distantFuture` means until they
    /// resume it themselves.
    @Published private(set) var pausedUntil: Date?

    let engine: KeyboardEngine
    let monitor: KeyboardEventMonitor

    private let settingsStore: SettingsStore
    private let statisticsStore: StatisticsStore
    private let calibrationStore: CalibrationStore
    private let overlayController = CatOverlayController()
    private let profileProvider: () -> CatProfile?

    /// `nonisolated(unsafe)`, like `appNapActivity`, only so the nonisolated
    /// `deinit` can release it. Both are written once, in `init`.
    nonisolated(unsafe) private var timer: Timer?
    /// Held for the coordinator's lifetime to keep App Nap away. A napping
    /// agent app has its timers coalesced by seconds at a time, and this tick
    /// is what resolves grace windows and matures a paw that has gone still.
    nonisolated(unsafe) private let appNapActivity: NSObjectProtocol
    private var protectionStartedAt: Date?
    private var lockStartedAt: Date?
    private var pendingBlockedEvents = 0
    private var testOverlayEnd: Date?
    private var contextTickCounter = 0

    /// The context probe does not need to run at the full tick rate.
    ///
    /// The tick itself is fast — re-scoring a handful of held keys — but
    /// reading the frontmost app is slower. Running it on a divisor keeps the
    /// cost per second low while detection latency drops with the tick.
    private static let tickInterval: TimeInterval = DetectionRules.monitorTick
    private static let contextTickDivisor = 10

    /// How a lock ended, as far as calibration and statistics are concerned.
    private enum LockOutcome {
        /// The lock ran its course: the detection stood.
        case ranItsCourse
        /// The user dismissed it after dealing with the cat: it stood too.
        case dismissed
        /// The user said it was them: PawGuard was wrong.
        case falseAlarm
        /// The emergency shortcut. Wrong if it came moments after the lock,
        /// otherwise says nothing either way.
        case emergencyUnlock
        /// Ended for a reason unrelated to the detection, such as a pause or
        /// permission loss. Teaches nothing.
        case abandoned
    }

    init(
        settingsStore: SettingsStore,
        statisticsStore: StatisticsStore,
        calibrationStore: CalibrationStore,
        profileProvider: @escaping () -> CatProfile?
    ) {
        self.settingsStore = settingsStore
        self.statisticsStore = statisticsStore
        self.calibrationStore = calibrationStore
        self.profileProvider = profileProvider
        appNapActivity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "PawGuard resolves keyboard protection on a short timer."
        )

        let settings = settingsStore.settings
        let engine = KeyboardEngine(
            threshold: settings.detectionThreshold,
            extendOnActivity: settings.extendOnActivity,
            lockDuration: settings.lockDuration,
            graceEnabled: settings.useGraceWindow
        )
        self.engine = engine
        monitor = KeyboardEventMonitor(
            handler: { [weak engine] sample in
                engine?.process(sample) ?? true
            },
            interruptionHandler: { [weak engine] in
                engine?.resetDetectionAfterMonitorInterruption()
            }
        )

        engine.onCatDetected = { [weak self] event in
            Task { @MainActor [weak self] in self?.handleDetection(event) }
        }
        engine.onDetectionUpdated = { [weak self] result in
            Task { @MainActor [weak self] in self?.handleDetectionUpdate(result) }
        }
        engine.onBlockedActivity = { [weak self] in
            Task { @MainActor [weak self] in self?.pendingBlockedEvents += 1 }
        }
        engine.onEmergencyUnlock = { [weak self] in
            Task { @MainActor [weak self] in self?.finishLock(.emergencyUnlock) }
        }

        // `.common`, not the default mode: a timer left in the default mode
        // stops firing while any of PawGuard's own controls is tracking the
        // mouse, and grace windows and held-key evaluation stall with it.
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    deinit {
        timer?.invalidate()
        ProcessInfo.processInfo.endActivity(appNapActivity)
    }

    var isLocked: Bool { protectionState.isLocked }

    var isPaused: Bool {
        guard let pausedUntil else { return false }
        return pausedUntil > .now
    }

    // MARK: - Actions

    func testCatMode() {
        guard !isLocked else { return }
        isTestOverlayVisible = true
        testOverlayEnd = Date().addingTimeInterval(8)
        overlayRemaining = 8
        overlayController.show(
            profile: profileProvider(),
            remaining: overlayRemaining,
            accent: settingsStore.settings.accentTheme,
            total: 8,
            isTest: true,
            undoableKeystrokes: 0,
            onUnlock: { [weak self] in self?.dismissTestOverlay() },
            onUndo: {},
            onFalseAlarm: {}
        )
    }

    /// Ends a lock the user has dealt with. The detection stood.
    func unlockNow() {
        guard isLocked else { return }
        engine.unlock()
        finishLock(.dismissed)
    }

    /// Ends a lock the user says was not the cat.
    func reportFalseAlarm() {
        guard isLocked else { return }
        engine.unlock()
        finishLock(.falseAlarm)
    }

    /// Stops protecting for `duration`, or until `resume()` when nil.
    func pause(for duration: TimeInterval?) {
        pausedUntil = duration.map { Date().addingTimeInterval($0) } ?? .distantFuture
        if isLocked {
            engine.unlock()
            finishLock(.abandoned)
        }
        syncEngine()
    }

    func resume() {
        pausedUntil = nil
        syncEngine()
    }

    func dismissTestOverlay() {
        testOverlayEnd = nil
        isTestOverlayVisible = false
        overlayController.dismiss()
    }

    /// Removes the keystrokes that reached the app before protection engaged.
    func undoCatTyping() {
        let count = undoableKeystrokes
        guard count > 0 else { return }
        undoableKeystrokes = 0
        overlayController.updateUndoAvailability(false)
        // The lock has to end first, or the synthetic deletes land while input
        // is still being withheld.
        if isLocked { unlockNow() }
        engine.undoDeliveredKeystrokes(count: count)
    }

    func teardownForPermissionLoss() {
        finishLock(.abandoned)
        engine.reset()
        protectionState = .monitoring
        currentDetection = .empty
        overlayController.dismiss()
    }

    // MARK: - Detection handling

    /// Called for every key event, so it must not redraw the UI for every key
    /// event. Most keystrokes score zero and change nothing worth publishing.
    private func handleDetectionUpdate(_ result: DetectionResult) {
        if result.score != currentDetection.score || result.confidence != currentDetection.confidence {
            currentDetection = result
        }
        // Only what looked human is evidence of how the user types. Anything
        // that crossed the threshold is either the cat or about to be judged,
        // and the calibration store discards the lead-up to every detection.
        if settingsStore.settings.adaptiveCalibration, result.confidence != .cat {
            calibrationStore.observe(result.features)
        }
    }

    private func handleDetection(_ event: ProtectionEvent) {
        currentDetection = event.result
        protectionStartedAt = protectionStartedAt ?? .now
        lockStartedAt = .now
        undoableKeystrokes = settingsStore.settings.offerUndo ? event.deliveredKeystrokes : 0
        statisticsStore.recordDetection()
        calibrationStore.recordDetection(event.result)
        if settingsStore.settings.showProtectionOverlay {
            showProtectionOverlay()
        }
        if settingsStore.settings.playProtectionSound {
            NSSound(named: NSSound.Name("Pop"))?.play()
        }
    }

    private func showProtectionOverlay() {
        guard case .locked(let until) = engine.state else { return }
        let remaining = max(0, until.timeIntervalSinceNow)
        overlayRemaining = remaining
        overlayController.show(
            profile: overlayProfile,
            remaining: remaining,
            accent: settingsStore.settings.accentTheme,
            total: settingsStore.settings.lockDuration,
            isTest: false,
            undoableKeystrokes: undoableKeystrokes,
            onUnlock: { [weak self] in self?.unlockNow() },
            onUndo: { [weak self] in self?.undoCatTyping() },
            onFalseAlarm: { [weak self] in self?.reportFalseAlarm() }
        )
    }

    /// The one place a lock is wrapped up, however it ended.
    ///
    /// An emergency unlock reaches here twice — once from its own callback and
    /// once from the tick that notices the lock is gone — in whichever order
    /// the main actor runs them. The first records the outcome and clears
    /// `protectionStartedAt`; the second finds nothing left to record and only
    /// tidies the UI.
    private func finishLock(_ outcome: LockOutcome) {
        let lockAge = lockStartedAt.map { Date().timeIntervalSince($0) }
        if let started = protectionStartedAt {
            statisticsStore.recordProtectionDuration(Date().timeIntervalSince(started))

            let wasMistaken: Bool?
            switch outcome {
            case .ranItsCourse, .dismissed:
                wasMistaken = false
            case .falseAlarm:
                wasMistaken = true
            case .emergencyUnlock:
                wasMistaken = (lockAge ?? .infinity) <= CalibrationStore.falsePositiveWindow ? true : nil
            case .abandoned:
                wasMistaken = nil
            }
            if wasMistaken == true { statisticsStore.recordFalseAlarm() }
            if settingsStore.settings.adaptiveCalibration, let wasMistaken {
                if wasMistaken {
                    calibrationStore.recordFalsePositive()
                } else {
                    calibrationStore.recordConfirmedDetection()
                }
            }
        }
        protectionStartedAt = nil
        lockStartedAt = nil
        undoableKeystrokes = 0
        protectionState = engine.state
        overlayController.dismiss()
        overlayRemaining = 0
    }

    private var overlayProfile: CatProfile? {
        guard let profile = profileProvider() else { return nil }
        guard settingsStore.settings.showCatPhoto else {
            var withoutPhoto = profile
            withoutPhoto.photoPaths = []
            withoutPhoto.selectedAvatarIndex = 0
            return withoutPhoto
        }
        return profile
    }

    // MARK: - Tick

    private func tick() {
        contextTickCounter += 1
        if contextTickCounter.isMultiple(of: Self.contextTickDivisor) {
            context = DetectionContextProbe.current()
        }
        if let pausedUntil, pausedUntil <= .now {
            self.pausedUntil = nil
        }

        syncEngine()

        let now = MonotonicClock.now
        engine.evaluateHeldKeys(at: now)

        if pendingBlockedEvents > 0 {
            statisticsStore.recordBlockedEvents(pendingBlockedEvents)
            pendingBlockedEvents = 0
        }

        if let testOverlayEnd {
            let remaining = testOverlayEnd.timeIntervalSinceNow
            if remaining <= 0 {
                dismissTestOverlay()
            } else {
                overlayRemaining = remaining
                overlayController.update(remaining: remaining)
            }
        }

        let wasLocked = protectionState.isLocked
        let nextState = engine.advance(at: now)
        protectionState = nextState
        if !wasLocked && nextState.isLocked {
            protectionStartedAt = protectionStartedAt ?? .now
            if settingsStore.settings.showProtectionOverlay { showProtectionOverlay() }
        }

        if case .locked(let until) = nextState {
            overlayRemaining = max(0, until.timeIntervalSinceNow)
            if settingsStore.settings.showProtectionOverlay {
                overlayController.update(remaining: overlayRemaining)
            } else {
                overlayController.dismiss()
            }
        } else if wasLocked {
            // Unlocks from the UI update `protectionState` synchronously, so a
            // lock this tick sees end either expired or was ended with the
            // emergency shortcut, whose own callback may not have run yet.
            finishLock(engine.lastLockEnding == .emergencyUnlock ? .emergencyUnlock : .ranItsCourse)
        }
    }

    /// Pushes current settings, calibration, and suppression into the engine.
    private func syncEngine() {
        let settings = settingsStore.settings
        let suppressed =
            isPaused
            || context.isProtectionSuppressed(
                disabledBundleIdentifiers: settings.disabledBundleIdentifiers,
                pauseInFullscreen: settings.pauseInFullscreen
            )
        engine.update(
            threshold: calibrationStore.effectiveThreshold(
                base: settings.detectionThreshold,
                adaptive: settings.adaptiveCalibration
            ),
            extendOnActivity: settings.extendOnActivity,
            lockDuration: settings.lockDuration,
            graceEnabled: settings.useGraceWindow,
            protectionSuppressed: suppressed,
            allowedKeySets: settings.adaptiveCalibration ? calibrationStore.allowedKeySets : []
        )
    }
}
