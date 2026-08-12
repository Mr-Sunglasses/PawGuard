import CoreGraphics
import XCTest

@testable import PawGuard

@MainActor
final class CalibrationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName = ""

    override func setUp() {
        super.setUp()
        suiteName = "pawguard.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func detection(heldKeys: Set<CGKeyCode>, score: Int = 80) -> DetectionResult {
        var features = DetectionFeatures()
        features.heldKeys = heldKeys
        features.simultaneousCount = heldKeys.count
        return DetectionResult(
            score: score,
            signals: [.simultaneousKeys],
            confidence: .cat,
            simultaneousKeyCount: heldKeys.count,
            burstKeyCount: heldKeys.count,
            rapidClusterKeyCount: heldKeys.count,
            heldKeyCount: heldKeys.count,
            hasPhysicalCluster: true,
            isImmediate: false,
            features: features
        )
    }

    func testThresholdStartsAtTheUsersSetting() {
        let store = CalibrationStore(defaults: defaults)
        XCTAssertEqual(store.effectiveThreshold(base: 70, adaptive: true), 70)
    }

    func testFalsePositiveRaisesTheThreshold() {
        let store = CalibrationStore(defaults: defaults)
        store.recordDetection(detection(heldKeys: [3, 5, 4]))
        store.recordFalsePositive()
        XCTAssertEqual(store.effectiveThreshold(base: 70, adaptive: true), 75)
    }

    func testAdaptiveLearningCanBeTurnedOff() {
        let store = CalibrationStore(defaults: defaults)
        store.recordDetection(detection(heldKeys: [3, 5, 4]))
        store.recordFalsePositive()
        XCTAssertEqual(store.effectiveThreshold(base: 70, adaptive: false), 70)
    }

    func testThresholdOffsetIsCapped() {
        let store = CalibrationStore(defaults: defaults)
        for _ in 0..<20 {
            store.recordDetection(detection(heldKeys: [3, 5, 4]))
            store.recordFalsePositive()
        }
        XCTAssertEqual(store.profile.thresholdOffset, CalibrationProfile.maximumOffset)
        XCTAssertLessThanOrEqual(store.effectiveThreshold(base: 95, adaptive: true), 100)
    }

    func testRepeatedFalsePositivesOnTheSameChordAllowlistIt() {
        let store = CalibrationStore(defaults: defaults)
        for _ in 0..<3 {
            store.recordDetection(detection(heldKeys: [3, 5, 4]))
            store.recordFalsePositive()
        }
        XCTAssertEqual(store.allowedKeySets, [Set<CGKeyCode>([3, 5, 4])])
    }

    func testADifferentChordIsNotAllowlisted() {
        let store = CalibrationStore(defaults: defaults)
        store.recordDetection(detection(heldKeys: [3, 5, 4]))
        store.recordFalsePositive()
        store.recordDetection(detection(heldKeys: [38, 40, 37]))
        store.recordFalsePositive()
        XCTAssertTrue(store.allowedKeySets.isEmpty)
    }

    func testAllowlistedChordStopsTriggeringTheDetector() {
        let detector = CatDetector()
        var result = DetectionResult.empty
        for (index, key) in [3, 5, 4, 38].enumerated() {
            result = detector.process(makeSample(CGKeyCode(key), time: Double(index) * 0.02, type: .keyDown))
        }
        XCTAssertEqual(result.confidence, .cat)

        let calibrated = CatDetector()
        calibrated.allowedKeySets = [Set<CGKeyCode>([3, 5, 4, 38])]
        var calibratedResult = DetectionResult.empty
        for (index, key) in [3, 5, 4, 38].enumerated() {
            calibratedResult = calibrated.process(makeSample(CGKeyCode(key), time: Double(index) * 0.02, type: .keyDown))
        }
        XCTAssertNotEqual(calibratedResult.confidence, .cat)
    }

    func testConfirmedDetectionsDecayARaisedThreshold() {
        let store = CalibrationStore(defaults: defaults)
        store.recordDetection(detection(heldKeys: [3, 5, 4]))
        store.recordFalsePositive()
        XCTAssertEqual(store.profile.thresholdOffset, 5)

        for _ in 0..<3 {
            store.recordDetection(detection(heldKeys: [3, 5, 4]))
            store.recordConfirmedDetection()
        }
        XCTAssertLessThan(store.profile.thresholdOffset, 5)
    }

    func testPassiveObservationRaisesTheBarForHeavyOverlappers() {
        let store = CalibrationStore(defaults: defaults)
        var features = DetectionFeatures()
        features.simultaneousCount = 3
        features.keyRate = 9
        for _ in 0..<400 {
            store.observe(features)
        }
        XCTAssertGreaterThan(store.profile.thresholdOffset, 0)
    }

    func testPassiveObservationLeavesLightOverlappersAlone() {
        let store = CalibrationStore(defaults: defaults)
        var features = DetectionFeatures()
        features.simultaneousCount = 1
        for _ in 0..<400 {
            store.observe(features)
        }
        XCTAssertEqual(store.profile.thresholdOffset, 0)
    }

    func testHistoryIsCappedAndPersisted() {
        let store = CalibrationStore(defaults: defaults)
        for _ in 0..<40 {
            store.recordDetection(detection(heldKeys: [3, 5, 4]))
        }
        XCTAssertLessThanOrEqual(store.recentDetections.count, 25)

        let reloaded = CalibrationStore(defaults: defaults)
        XCTAssertEqual(reloaded.recentDetections.count, store.recentDetections.count)
    }

    func testSnapshotsCarryNoTextOnlyShape() throws {
        let store = CalibrationStore(defaults: defaults)
        store.recordDetection(detection(heldKeys: [3, 5, 4]))
        let snapshot = try XCTUnwrap(store.recentDetections.first)
        XCTAssertEqual(snapshot.heldKeys, [3, 4, 5])
        XCTAssertEqual(snapshot.simultaneousCount, 3)
        // The record is key codes and scores; nothing here can reconstruct text.
        let encoded = try JSONEncoder().encode(snapshot)
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertFalse(json.contains("character"))
    }

    func testResetClearsEverythingLearned() {
        let store = CalibrationStore(defaults: defaults)
        for _ in 0..<3 {
            store.recordDetection(detection(heldKeys: [3, 5, 4]))
            store.recordFalsePositive()
        }
        store.resetLearning()
        XCTAssertEqual(store.profile, CalibrationProfile())
        XCTAssertTrue(store.recentDetections.isEmpty)
        XCTAssertTrue(store.allowedKeySets.isEmpty)
    }
}
