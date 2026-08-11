import AppKit
import Combine
import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    let settingsStore: SettingsStore
    let profileStore: CatProfileStore
    let statisticsStore: StatisticsStore
    let photoManager: CatPhotoManager
    let accessibilityManager: AccessibilityManager

    @Published private(set) var protectionState: ProtectionState = .monitoring
    @Published private(set) var accessibilityEnabled = false
    @Published private(set) var keyboardMonitoringAvailable = false
    @Published private(set) var isResettingAccessibility = false
    @Published private(set) var accessibilityResetMessage: String?
    @Published private(set) var currentDetection: DetectionResult = .empty
    @Published private(set) var overlayRemaining: TimeInterval = 0
    @Published private(set) var isTestOverlayVisible = false

    private let keyboardEngine: KeyboardEngine
    private let keyboardMonitor: KeyboardEventMonitor
    private let overlayController: CatOverlayController
    private var timer: Timer?
    private var protectionStartedAt: Date?
    private var pendingBlockedEvents = 0
    private var testOverlayEnd: Date?
    private var lastAccessibilityState = false
    private var storeCancellables = Set<AnyCancellable>()

    init() {
        let settingsStore = SettingsStore()
        let profileStore = CatProfileStore()
        let statisticsStore = StatisticsStore()
        self.settingsStore = settingsStore
        self.profileStore = profileStore
        self.statisticsStore = statisticsStore
        photoManager = CatPhotoManager()
        accessibilityManager = AccessibilityManager()

        let settings = settingsStore.settings
        let engine = KeyboardEngine(
            threshold: settings.detectionThreshold,
            extendOnActivity: settings.extendOnActivity,
            lockDuration: settings.lockDuration
        )
        keyboardEngine = engine
        keyboardMonitor = KeyboardEventMonitor { [weak engine] sample in
            engine?.process(sample) ?? true
        }
        overlayController = CatOverlayController()

        settingsStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &storeCancellables)
        profileStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &storeCancellables)
        statisticsStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &storeCancellables)

        engine.onCatDetected = { [weak self] result in
            Task { @MainActor [weak self] in
                self?.handleDetection(result)
            }
        }
        engine.onBlockedActivity = { [weak self] in
            Task { @MainActor [weak self] in
                self?.pendingBlockedEvents += 1
            }
        }
        engine.onEmergencyUnlock = { [weak self] in
            Task { @MainActor [weak self] in
                self?.completeManualUnlock()
            }
        }

        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        refreshAccessibility()
    }

    deinit {
        timer?.invalidate()
        keyboardMonitor.stop()
    }

    var activeCat: CatProfile? { profileStore.activeProfile }

    var needsOnboarding: Bool {
        !settingsStore.settings.hasCompletedOnboarding || activeCat == nil
    }

    var isLocked: Bool { protectionState.isLocked }

    var statusTitle: String {
        if !keyboardMonitoringAvailable { return "Protection unavailable" }
        if isLocked { return "Protected" }
        return "Watching for tiny paws"
    }

    var statusSubtitle: String {
        if !accessibilityEnabled { return "Accessibility permission is required to enable protection." }
        if !keyboardMonitoringAvailable { return "PawGuard cannot start its keyboard monitor. Use a signed build or repair permission." }
        if isLocked { return "Keyboard input is temporarily paused." }
        if let activeCat { return "Watching for \(activeCat.displayName)'s paws" }
        return "Create a cat profile to personalize PawGuard"
    }

    var accessibilityRepairNeeded: Bool {
        !accessibilityEnabled || !keyboardMonitoringAvailable
    }

    func refreshAccessibility() {
        let trusted = accessibilityManager.isTrusted
        lastAccessibilityState = trusted
        accessibilityEnabled = trusted
        if trusted && !keyboardMonitor.isRunning {
            keyboardMonitoringAvailable = keyboardMonitor.start()
        } else if !trusted {
            keyboardMonitoringAvailable = false
            keyboardMonitor.stop()
        }
    }

    func requestAccessibility() {
        accessibilityManager.requestAccess()
        refreshAccessibility()
    }

    func resetAccessibilityPermission() {
        guard !isResettingAccessibility else { return }
        isResettingAccessibility = true
        accessibilityResetMessage = nil
        keyboardMonitor.stop()
        keyboardMonitoringAvailable = false
        accessibilityEnabled = false
        lastAccessibilityState = false

        if keyboardEngine.state.isLocked {
            completeManualUnlock()
        }
        keyboardEngine.reset()
        protectionState = .monitoring
        overlayController.dismiss()

        accessibilityManager.resetAccess { [weak self] succeeded in
            guard let self else { return }
            self.isResettingAccessibility = false
            self.accessibilityResetMessage =
                succeeded
                ? "Accessibility permission reset. Enable PawGuard again in System Settings."
                : "PawGuard could not reset the permission. You can manage it in System Settings."
            self.refreshAccessibility()
            self.accessibilityManager.openSettings()
        }
    }

    func completeOnboarding() {
        settingsStore.settings.hasCompletedOnboarding = true
        settingsStore.save()
    }

    func createCatProfile(named name: String) -> CatProfile {
        profileStore.createProfile(name: name)
    }

    func importPhotos(_ urls: [URL], for profileID: UUID? = nil) {
        guard let profileID = profileID ?? activeCat?.id else { return }
        let existingCount = profileStore.profiles.first(where: { $0.id == profileID })?.photoPaths.count ?? 0
        let remainingSlots = max(0, 5 - existingCount)
        let imported = urls.prefix(remainingSlots).compactMap { url -> ImportedCatPhoto? in
            guard ["jpg", "jpeg", "png", "heic"].contains(url.pathExtension.lowercased()) else { return nil }
            let access = url.startAccessingSecurityScopedResource()
            defer {
                if access { url.stopAccessingSecurityScopedResource() }
            }
            return photoManager.importPhotos(from: [url], for: profileID).first
        }
        guard var profile = profileStore.profiles.first(where: { $0.id == profileID }), !imported.isEmpty else { return }
        profile.photoPaths.append(contentsOf: imported.map(\.avatarPath))
        profileStore.update(profile)
    }

    func selectAvatar(at index: Int) {
        profileStore.selectPhoto(at: index)
    }

    func removePhoto(at index: Int) {
        guard let profile = activeCat, profile.photoPaths.indices.contains(index) else { return }
        photoManager.deletePhoto(atPath: profile.photoPaths[index])
        profileStore.removePhoto(at: index)
    }

    func updateActiveCatName(_ name: String) {
        profileStore.updateActiveName(name)
    }

    func updateCatName(_ name: String, profileID: UUID) {
        profileStore.updateName(name, for: profileID)
    }

    func testCatMode() {
        guard !isLocked else { return }
        isTestOverlayVisible = true
        testOverlayEnd = Date().addingTimeInterval(8)
        overlayRemaining = 8
        overlayController.show(
            profile: activeCat,
            remaining: overlayRemaining,
            accent: settingsStore.settings.accentTheme,
            total: 8,
            isTest: true,
            onUnlock: { [weak self] in self?.dismissTestOverlay() }
        )
    }

    func unlockNow() {
        guard isLocked else { return }
        keyboardEngine.unlock()
        completeManualUnlock()
    }

    func dismissTestOverlay() {
        testOverlayEnd = nil
        isTestOverlayVisible = false
        overlayController.dismiss()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                settingsStore.settings.launchAtLogin = enabled
            } catch {
                settingsStore.settings.launchAtLogin = false
            }
        } else {
            settingsStore.settings.launchAtLogin = false
        }
    }

    private func handleDetection(_ result: DetectionResult) {
        currentDetection = result
        protectionStartedAt = protectionStartedAt ?? .now
        statisticsStore.recordDetection()
        if settingsStore.settings.showProtectionOverlay {
            showProtectionOverlay()
        }
        if settingsStore.settings.playProtectionSound {
            NSSound(named: NSSound.Name("Pop"))?.play()
        }
    }

    private func showProtectionOverlay() {
        guard case .locked(let until) = keyboardEngine.state else { return }
        let remaining = max(0, until.timeIntervalSinceNow)
        overlayRemaining = remaining
        overlayController.show(
            profile: overlayProfile,
            remaining: remaining,
            accent: settingsStore.settings.accentTheme,
            total: settingsStore.settings.lockDuration,
            isTest: false,
            onUnlock: { [weak self] in self?.unlockNow() }
        )
    }

    private func completeManualUnlock() {
        if let started = protectionStartedAt {
            statisticsStore.recordProtectionDuration(Date().timeIntervalSince(started))
        }
        protectionStartedAt = nil
        protectionState = keyboardEngine.state
        overlayController.dismiss()
        overlayRemaining = 0
    }

    private var overlayProfile: CatProfile? {
        guard let profile = activeCat else { return nil }
        guard settingsStore.settings.showCatPhoto else {
            var withoutPhoto = profile
            withoutPhoto.photoPaths = []
            withoutPhoto.selectedAvatarIndex = 0
            return withoutPhoto
        }
        return profile
    }

    private func tick() {
        refreshAccessibilityIfNeeded()
        keyboardEngine.update(
            threshold: settingsStore.settings.detectionThreshold,
            extendOnActivity: settingsStore.settings.extendOnActivity,
            lockDuration: settingsStore.settings.lockDuration
        )

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
        let nextState = keyboardEngine.advance()
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
            protectionStartedAt = nil
            overlayController.dismiss()
            overlayRemaining = 0
        }

        if case .monitoring = nextState, !wasLocked {
            currentDetection = .empty
        }
    }

    private func refreshAccessibilityIfNeeded() {
        let trusted = accessibilityManager.isTrusted
        if trusted != lastAccessibilityState || (trusted && !keyboardMonitor.isRunning) {
            refreshAccessibility()
        }
        if !trusted && keyboardMonitor.isRunning {
            keyboardMonitor.stop()
            keyboardMonitoringAvailable = false
            if keyboardEngine.state.isLocked {
                keyboardEngine.unlock()
                completeManualUnlock()
            }
        }
    }
}
