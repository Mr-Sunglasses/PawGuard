import Foundation

enum ProtectionState: Equatable {
    case monitoring
    case suspicious(score: Int)
    /// Input is being withheld while a borderline detection is confirmed.
    /// Ends either in a lock or in the withheld input being replayed.
    case grace(until: Date)
    case locked(until: Date)
    case cooldown(until: Date)

    var isLocked: Bool {
        if case .locked = self { return true }
        return false
    }

    var isGrace: Bool {
        if case .grace = self { return true }
        return false
    }

    /// True while keyboard input is not reaching applications.
    var withholdsInput: Bool {
        isLocked || isGrace
    }
}

final class ProtectionManager {
    private let lock = NSLock()
    private var currentState: ProtectionState = .monitoring

    var state: ProtectionState {
        lock.lock()
        defer { lock.unlock() }
        return currentState
    }

    @discardableResult
    func markSuspicious(score: Int) -> ProtectionState {
        lock.lock()
        currentState = .suspicious(score: score)
        let result = currentState
        lock.unlock()
        return result
    }

    @discardableResult
    func beginGrace(
        for duration: TimeInterval = DetectionRules.graceWindow,
        now: Date = .now
    ) -> Date {
        lock.lock()
        let until = now.addingTimeInterval(duration)
        currentState = .grace(until: until)
        lock.unlock()
        return until
    }

    @discardableResult
    func lockKeyboard(for duration: TimeInterval, now: Date = .now) -> Date {
        lock.lock()
        let until = now.addingTimeInterval(duration)
        currentState = .locked(until: until)
        lock.unlock()
        return until
    }

    /// Abandons a grace window without locking, so withheld input can be
    /// replayed and monitoring resumes immediately.
    @discardableResult
    func cancelGrace() -> ProtectionState {
        lock.lock()
        if case .grace = currentState {
            currentState = .monitoring
        }
        let result = currentState
        lock.unlock()
        return result
    }

    @discardableResult
    func registerBlockedActivity(
        now: Date = .now,
        extend: Bool = true,
        extensionDuration: TimeInterval = DetectionRules.activityExtension
    ) -> ProtectionState {
        lock.lock()
        if case .locked(let until) = currentState, extend {
            currentState = .locked(until: max(until, now.addingTimeInterval(extensionDuration)))
        }
        let result = currentState
        lock.unlock()
        return result
    }

    @discardableResult
    func unlock(now: Date = .now) -> ProtectionState {
        lock.lock()
        currentState = .cooldown(until: now.addingTimeInterval(DetectionRules.cooldown))
        let result = currentState
        lock.unlock()
        return result
    }

    @discardableResult
    func advance(now: Date = .now) -> ProtectionState {
        lock.lock()
        switch currentState {
        case .locked(let until) where now >= until:
            currentState = .cooldown(until: now.addingTimeInterval(DetectionRules.cooldown))
        case .cooldown(let until) where now >= until:
            currentState = .monitoring
        default:
            break
        }
        let result = currentState
        lock.unlock()
        return result
    }

    func reset() {
        lock.lock()
        currentState = .monitoring
        lock.unlock()
    }
}
