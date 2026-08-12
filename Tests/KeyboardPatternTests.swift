import CoreGraphics
import XCTest

@testable import PawGuard

final class KeyboardPatternTests: XCTestCase {
    private var injector = SpyKeyboardEventInjector()

    override func setUp() {
        super.setUp()
        injector = SpyKeyboardEventInjector()
    }

    private func makeEngine(
        threshold: Int = 70,
        lockDuration: TimeInterval = 20,
        graceEnabled: Bool = true,
        graceDuration: TimeInterval = 0,
        clock: TestClock? = nil
    ) -> KeyboardEngine {
        KeyboardEngine(
            threshold: threshold,
            extendOnActivity: true,
            lockDuration: lockDuration,
            graceEnabled: graceEnabled,
            graceDuration: graceDuration,
            injector: injector,
            clock: clock.map { fake in { fake.now } } ?? Date.init
        )
    }

    // MARK: - Baseline behaviour

    func testEngineBlocksCatActivityAndEmergencyUnlocks() {
        let engine = makeEngine()
        for (index, key) in [3, 5, 4, 9, 11, 45].enumerated() {
            _ = engine.process(makeSample(CGKeyCode(key), time: Double(index) * 0.01, type: .keyDown))
        }
        XCTAssertEqual(engine.state.isLocked, true)
        XCTAssertFalse(engine.process(makeSample(0, time: 1, type: .keyDown)))

        let emergencyFlags = CGEventFlags.maskControl.union(.maskAlternate).union(.maskCommand)
        XCTAssertFalse(engine.process(makeSample(53, time: 1.1, type: .keyDown, modifiers: emergencyFlags)))
        guard case .cooldown = engine.state else {
            return XCTFail("Emergency shortcut should enter cooldown")
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
        let engine = makeEngine(threshold: 30)
        for (index, key) in [3, 5, 4, 9, 11, 45].enumerated() {
            _ = engine.detector.process(makeSample(CGKeyCode(key), time: Double(index) * 0.01, type: .keyDown))
        }
        XCTAssertTrue(engine.process(makeSample(3, time: 0.1, type: .keyUp)))
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
        let engine = makeEngine()
        for (index, key) in [3, 5, 4].enumerated() {
            XCTAssertTrue(engine.process(makeSample(CGKeyCode(key), time: Double(index) * 0.02, type: .keyDown)))
        }
        let result = engine.evaluateHeldKeys(at: 0.8)
        XCTAssertEqual(result.confidence, .cat)
        XCTAssertTrue(engine.state.isLocked)
    }

    func testMonitoringTimerDoesNotEraseHeldKeysBeforeHoldMatures() {
        let engine = makeEngine()
        for (index, key) in [3, 5, 4].enumerated() {
            _ = engine.process(makeSample(CGKeyCode(key), time: Double(index) * 0.02, type: .keyDown))
        }
        for timerTimestamp in [0.25, 0.5] {
            let result = engine.evaluateHeldKeys(at: timerTimestamp)
            XCTAssertEqual(result.heldKeyCount, 3)
            XCTAssertFalse(engine.state.isLocked)
            XCTAssertEqual(engine.advance(at: timerTimestamp), .monitoring)
        }
        let matured = engine.evaluateHeldKeys(at: 0.8)
        XCTAssertEqual(matured.confidence, .cat)
        XCTAssertTrue(engine.state.isLocked)
    }

    func testEngineDoesNotDetectReleasedHumanRolloverOnTimer() {
        let engine = makeEngine()
        for (index, key) in [4, 14, 37].enumerated() {
            let time = Double(index) * 0.04
            XCTAssertTrue(engine.process(makeSample(CGKeyCode(key), time: time, type: .keyDown)))
            XCTAssertTrue(engine.process(makeSample(CGKeyCode(key), time: time + 0.025, type: .keyUp)))
        }
        let result = engine.evaluateHeldKeys(at: 0.8)
        XCTAssertEqual(result.heldKeyCount, 0)
        XCTAssertFalse(engine.state.isLocked)
    }

    func testMonitorInterruptionClearsHeldKeyState() {
        let engine = makeEngine()
        for (index, key) in [3, 5, 4].enumerated() {
            _ = engine.process(makeSample(CGKeyCode(key), time: Double(index) * 0.02, type: .keyDown))
        }
        engine.resetDetectionAfterMonitorInterruption()
        let result = engine.evaluateHeldKeys(at: 0.8)
        XCTAssertEqual(result.heldKeyCount, 0)
        XCTAssertFalse(engine.state.isLocked)
    }

    // MARK: - Stuck keys and modifiers

    func testLockingReleasesKeysTheAppAlreadySaw() {
        let engine = makeEngine()
        // Three keys reach the app before the fourth crosses the threshold.
        for (index, key) in [3, 5, 4].enumerated() {
            XCTAssertTrue(engine.process(makeSample(CGKeyCode(key), time: Double(index) * 0.02, type: .keyDown)))
        }
        _ = engine.evaluateHeldKeys(at: 0.8)
        XCTAssertTrue(engine.state.isLocked)

        // Without this the frontmost app believes F, G and H are still held for
        // the whole lock.
        XCTAssertEqual(Set(injector.releasedKeys), [3, 5, 4])
    }

    func testLockingReleasesAHeldModifier() {
        let engine = makeEngine()
        _ = engine.process(makeSample(55, time: 0, type: .flagsChanged, modifiers: .maskCommand))
        for (index, key) in [3, 5, 4, 9, 11, 45].enumerated() {
            _ = engine.process(
                makeSample(CGKeyCode(key), time: 0.01 + Double(index) * 0.01, type: .keyDown, modifiers: .maskCommand)
            )
        }
        XCTAssertTrue(engine.state.isLocked)
        XCTAssertTrue(injector.releasedKeys.contains(55), "a held Command must be released, not left stuck down")
    }

    func testKeyUpForAWithheldPressIsAlsoWithheld() {
        let engine = makeEngine()
        for (index, key) in [3, 5, 4, 9, 11, 45].enumerated() {
            _ = engine.process(makeSample(CGKeyCode(key), time: Double(index) * 0.01, type: .keyDown))
        }
        XCTAssertTrue(engine.state.isLocked)
        // A brand new key pressed during the lock is withheld...
        XCTAssertFalse(engine.process(makeSample(46, time: 1, type: .keyDown)))
        engine.unlock()
        _ = engine.advance(at: 2)
        // ...so its release must be withheld too, or the app sees a key come up
        // that it never saw go down.
        XCTAssertFalse(engine.process(makeSample(46, time: 2.1, type: .keyUp)))
    }

    // MARK: - Grace window

    func testBorderlineDetectionEntersGraceInsteadOfLocking() {
        let engine = makeEngine(graceDuration: 5)
        var result = DetectionResult.empty
        engine.onDetectionUpdated = { result = $0 }
        for (index, key) in [3, 5, 4, 38].enumerated() {
            _ = engine.process(makeSample(CGKeyCode(key), time: Double(index) * 0.02, type: .keyDown))
        }
        XCTAssertEqual(result.confidence, .cat)
        XCTAssertFalse(result.isImmediate, "a four-key impact is strong but not beyond doubt")
        XCTAssertTrue(engine.state.isGrace)
        XCTAssertFalse(engine.state.isLocked)
    }

    func testOverwhelmingEvidenceSkipsTheGraceWindow() {
        let engine = makeEngine(graceDuration: 5)
        for (index, key) in [3, 5, 4, 9, 11, 45].enumerated() {
            _ = engine.process(makeSample(CGKeyCode(key), time: Double(index) * 0.01, type: .keyDown))
        }
        XCTAssertTrue(engine.state.isLocked, "six overlapping keys should not wait for confirmation")
    }

    func testGraceCommitsToALockWhileThePawStaysDown() {
        let engine = makeEngine(graceDuration: 0)
        var resolution: Bool?
        engine.onGraceResolved = { resolution = $0 }
        for (index, key) in [3, 5, 4, 38].enumerated() {
            _ = engine.process(makeSample(CGKeyCode(key), time: Double(index) * 0.02, type: .keyDown))
        }
        XCTAssertTrue(engine.state.isGrace)

        _ = engine.advance(at: 0.1)

        XCTAssertEqual(resolution, true)
        XCTAssertTrue(engine.state.isLocked)
        XCTAssertEqual(injector.replayCallCount, 0, "a confirmed cat's keystrokes must never be delivered")
    }

    func testGraceReplaysWithheldInputWhenItTurnsOutHuman() {
        let clock = TestClock()
        let engine = makeEngine(graceDuration: 0.18, clock: clock)
        var resolution: Bool?
        engine.onGraceResolved = { resolution = $0 }

        // The first three keys reach the app; the fourth opens a grace window.
        for (index, key) in [3, 5, 4, 38].enumerated() {
            _ = engine.process(makeSample(CGKeyCode(key), time: Double(index) * 0.02, type: .keyDown))
        }
        XCTAssertTrue(engine.state.isGrace)

        // The keys come straight back up: fingers, not a paw.
        for (index, key) in [3, 5, 4, 38].enumerated() {
            _ = engine.process(makeSample(CGKeyCode(key), time: 0.1 + Double(index) * 0.01, type: .keyUp))
        }
        clock.advance(by: 0.2)
        _ = engine.advance(at: 0.2)

        XCTAssertEqual(resolution, false)
        XCTAssertEqual(engine.state, .monitoring)
        // Only what was actually withheld gets replayed: the press that opened
        // the window and every event after it.
        XCTAssertEqual(
            injector.replayedEvents.filter { $0.type == .keyDown }.map(\.keyCode),
            [38],
            "the withheld press must be delivered after all"
        )
        XCTAssertEqual(injector.replayedEvents.count, 5, "the withheld press plus the four releases")
    }

    func testGraceCanBeTurnedOff() {
        let engine = makeEngine(graceEnabled: false)
        for (index, key) in [3, 5, 4, 38].enumerated() {
            _ = engine.process(makeSample(CGKeyCode(key), time: Double(index) * 0.02, type: .keyDown))
        }
        XCTAssertTrue(engine.state.isLocked)
    }

    // MARK: - Undo

    func testDetectionReportsHowManyKeystrokesGotThrough() {
        let engine = makeEngine()
        var event: ProtectionEvent?
        engine.onCatDetected = { event = $0 }
        for (index, key) in [3, 5, 4].enumerated() {
            _ = engine.process(makeSample(CGKeyCode(key), time: Double(index) * 0.02, type: .keyDown))
        }
        _ = engine.evaluateHeldKeys(at: 0.8)
        XCTAssertEqual(event?.deliveredKeystrokes, 3)
    }

    func testUndoPostsOneDeleteForEachDeliveredKeystroke() {
        let engine = makeEngine()
        engine.undoDeliveredKeystrokes(count: 4)
        XCTAssertEqual(injector.deleteCount, 4)
    }

    func testUndoIgnoresNonPositiveCounts() {
        let engine = makeEngine()
        engine.undoDeliveredKeystrokes(count: 0)
        engine.undoDeliveredKeystrokes(count: -3)
        XCTAssertEqual(injector.deleteCount, 0)
    }

    // MARK: - Context gates

    func testSuppressedProtectionNeverLocks() {
        let engine = makeEngine()
        engine.update(
            threshold: 70,
            extendOnActivity: true,
            lockDuration: 20,
            graceEnabled: true,
            protectionSuppressed: true
        )
        for (index, key) in [3, 5, 4, 9, 11, 45].enumerated() {
            _ = engine.process(makeSample(CGKeyCode(key), time: Double(index) * 0.01, type: .keyDown))
        }
        XCTAssertFalse(engine.state.isLocked)
        _ = engine.evaluateHeldKeys(at: 1.0)
        XCTAssertFalse(engine.state.isLocked)
    }

    func testFullscreenAppSuppressesProtectionWhenEnabled() {
        var context = DetectionContext()
        context.isFrontmostFullscreen = true
        XCTAssertTrue(context.isProtectionSuppressed(disabledBundleIdentifiers: [], pauseInFullscreen: true))
        XCTAssertFalse(context.isProtectionSuppressed(disabledBundleIdentifiers: [], pauseInFullscreen: false))
    }

    func testPerAppRuleSuppressesProtection() {
        var context = DetectionContext()
        context.frontmostBundleIdentifier = "com.example.game"
        XCTAssertTrue(
            context.isProtectionSuppressed(
                disabledBundleIdentifiers: ["com.example.game"],
                pauseInFullscreen: false
            )
        )
        XCTAssertFalse(
            context.isProtectionSuppressed(disabledBundleIdentifiers: ["com.other.app"], pauseInFullscreen: false)
        )
    }

    // MARK: - Physical key reconciliation

    func testReconciliationAdoptsKeysHeldBeforeMonitoringStarted() {
        let engine = makeEngine()
        // No events were ever seen; the paw was already on the keyboard when
        // monitoring started. With no impact timing to go on, the evidence is
        // the hold itself, so it takes a couple of seconds to mature.
        engine.reconcileHeldKeys(with: [3, 5, 4], at: 100)
        XCTAssertEqual(engine.evaluateHeldKeys(at: 100.5).heldKeyCount, 3)
        XCTAssertFalse(engine.state.isLocked)

        let result = engine.evaluateHeldKeys(at: 102)
        XCTAssertEqual(result.heldKeyCount, 3)
        XCTAssertEqual(result.confidence, .cat)
        XCTAssertTrue(engine.state.isLocked)
    }

    func testReconciliationDropsKeysWhoseKeyUpWasLost() {
        let engine = makeEngine()
        for (index, key) in [3, 5, 4].enumerated() {
            _ = engine.process(makeSample(CGKeyCode(key), time: Double(index) * 0.02, type: .keyDown))
        }
        // The hardware says nothing is down, so the inferred holds were stale.
        engine.reconcileHeldKeys(with: [], at: 0.5)
        let result = engine.evaluateHeldKeys(at: 0.8)
        XCTAssertEqual(result.heldKeyCount, 0)
        XCTAssertFalse(engine.state.isLocked)
    }

    func testStaleHoldsExpireEvenWithoutReconciliation() {
        let detector = CatDetector()
        _ = detector.process(makeSample(3, time: 0, type: .keyDown))
        let result = detector.evaluate(at: DetectionRules.staleHoldTimeout + 5)
        XCTAssertEqual(result.heldKeyCount, 0)
    }
}
