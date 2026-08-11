import CoreGraphics
import XCTest

@testable import PawGuard

final class KeyboardPatternTests: XCTestCase {
    func testEngineBlocksCatActivityAndEmergencyUnlocks() {
        let engine = KeyboardEngine(threshold: 70, extendOnActivity: true, lockDuration: 20)
        for (index, key) in [3, 5, 4, 9, 11, 45].enumerated() {
            _ = engine.process(
                KeyboardEventSample(
                    keyCode: CGKeyCode(key),
                    timestamp: Double(index) * 0.01,
                    type: .keyDown
                ))
        }
        XCTAssertEqual(engine.state.isLocked, true)
        XCTAssertFalse(engine.process(KeyboardEventSample(keyCode: 0, timestamp: 1, type: .keyDown)))

        let emergencyFlags = CGEventFlags.maskControl.union(.maskAlternate).union(.maskCommand)
        XCTAssertFalse(
            engine.process(
                KeyboardEventSample(
                    keyCode: 53,
                    timestamp: 1.1,
                    type: .keyDown,
                    modifiers: emergencyFlags
                )))
        if case .cooldown = engine.state {
            XCTAssertTrue(true)
        } else {
            XCTFail("Emergency shortcut should enter cooldown")
        }
    }

    func testProtectionStateExpiresIntoCooldownThenMonitoring() {
        let manager = ProtectionManager()
        let start = Date(timeIntervalSince1970: 100)
        let until = manager.lockKeyboard(for: 20, now: start)
        XCTAssertEqual(manager.state, .locked(until: until))

        let cooldownState = manager.advance(now: start.addingTimeInterval(21))
        guard case .cooldown(let cooldownUntil) = cooldownState else {
            return XCTFail("Expected cooldown after lock expiry")
        }
        XCTAssertEqual(cooldownUntil, start.addingTimeInterval(24))

        XCTAssertEqual(manager.advance(now: start.addingTimeInterval(25)), .monitoring)
    }

    func testKeyUpEventCannotStartProtection() {
        let engine = KeyboardEngine(threshold: 30, extendOnActivity: true, lockDuration: 20)
        for (index, key) in [3, 5, 4, 9, 11, 45].enumerated() {
            _ = engine.detector.process(
                KeyboardEventSample(
                    keyCode: CGKeyCode(key),
                    timestamp: Double(index) * 0.01,
                    type: .keyDown
                ))
        }

        XCTAssertTrue(engine.process(KeyboardEventSample(keyCode: 3, timestamp: 0.1, type: .keyUp)))
        XCTAssertFalse(engine.state.isLocked)
    }

    func testBlockedActivityExtendsProtectionWithoutChangingStateType() {
        let manager = ProtectionManager()
        let start = Date(timeIntervalSince1970: 200)
        _ = manager.lockKeyboard(for: 20, now: start)
        let extended = manager.registerBlockedActivity(now: start.addingTimeInterval(19), extend: true)
        guard case .locked(let until) = extended else {
            return XCTFail("Expected protection to remain locked")
        }
        XCTAssertEqual(until, start.addingTimeInterval(27))
    }
}
