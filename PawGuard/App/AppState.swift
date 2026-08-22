import AppKit
import Combine
import Foundation
import ServiceManagement
import SwiftUI

/// Composes the app's stores and the two objects that do the real work:
/// `ProtectionCoordinator` for detection and locking, `AccessibilityWatcher`
/// for permission and monitor lifecycle. Everything here is presentation glue.
@MainActor
final class AppState: ObservableObject {
    let settingsStore: SettingsStore
    let profileStore: CatProfileStore
    let statisticsStore: StatisticsStore
    let calibrationStore: CalibrationStore
    let photoManager: CatPhotoManager
    let protection: ProtectionCoordinator
    let accessibility: AccessibilityWatcher

    private var storeCancellables = Set<AnyCancellable>()

    init() {
        let settingsStore = SettingsStore()
        let profileStore = CatProfileStore()
        let statisticsStore = StatisticsStore()
        let calibrationStore = CalibrationStore()
        self.settingsStore = settingsStore
        self.profileStore = profileStore
        self.statisticsStore = statisticsStore
        self.calibrationStore = calibrationStore
        photoManager = CatPhotoManager()

        let protection = ProtectionCoordinator(
            settingsStore: settingsStore,
            statisticsStore: statisticsStore,
            calibrationStore: calibrationStore,
            profileProvider: { [weak profileStore] in profileStore?.activeProfile }
        )
        self.protection = protection
        accessibility = AccessibilityWatcher(monitor: protection.monitor)
        accessibility.onMonitoringLost = { [weak protection] in
            protection?.teardownForPermissionLoss()
        }

        for publisher in [
            settingsStore.objectWillChange.eraseToAnyPublisher(),
            profileStore.objectWillChange.eraseToAnyPublisher(),
            statisticsStore.objectWillChange.eraseToAnyPublisher(),
            calibrationStore.objectWillChange.eraseToAnyPublisher(),
            protection.objectWillChange.eraseToAnyPublisher(),
            accessibility.objectWillChange.eraseToAnyPublisher(),
        ] {
            publisher
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &storeCancellables)
        }
    }

    var accessibilityManager: AccessibilityGranting { accessibility.manager }

    // MARK: - Protection

    var protectionState: ProtectionState { protection.protectionState }
    var currentDetection: DetectionResult { protection.currentDetection }
    var overlayRemaining: TimeInterval { protection.overlayRemaining }
    var isTestOverlayVisible: Bool { protection.isTestOverlayVisible }
    var isLocked: Bool { protection.isLocked }
    var undoableKeystrokes: Int { protection.undoableKeystrokes }
    var detectionContext: DetectionContext { protection.context }

    func testCatMode() { protection.testCatMode() }
    func unlockNow() { protection.unlockNow() }
    func dismissTestOverlay() { protection.dismissTestOverlay() }
    func undoCatTyping() { protection.undoCatTyping() }

    // MARK: - Permissions

    var accessibilityEnabled: Bool { accessibility.isTrusted }
    var keyboardMonitoringAvailable: Bool { accessibility.monitoringAvailable }
    var isResettingAccessibility: Bool { accessibility.isResetting }
    var accessibilityResetMessage: String? { accessibility.resetMessage }
    var accessibilityRepairNeeded: Bool { accessibility.repairNeeded }
    var accessibilityStage: AccessibilityStage { accessibility.stage }

    func refreshAccessibility() { accessibility.refresh() }
    func requestAccessibility() { accessibility.requestAccess() }
    func openAccessibilitySettings() { accessibilityManager.openSettings() }
    func relaunchForAccessibility() { accessibility.relaunch() }

    func resetAccessibilityPermission() {
        accessibility.resetPermission { [weak self] in
            self?.protection.teardownForPermissionLoss()
        }
    }

    // MARK: - Status

    var activeCat: CatProfile? { profileStore.activeProfile }

    var needsOnboarding: Bool {
        !settingsStore.settings.hasCompletedOnboarding || activeCat == nil
    }

    /// Whether setup still has to be put in front of the user at launch.
    ///
    /// Lives here rather than in the menu bar label's own state because SwiftUI
    /// may rebuild that label at any time; a flag stored there would reset with
    /// it and pull the window back in front of whatever the user was doing.
    private var hasOfferedSetup = false

    func shouldOfferSetupOnLaunch() -> Bool {
        guard !hasOfferedSetup, needsOnboarding else { return false }
        hasOfferedSetup = true
        return true
    }

    /// True while macOS secure input is on. No event tap receives key events in
    /// that state, so claiming to be watching would be a lie.
    var isSecureInputActive: Bool { protection.context.isSecureInputEnabled }

    var isProtectionPaused: Bool {
        protection.context.isProtectionSuppressed(
            disabledBundleIdentifiers: settingsStore.settings.disabledBundleIdentifiers,
            pauseInFullscreen: settingsStore.settings.pauseInFullscreen
        )
    }

    var statusTitle: String {
        if !keyboardMonitoringAvailable { return "Protection unavailable" }
        if isLocked { return "Protected" }
        if isSecureInputActive { return "Paused for secure input" }
        if isProtectionPaused { return "Paused for this app" }
        return "Watching for tiny paws"
    }

    var statusSubtitle: String {
        if !accessibilityEnabled { return "Accessibility permission is required to enable protection." }
        if !keyboardMonitoringAvailable {
            return "PawGuard cannot start its keyboard monitor. Use a signed build or repair permission."
        }
        if isLocked { return "Keyboard input is temporarily paused." }
        if isSecureInputActive {
            return "A password field has secure input turned on, so no app can observe the keyboard."
        }
        if isProtectionPaused {
            let name = protection.context.frontmostApplicationName ?? "this app"
            return "PawGuard is standing down while \(name) is frontmost."
        }
        if let activeCat { return "Watching for \(activeCat.displayName)'s paws" }
        return "Create a cat profile to personalize PawGuard"
    }

    // MARK: - Profiles

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
        guard var profile = profileStore.profiles.first(where: { $0.id == profileID }), !imported.isEmpty else {
            return
        }
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

    // MARK: - App rules

    func disableProtection(forBundleIdentifier identifier: String) {
        guard !settingsStore.settings.disabledBundleIdentifiers.contains(identifier) else { return }
        settingsStore.settings.disabledBundleIdentifiers.append(identifier)
    }

    func enableProtection(forBundleIdentifier identifier: String) {
        settingsStore.settings.disabledBundleIdentifiers.removeAll { $0 == identifier }
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
}
