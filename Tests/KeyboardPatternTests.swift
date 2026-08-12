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

    func testEngineDetectsQuietThreeKeyPawWithoutAutorepeat() {
        let engine = KeyboardEngine(threshold: 70, extendOnActivity: true, lockDuration: 20)
        for (index, key) in [3, 5, 4].enumerated() {  // F G H
            XCTAssertTrue(
                engine.process(
                    KeyboardEventSample(
                        keyCode: CGKeyCode(key),
                        timestamp: Double(index) * 0.02,
                        type: .keyDown
                    )
                )
            )
        }

        let result = engine.evaluateHeldKeys(at: 0.8)

        XCTAssertEqual(result.confidence, .cat)
        XCTAssertTrue(engine.state.isLocked)
    }

    func testMonitoringTimerDoesNotEraseHeldKeysBeforeHoldMatures() {
        let engine = KeyboardEngine(threshold: 70, extendOnActivity: true, lockDuration: 20)
        for (index, key) in [3, 5, 4].enumerated() {  // F G H
            _ = engine.process(
                KeyboardEventSample(
                    keyCode: CGKeyCode(key),
                    timestamp: Double(index) * 0.02,
                    type: .keyDown
                )
            )
        }

        for timerTimestamp in [0.25, 0.5] {
            let result = engine.evaluateHeldKeys(at: timerTimestamp)
            XCTAssertEqual(result.heldKeyCount, 3)
            XCTAssertFalse(engine.state.isLocked)
            XCTAssertEqual(engine.advance(), .monitoring)
        }

        let maturedResult = engine.evaluateHeldKeys(at: 0.8)
        XCTAssertEqual(maturedResult.confidence, .cat)
        XCTAssertTrue(engine.state.isLocked)
    }

    func testEngineDoesNotDetectReleasedHumanRolloverOnTimer() {
        let engine = KeyboardEngine(threshold: 70, extendOnActivity: true, lockDuration: 20)
        for (index, key) in [4, 14, 37].enumerated() {  // H E L
            let time = Double(index) * 0.04
            XCTAssertTrue(
                engine.process(
                    KeyboardEventSample(keyCode: CGKeyCode(key), timestamp: time, type: .keyDown)
                )
            )
            XCTAssertTrue(
                engine.process(
                    KeyboardEventSample(keyCode: CGKeyCode(key), timestamp: time + 0.025, type: .keyUp)
                )
            )
        }

        let result = engine.evaluateHeldKeys(at: 0.8)

        XCTAssertEqual(result.heldKeyCount, 0)
        XCTAssertFalse(engine.state.isLocked)
    }

    func testMonitorInterruptionClearsHeldKeyState() {
        let engine = KeyboardEngine(threshold: 70, extendOnActivity: true, lockDuration: 20)
        for (index, key) in [3, 5, 4].enumerated() {
            _ = engine.process(
                KeyboardEventSample(
                    keyCode: CGKeyCode(key),
                    timestamp: Double(index) * 0.02,
                    type: .keyDown
                )
            )
        }

        engine.resetDetectionAfterMonitorInterruption()
        let result = engine.evaluateHeldKeys(at: 0.8)

        XCTAssertEqual(result.heldKeyCount, 0)
        XCTAssertFalse(engine.state.isLocked)
    }
}
