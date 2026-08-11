import CoreGraphics
import XCTest

@testable import PawGuard

final class CatDetectorTests: XCTestCase {
    func testNormalTypingDoesNotDetect() {
        let detector = CatDetector()
        var result = DetectionResult.empty
        let keys: [CGKeyCode] = [4, 14, 37, 37, 31]  // h e l l o
        for (index, key) in keys.enumerated() {
            let time = Double(index) * 0.12
            result = detector.process(sample(key, time: time, type: .keyDown))
            _ = detector.process(sample(key, time: time + 0.04, type: .keyUp))
        }
        XCTAssertNotEqual(result.confidence, .cat)
        XCTAssertLessThan(result.score, DetectionRules.defaultThreshold)
    }

    func testFastSequentialTypingDoesNotDetect() {
        let detector = CatDetector()
        var result = DetectionResult.empty
        for index in 0..<10 {
            let key = CGKeyCode(index % 10)
            let time = Double(index) * 0.035
            result = detector.process(sample(key, time: time, type: .keyDown))
            _ = detector.process(sample(key, time: time + 0.02, type: .keyUp))
        }
        XCTAssertNotEqual(result.confidence, .cat)
    }

    func testCommonShortcutDoesNotDetect() {
        let detector = CatDetector()
        let modifiers = CGEventFlags.maskCommand.union(.maskShift)
        _ = detector.process(sample(55, time: 0, type: .keyDown, modifiers: modifiers))
        _ = detector.process(sample(56, time: 0.01, type: .keyDown, modifiers: modifiers))
        let result = detector.process(sample(35, time: 0.02, type: .keyDown, modifiers: modifiers))
        XCTAssertNotEqual(result.confidence, .cat)
    }

    func testGamingStyleHoldDoesNotDetect() {
        let detector = CatDetector()
        _ = detector.process(sample(13, time: 0, type: .keyDown))  // W
        let result = detector.process(sample(56, time: 0.02, type: .keyDown))  // Shift
        XCTAssertNotEqual(result.confidence, .cat)
    }

    func testFourKeyHumanChordDoesNotImmediatelyDetect() {
        let detector = CatDetector()
        var result = DetectionResult.empty
        for (index, key) in [0, 1, 2, 13].enumerated() {  // A S D W
            result = detector.process(sample(CGKeyCode(key), time: Double(index) * 0.015, type: .keyDown))
        }
        XCTAssertNotEqual(result.confidence, .cat)
    }

    func testLongWASDHoldDoesNotDetect() {
        let detector = CatDetector()
        for (index, key) in [0, 1, 2, 13].enumerated() {
            _ = detector.process(sample(CGKeyCode(key), time: Double(index) * 0.02, type: .keyDown))
        }
        let result = detector.process(sample(13, time: 2, type: .keyDown, isRepeat: true))
        XCTAssertNotEqual(result.confidence, .cat)
    }

    func testThreeKeyRolloverDuringFastTypingDoesNotDetect() {
        let detector = CatDetector()
        var result = DetectionResult.empty
        let keys: [CGKeyCode] = [4, 14, 37, 31, 34, 40, 46]
        for (index, key) in keys.enumerated() {
            let time = Double(index) * 0.045
            result = detector.process(sample(key, time: time, type: .keyDown))
            if index >= 2 {
                _ = detector.process(sample(keys[index - 2], time: time + 0.01, type: .keyUp))
            }
        }
        XCTAssertNotEqual(result.confidence, .cat)
    }

    func testCatPawPressesTrigger() {
        let detector = CatDetector()
        var result = DetectionResult.empty
        for (index, key) in [3, 5, 4, 9, 11, 45].enumerated() {  // F G H V B N
            result = detector.process(sample(CGKeyCode(key), time: Double(index) * 0.015, type: .keyDown))
        }
        XCTAssertEqual(result.confidence, .cat)
        XCTAssertTrue(result.signals.contains(.simultaneousKeys))
        XCTAssertTrue(result.signals.contains(.physicalCluster))
    }

    func testCatRestingOnKeyboardTriggersAfterHold() {
        let detector = CatDetector()
        for (index, key) in [38, 40, 37, 41].enumerated() {  // J K L ;
            _ = detector.process(sample(CGKeyCode(key), time: Double(index) * 0.02, type: .keyDown))
        }
        let result = detector.process(sample(38, time: 0.9, type: .keyDown, isRepeat: true))
        XCTAssertEqual(result.confidence, .cat)
        XCTAssertTrue(result.signals.contains(.multiKeyHold))
    }

    func testWalkingPawPatternTriggers() {
        let detector = CatDetector()
        var result = DetectionResult.empty
        for (index, key) in [38, 40, 32, 34, 46].enumerated() {  // J K U I M
            result = detector.process(sample(CGKeyCode(key), time: Double(index) * 0.08, type: .keyDown))
        }
        XCTAssertEqual(result.confidence, .cat)
        XCTAssertTrue(result.hasPhysicalCluster)
    }

    private func sample(
        _ key: CGKeyCode,
        time: TimeInterval,
        type: KeyboardEventKind,
        isRepeat: Bool = false,
        modifiers: CGEventFlags = []
    ) -> KeyboardEventSample {
        KeyboardEventSample(keyCode: key, timestamp: time, type: type, isRepeat: isRepeat, modifiers: modifiers)
    }
}
