import Foundation

enum ProtectionState: Equatable {
    case monitoring
    case suspicious(score: Int)
    case locked(until: Date)
    case cooldown(until: Date)

    var isLocked: Bool {
        if case .locked = self { return true }
        return false
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
    func lockKeyboard(for duration: TimeInterval, now: Date = .now) -> Date {
        lock.lock()
        let until = now.addingTimeInterval(duration)
        currentState = .locked(until: until)
        lock.unlock()
        return until
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
