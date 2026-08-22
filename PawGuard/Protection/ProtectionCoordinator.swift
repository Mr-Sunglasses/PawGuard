import AppKit
import Combine
import Foundation

/// Drives the protection lifecycle: the detection engine, the overlay, the
/// monitoring tick, and the statistics that come out of them.
///
/// Split out of `AppState` so that permission handling, profile editing, and
/// protection no longer share one object and one timer.
@MainActor
final class ProtectionCoordinator: ObservableObject {
    @Published private(set) var protectionState: ProtectionState = .monitoring
    @Published private(set) var currentDetection: DetectionResult = .empty
    @Published private(set) var overlayRemaining: TimeInterval = 0
    @Published private(set) var isTestOverlayVisible = false
    @Published private(set) var context = DetectionContext()
    /// Keystrokes the cat landed before protection engaged, available to undo
    /// while the overlay is up.
    @Published private(set) var undoableKeystrokes = 0

    let engine: KeyboardEngine
    let monitor: KeyboardEventMonitor

    private let settingsStore: SettingsStore
    private let statisticsStore: StatisticsStore
    private let calibrationStore: CalibrationStore
    private let overlayController = CatOverlayController()
    private let profileProvider: () -> CatProfile?

    private var timer: Timer?
    private var protectionStartedAt: Date?
    private var lockStartedAt: Date?
    private var pendingBlockedEvents = 0
    private var testOverlayEnd: Date?
    private var contextTickCounter = 0

    /// The context probe does not need to run at the full tick rate.
    ///
    /// The tick itself is fast — re-scoring a handful of held keys — but
    /// reading the frontmost app is slower. Running it on a divisor keeps the
    /// cost per second low while detection latency drops with the tick.
    private static let tickInterval: TimeInterval = DetectionRules.monitorTick
    private static let contextTickDivisor = 10

    init(
        settingsStore: SettingsStore,
        statisticsStore: StatisticsStore,
        calibrationStore: CalibrationStore,
        profileProvider: @escaping () -> CatProfile?
    ) {
        self.settingsStore = settingsStore
        self.statisticsStore = statisticsStore
        self.calibrationStore = calibrationStore
        self.profileProvider = profileProvider

        let settings = settingsStore.settings
        let engine = KeyboardEngine(
            threshold: settings.detectionThreshold,
            extendOnActivity: settings.extendOnActivity,
            lockDuration: settings.lockDuration,
            graceEnabled: settings.useGraceWindow
        )
        self.engine = engine
        monitor = KeyboardEventMonitor(
            handler: { [weak engine] sample in
                engine?.process(sample) ?? true
            },
            interruptionHandler: { [weak engine] in
                engine?.resetDetectionAfterMonitorInterruption()
            }
        )

        engine.onCatDetected = { [weak self] event in
            Task { @MainActor [weak self] in self?.handleDetection(event) }
        }
        engine.onDetectionUpdated = { [weak self] result in
            Task { @MainActor [weak self] in self?.handleDetectionUpdate(result) }
        }
        engine.onBlockedActivity = { [weak self] in
            Task { @MainActor [weak self] in self?.pendingBlockedEvents += 1 }
        }
        engine.onEmergencyUnlock = { [weak self] in
            Task { @MainActor [weak self] in self?.completeManualUnlock(userInitiated: true) }
        }

        timer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    deinit {
        timer?.invalidate()
    }

    var isLocked: Bool { protectionState.isLocked }

    // MARK: - Actions

    func testCatMode() {
        guard !isLocked else { return }
        isTestOverlayVisible = true
        testOverlayEnd = Date().addingTimeInterval(8)
        overlayRemaining = 8
        overlayController.show(
            profile: profileProvider(),
            remaining: overlayRemaining,
            accent: settingsStore.settings.accentTheme,
            total: 8,
            isTest: true,
            undoableKeystrokes: 0,
            onUnlock: { [weak self] in self?.dismissTestOverlay() },
            onUndo: {}
        )
    }

    func unlockNow() {
        guard isLocked else { return }
        engine.unlock()
        completeManualUnlock(userInitiated: true)
    }

    func dismissTestOverlay() {
        testOverlayEnd = nil
        isTestOverlayVisible = false
        overlayController.dismiss()
    }

    /// Removes the keystrokes that reached the app before protection engaged.
    func undoCatTyping() {
        let count = undoableKeystrokes
        guard count > 0 else { return }
        undoableKeystrokes = 0
        overlayController.updateUndoAvailability(false)
        // The lock has to end first, or the synthetic deletes land while input
        // is still being withheld.
        if isLocked { unlockNow() }
        engine.undoDeliveredKeystrokes(count: count)
    }

    func teardownForPermissionLoss() {
        if engine.state.isLocked {
            completeManualUnlock(userInitiated: false)
        }
        engine.reset()
        protectionState = .monitoring
        currentDetection = .empty
        overlayController.dismiss()
    }

    // MARK: - Detection handling

    /// Called for every key event, so it must not redraw the UI for every key
    /// event. Most keystrokes score zero and change nothing worth publishing.
    private func handleDetectionUpdate(_ result: DetectionResult) {
        if result.score != currentDetection.score || result.confidence != currentDetection.confidence {
            currentDetection = result
        }
        if settingsStore.settings.adaptiveCalibration {
            calibrationStore.observe(result.features)
        }
    }

    private func handleDetection(_ event: ProtectionEvent) {
        currentDetection = event.result
        protectionStartedAt = protectionStartedAt ?? .now
        lockStartedAt = .now
        undoableKeystrokes = settingsStore.settings.offerUndo ? event.deliveredKeystrokes : 0
        statisticsStore.recordDetection()
        calibrationStore.recordDetection(event.result)
        if settingsStore.settings.showProtectionOverlay {
            showProtectionOverlay()
        }
        if settingsStore.settings.playProtectionSound {
            NSSound(named: NSSound.Name("Pop"))?.play()
        }
    }

    private func showProtectionOverlay() {
        guard case .locked(let until) = engine.state else { return }
        let remaining = max(0, until.timeIntervalSinceNow)
        overlayRemaining = remaining
        overlayController.show(
            profile: overlayProfile,
            remaining: remaining,
            accent: settingsStore.settings.accentTheme,
            total: settingsStore.settings.lockDuration,
            isTest: false,
            undoableKeystrokes: undoableKeystrokes,
            onUnlock: { [weak self] in self?.unlockNow() },
            onUndo: { [weak self] in self?.undoCatTyping() }
        )
    }

    /// A lock the user kills within seconds was a false positive; one that runs
    /// its course stood. Both are free labels for calibration.
    private func completeManualUnlock(userInitiated: Bool) {
        if let started = protectionStartedAt {
            statisticsStore.recordProtectionDuration(Date().timeIntervalSince(started))
        }
        if userInitiated, settingsStore.settings.adaptiveCalibration, let lockStartedAt {
            let elapsed = Date().timeIntervalSince(lockStartedAt)
            if elapsed <= CalibrationStore.falsePositiveWindow {
                calibrationStore.recordFalsePositive()
                statisticsStore.recordFalsePositive(wasCat: false)
            }
        }
        protectionStartedAt = nil
        lockStartedAt = nil
        undoableKeystrokes = 0
        protectionState = engine.state
        overlayController.dismiss()
        overlayRemaining = 0
    }

    private var overlayProfile: CatProfile? {
        guard let profile = profileProvider() else { return nil }
        guard settingsStore.settings.showCatPhoto else {
            var withoutPhoto = profile
            withoutPhoto.photoPaths = []
            withoutPhoto.selectedAvatarIndex = 0
            return withoutPhoto
        }
        return profile
    }

    // MARK: - Tick

    private func tick() {
        contextTickCounter += 1
        if contextTickCounter.isMultiple(of: Self.contextTickDivisor) {
            context = DetectionContextProbe.current()
        }

        let settings = settingsStore.settings
        let suppressed = context.isProtectionSuppressed(
            disabledBundleIdentifiers: settings.disabledBundleIdentifiers,
            pauseInFullscreen: settings.pauseInFullscreen
        )
        engine.update(
            threshold: calibrationStore.effectiveThreshold(
                base: settings.detectionThreshold,
                adaptive: settings.adaptiveCalibration
            ),
            extendOnActivity: settings.extendOnActivity,
            lockDuration: settings.lockDuration,
            graceEnabled: settings.useGraceWindow,
            protectionSuppressed: suppressed,
            allowedKeySets: settings.adaptiveCalibration ? calibrationStore.allowedKeySets : []
        )

        let now = MonotonicClock.now
        engine.evaluateHeldKeys(at: now)

        if pendingBlockedEvents > 0 {
            statisticsStore.recordBlockedEvents(pendingBlockedEvents)
            pendingBlockedEvents = 0
        }

        if let testOverlayEnd {
            let remaining = testOverlayEnd.timeIntervalSinceNow
            if remaining <= 0 {
                dismissTestOverlay()
            } else {
                overlayRemaining = remaining
                overlayController.update(remaining: remaining)
            }
        }

        let wasLocked = protectionState.isLocked
        let nextState = engine.advance(at: now)
        protectionState = nextState
        if !wasLocked && nextState.isLocked {
            protectionStartedAt = protectionStartedAt ?? .now
            if settingsStore.settings.showProtectionOverlay { showProtectionOverlay() }
        }

        if case .locked(let until) = nextState {
            overlayRemaining = max(0, until.timeIntervalSinceNow)
            if settingsStore.settings.showProtectionOverlay {
                overlayController.update(remaining: overlayRemaining)
            } else {
                overlayController.dismiss()
            }
        } else if wasLocked {
            if let started = protectionStartedAt {
                statisticsStore.recordProtectionDuration(Date().timeIntervalSince(started))
            }
            // The lock ran to completion, so the detection stood.
            if settingsStore.settings.adaptiveCalibration {
                calibrationStore.recordConfirmedDetection()
            }
            protectionStartedAt = nil
            lockStartedAt = nil
            undoableKeystrokes = 0
            overlayController.dismiss()
            overlayRemaining = 0
        }
    }
}
