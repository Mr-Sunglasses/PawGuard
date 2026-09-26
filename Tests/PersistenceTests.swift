import XCTest

@testable import PawGuard

/// Stored settings must survive an upgrade that adds a field. Synthesized
/// `Decodable` treats a missing key as an error, which used to reset every
/// preference — onboarding included — the first time a new build launched.
@MainActor
final class PersistenceTests: XCTestCase {
    // Written by the nonisolated `setUp` and `tearDown` XCTest calls around
    // each main-actor test, never concurrently with one.
    nonisolated(unsafe) private var defaults: UserDefaults!
    nonisolated(unsafe) private var suiteName = ""

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

    func testSettingsFromAnOlderBuildKeepTheirValues() {
        // What a build from before the grace window and undo existed saved.
        let stored = #"{"hasCompletedOnboarding":true,"lockDuration":45,"customThreshold":82,"sensitivity":"custom"}"#
        defaults.set(Data(stored.utf8), forKey: "pawguard.settings")

        let settings = SettingsStore(defaults: defaults).settings
        XCTAssertTrue(settings.hasCompletedOnboarding)
        XCTAssertEqual(settings.lockDuration, 45)
        XCTAssertEqual(settings.detectionThreshold, 82)
        XCTAssertTrue(settings.useGraceWindow, "a field the old build never saved takes its default")
    }

    func testStatisticsFromAnOlderBuildKeepTheirCounts() {
        let stored = #"{"detectionCount":12,"blockedEventCount":340,"totalProtectionDuration":95}"#
        defaults.set(Data(stored.utf8), forKey: "pawguard.statistics")

        let stats = StatisticsStore(defaults: defaults).stats
        XCTAssertEqual(stats.detectionCount, 12)
        XCTAssertEqual(stats.blockedEventCount, 340)
        XCTAssertEqual(stats.falseAlarmCount, 0)
    }

    func testUnreadableDataFallsBackToDefaults() {
        defaults.set(Data("not json".utf8), forKey: "pawguard.settings")
        XCTAssertEqual(SettingsStore(defaults: defaults).settings, PawGuardSettings())
    }

    func testAnInvalidValueStillFailsRatherThanGuessing() {
        let stored = #"{"sensitivity":"reckless"}"#
        XCTAssertNil(
            LenientDecoding.decode(PawGuardSettings.self, from: Data(stored.utf8), fallback: PawGuardSettings())
        )
    }
}
