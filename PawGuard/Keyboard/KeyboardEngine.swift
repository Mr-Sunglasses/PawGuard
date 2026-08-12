import CoreGraphics
import Foundation

final class KeyboardEngine {
    let detector: CatDetector
    let protectionManager: ProtectionManager

    var onCatDetected: ((DetectionResult) -> Void)?
    var onDetectionUpdated: ((DetectionResult) -> Void)?
    var onBlockedActivity: (() -> Void)?
    var onEmergencyUnlock: (() -> Void)?

    private let stateLock = NSLock()
    private var extendOnActivity = true
    private var lockDuration: TimeInterval = 20

    init(threshold: Int, extendOnActivity: Bool, lockDuration: TimeInterval = 20) {
        detector = CatDetector(threshold: threshold)
        protectionManager = ProtectionManager()
        self.extendOnActivity = extendOnActivity
        self.lockDuration = lockDuration
    }

    func update(threshold: Int, extendOnActivity: Bool, lockDuration: TimeInterval) {
        stateLock.lock()
        detector.updateThreshold(threshold)
        self.extendOnActivity = extendOnActivity
        self.lockDuration = lockDuration
        stateLock.unlock()
    }

    func process(_ sample: KeyboardEventSample) -> Bool {
        if isEmergencyUnlock(sample) && protectionManager.state.isLocked {
            protectionManager.unlock(now: Date())
            detector.reset()
            onEmergencyUnlock?()
            return false
        }

        if protectionManager.state.isLocked {
            if sample.type == .keyDown {
                stateLock.lock()
                let shouldExtend = extendOnActivity
                stateLock.unlock()
                protectionManager.registerBlockedActivity(extend: shouldExtend)
                onBlockedActivity?()
            }
            return false
        }

        if case .cooldown = protectionManager.state {
            detector.reset()
            return true
        }

        let result = detector.process(sample)
        onDetectionUpdated?(result)
        guard sample.type == .keyDown,
            !KeyboardGeometry.isModifier(sample.keyCode),
            result.confidence == .cat
        else { return true }

        beginProtection(for: result)
        return false
    }

    /// Detects a paw that has stopped generating events while several keys
    /// remain physically down. This is called by the app's monitoring timer.
    @discardableResult
    func evaluateHeldKeys(at timestamp: TimeInterval) -> DetectionResult {
        guard case .monitoring = protectionManager.state else { return .empty }
        let result = detector.evaluate(at: timestamp)
        onDetectionUpdated?(result)
        guard result.heldKeyCount >= 3, result.confidence == .cat else { return result }
        beginProtection(for: result)
        return result
    }

    func resetDetectionAfterMonitorInterruption() {
        detector.reset()
        onDetectionUpdated?(.empty)
    }

    private func beginProtection(for result: DetectionResult) {
        stateLock.lock()
        let duration = lockDuration
        stateLock.unlock()
        _ = protectionManager.lockKeyboard(for: duration)
        detector.reset()
        onCatDetected?(result)
    }

    func lockForTest(duration: TimeInterval) {
        protectionManager.lockKeyboard(for: duration)
    }

    func unlock() {
        protectionManager.unlock()
        detector.reset()
    }

    func reset() {
        protectionManager.reset()
        detector.reset()
    }

    func advance() -> ProtectionState {
        let previousState = protectionManager.state
        let state = protectionManager.advance()
        if case .cooldown = previousState, case .monitoring = state {
            detector.reset()
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
