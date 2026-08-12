import CoreGraphics
import XCTest

@testable import PawGuard

final class DetectionFeatureTests: XCTestCase {
    private func features(
        held: [CGKeyCode: TimeInterval],
        samples: [KeyboardEventSample],
        at timestamp: TimeInterval,
        modifiers: CGEventFlags = []
    ) -> DetectionFeatures {
        DetectionFeatures.extract(heldKeys: held, samples: samples, modifiers: modifiers, at: timestamp)
    }

    func testSynchronyCountsNearSimultaneousImpacts() {
        let samples = [
            makeSample(3, time: 0, type: .keyDown),
            makeSample(5, time: 0.006, type: .keyDown),
            makeSample(4, time: 0.011, type: .keyDown),
            makeSample(38, time: 0.018, type: .keyDown),
        ]
        let extracted = features(held: [3: 0, 5: 0.006, 4: 0.011, 38: 0.018], samples: samples, at: 0.02)
        XCTAssertEqual(extracted.synchronyCount, 4)
    }

    func testSynchronyIgnoresStaggeredHumanRollover() {
        let samples = (0..<4).map { makeSample(CGKeyCode(3 + $0), time: Double($0) * 0.06, type: .keyDown) }
        let extracted = features(held: [:], samples: samples, at: 0.2)
        XCTAssertEqual(extracted.synchronyCount, 1)
    }

    func testMedianIntervalMeasuresTypingRhythm() {
        let samples = (0..<5).map { makeSample(CGKeyCode(3 + $0), time: Double($0) * 0.12, type: .keyDown) }
        let extracted = features(held: [:], samples: samples, at: 0.5)
        XCTAssertEqual(extracted.medianInterval, 0.12, accuracy: 0.001)
    }

    func testHandAlternationIsHighForOrdinaryTyping() {
        // Alternating left and right hands, as touch typing does.
        let keys: [CGKeyCode] = [0, 38, 1, 40, 2, 37]
        let samples = keys.enumerated().map { makeSample($0.element, time: Double($0.offset) * 0.1, type: .keyDown) }
        let extracted = features(held: [:], samples: samples, at: 0.6)
        XCTAssertEqual(extracted.handAlternationRate, 1, accuracy: 0.001)
    }

    func testHandAlternationIsLowForAOneSidedPaw() {
        let keys: [CGKeyCode] = [38, 40, 37, 41]
        let samples = keys.enumerated().map { makeSample($0.element, time: Double($0.offset) * 0.01, type: .keyDown) }
        let extracted = features(held: [:], samples: samples, at: 0.05)
        XCTAssertEqual(extracted.handAlternationRate, 0, accuracy: 0.001)
    }

    func testSeparateClustersAreCounted() {
        let held: [CGKeyCode: TimeInterval] = [12: 0, 13: 0, 40: 0, 37: 0]
        let extracted = features(held: held, samples: [], at: 0.1)
        XCTAssertEqual(extracted.separateClusterCount, 2)
    }

    func testKeyRateIsSustainedNotInstantaneous() {
        // Seven keys inside a fifth of a second is a burst, but over the
        // one-and-a-fifth-second window it is not a sustained rate.
        let samples = (0..<7).map { makeSample(CGKeyCode(3 + $0), time: Double($0) * 0.03, type: .keyDown) }
        let extracted = features(held: [:], samples: samples, at: 0.2)
        XCTAssertEqual(extracted.keyRate, 7 / DetectionRules.generalWindow, accuracy: 0.001)
        XCTAssertLessThan(extracted.keyRate, DetectionRules.humanKeyRateFloor)
    }

    func testLongHoldsAreCountedFromPressTime() {
        // Held for 1.6s, 1.5s and 0.8s respectively at the moment of extraction.
        let held: [CGKeyCode: TimeInterval] = [3: 0, 5: 0.1, 4: 0.8]
        let extracted = features(held: held, samples: [], at: 1.6)
        XCTAssertEqual(extracted.longHeldCount, 3, "all three passed the 0.7s hold threshold")
        XCTAssertEqual(extracted.extendedHeldCount, 2, "only two passed the 1.5s threshold")
        XCTAssertEqual(extracted.maxHoldDuration, 1.6, accuracy: 0.001)
    }

    func testAutorepeatDoesNotInflateTimingFeatures() {
        var samples = [makeSample(3, time: 0, type: .keyDown)]
        for index in 1..<20 {
            samples.append(makeSample(3, time: Double(index) * 0.03, type: .keyDown, isRepeat: true))
        }
        let extracted = features(held: [3: 0], samples: samples, at: 0.6)
        XCTAssertEqual(extracted.keyRate, 1 / DetectionRules.generalWindow, accuracy: 0.001)
        XCTAssertEqual(extracted.synchronyCount, 1)
        XCTAssertFalse(extracted.medianInterval.isFinite)
    }

    func testShortcutModifiersAreDetected() {
        let extracted = features(held: [1: 0], samples: [], at: 0.1, modifiers: .maskCommand)
        XCTAssertTrue(extracted.hasShortcutModifier)
    }

    func testRampIsClampedAtBothEnds() {
        XCTAssertEqual(detectionRamp(0, from: 1, to: 5), 0, accuracy: 0.001)
        XCTAssertEqual(detectionRamp(3, from: 1, to: 5), 0.5, accuracy: 0.001)
        XCTAssertEqual(detectionRamp(9, from: 1, to: 5), 1, accuracy: 0.001)
    }
}
