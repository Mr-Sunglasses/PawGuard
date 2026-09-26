import XCTest

@testable import PawGuard

/// Stands in for the real TCC surface.
private final class FakeAccessibilityManager: AccessibilityGranting {
    var isTrusted = false
    var requestCount = 0
    var openSettingsCount = 0
    var relaunchCount = 0

    func requestAccess() { requestCount += 1 }
    func openSettings() { openSettingsCount += 1 }
    func relaunch() { relaunchCount += 1 }
    func resetAccess(completion: @escaping @Sendable (Bool) -> Void) { completion(true) }
}

/// Stands in for the event tap, so nothing here touches the real keyboard.
private final class FakeKeyboardMonitor: KeyboardMonitoring {
    /// What `start()` will report. Set false to model macOS refusing the tap
    /// even though it says the process is trusted.
    var canStart = true
    /// Whether an already-running tap is still enabled.
    var tapEnabled = true

    private(set) var startCallCount = 0
    private(set) var recoverCallCount = 0
    private(set) var stopCallCount = 0

    var isRunning = false
    var lastStartError: String?

    var isTapActive: Bool { isRunning && tapEnabled }

    @discardableResult
    func start() -> Bool {
        startCallCount += 1
        isRunning = canStart
        return canStart
    }

    func stop() {
        stopCallCount += 1
        isRunning = false
    }

    func recover() {
        recoverCallCount += 1
        if tapEnabled { return }
        isRunning = canStart
        tapEnabled = canStart
    }
}

@MainActor
final class AccessibilityWatcherTests: XCTestCase {
    private var monitor: FakeKeyboardMonitor!
    private var manager: FakeAccessibilityManager!

    private func makeWatcher(adHocSigned: Bool = false) -> AccessibilityWatcher {
        monitor = FakeKeyboardMonitor()
        manager = FakeAccessibilityManager()
        return AccessibilityWatcher(
            monitor: monitor,
            manager: manager,
            pollsSystemState: false,
            hasUnstableSignature: adHocSigned
        )
    }

    func testUngrantedPermissionReportsNothingToRepairYet() {
        let watcher = makeWatcher()
        XCTAssertFalse(watcher.isTrusted)
        XCTAssertFalse(watcher.monitoringAvailable)
        XCTAssertEqual(watcher.stage, .notGranted)
        XCTAssertEqual(monitor.startCallCount, 0, "there is no point starting a tap that will be refused")
    }

    func testGrantingPermissionStartsMonitoringOnTheNextRefresh() {
        let watcher = makeWatcher()
        manager.isTrusted = true

        watcher.refresh()

        XCTAssertTrue(watcher.isTrusted)
        XCTAssertTrue(watcher.monitoringAvailable)
        XCTAssertEqual(watcher.stage, .ready)
        XCTAssertFalse(watcher.repairNeeded)
    }

    func testAskingForAccessMovesOutOfTheUnaskedState() {
        let watcher = makeWatcher()
        watcher.requestAccess()

        XCTAssertEqual(manager.requestCount, 1)
        XCTAssertEqual(watcher.stage, .awaitingGrant, "the user is in System Settings; keep waiting rather than re-asking")
    }

    /// The reported bug: macOS says PawGuard is trusted, but every attempt to
    /// create the tap fails, and nothing in-process ever clears it.
    func testATrustedProcessThatCannotTapEventuallyAsksForARelaunch() {
        let watcher = makeWatcher()
        manager.isTrusted = true
        monitor.canStart = false

        watcher.refresh()
        XCTAssertEqual(watcher.stage, .awaitingGrant, "one failure could just be a grant still settling")

        watcher.refresh()
        watcher.refresh()

        XCTAssertEqual(watcher.stage, .needsRelaunch)
        XCTAssertTrue(watcher.repairNeeded)
        XCTAssertFalse(watcher.monitoringAvailable)
    }

    func testASucceedingStartClearsAnEarlierFailure() {
        let watcher = makeWatcher()
        manager.isTrusted = true
        monitor.canStart = false
        watcher.refresh()
        watcher.refresh()

        monitor.canStart = true
        watcher.refresh()

        XCTAssertEqual(watcher.stage, .ready)
        XCTAssertTrue(watcher.monitoringAvailable)
    }

    /// A permission granted while the app runs must not be judged by the
    /// failures it accumulated while it was still being refused.
    func testFailuresWhileUntrustedDoNotCountTowardsARelaunch() {
        let watcher = makeWatcher()
        monitor.canStart = false
        for _ in 0..<5 { watcher.refresh() }

        manager.isTrusted = true
        watcher.refresh()

        XCTAssertNotEqual(watcher.stage, .needsRelaunch, "the count should restart when permission appears")
    }

    /// `isRunning` stays true for a tap macOS switched off underneath us, so a
    /// watcher that trusted it would keep claiming to be protecting the user.
    func testATapDisabledUnderneathIsNoticedAndRecovered() {
        let watcher = makeWatcher()
        manager.isTrusted = true
        watcher.refresh()
        XCTAssertTrue(watcher.monitoringAvailable)

        monitor.tapEnabled = false
        watcher.refresh()

        XCTAssertEqual(monitor.recoverCallCount, 1, "a dead tap should be rebuilt, not reported as healthy")
        XCTAssertTrue(watcher.monitoringAvailable, "recovery brought it back")
        XCTAssertEqual(watcher.stage, .ready)
    }

    func testAnUnrecoverableTapIsReportedAsUnavailable() {
        let watcher = makeWatcher()
        manager.isTrusted = true
        watcher.refresh()

        monitor.tapEnabled = false
        monitor.canStart = false
        watcher.refresh()

        XCTAssertFalse(watcher.monitoringAvailable)
        XCTAssertTrue(watcher.repairNeeded)
    }

    // MARK: - Ad-hoc builds

    /// An ad-hoc build's grant is bound to the exact binary, so a rebuild voids
    /// it while System Settings still shows an enabled row for the old one.
    /// Waiting quietly in that state waits forever.
    func testAnAdHocBuildSaysSoInsteadOfWaitingForever() {
        let watcher = makeWatcher(adHocSigned: true)
        watcher.requestAccess()

        XCTAssertEqual(watcher.stage, .unstableSignature)
        XCTAssertTrue(watcher.repairNeeded)
    }

    func testAnAdHocBuildIsSilentUntilPermissionIsActuallyAskedFor() {
        let watcher = makeWatcher(adHocSigned: true)
        XCTAssertEqual(watcher.stage, .notGranted, "nothing has gone wrong yet")
    }

    /// The signature only explains a grant that will not take. Once macOS does
    /// trust the process, how it was signed stops mattering.
    func testAnAdHocBuildThatIsTrustedBehavesNormally() {
        let watcher = makeWatcher(adHocSigned: true)
        watcher.requestAccess()
        manager.isTrusted = true

        watcher.refresh()

        XCTAssertEqual(watcher.stage, .ready)
        XCTAssertTrue(watcher.monitoringAvailable)
    }

    func testASignedBuildStillWaitsNormally() {
        let watcher = makeWatcher(adHocSigned: false)
        watcher.requestAccess()

        XCTAssertEqual(watcher.stage, .awaitingGrant)
    }

    func testLosingPermissionTearsProtectionDown() {
        let watcher = makeWatcher()
        var teardownCount = 0
        watcher.onMonitoringLost = { teardownCount += 1 }
        manager.isTrusted = true
        watcher.refresh()

        manager.isTrusted = false
        watcher.refresh()

        XCTAssertEqual(teardownCount, 1)
        XCTAssertFalse(watcher.monitoringAvailable)
        XCTAssertGreaterThan(monitor.stopCallCount, 0)
    }
}
