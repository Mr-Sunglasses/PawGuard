import AppKit
import Combine
import Foundation

/// Tracks Accessibility trust and keeps the keyboard monitor's lifecycle in
/// step with it.
///
/// macOS has no direct observer for a permission change, but it does post a
/// distributed notification, and permission is almost always granted while the
/// user is away in System Settings. Reacting to those two events plus a slow
/// fallback poll replaces checking `AXIsProcessTrusted` four times a second.
@MainActor
final class AccessibilityWatcher: ObservableObject {
    @Published private(set) var isTrusted = false
    @Published private(set) var monitoringAvailable = false
    @Published private(set) var isResetting = false
    @Published private(set) var resetMessage: String?

    let manager: AccessibilityManager

    /// Called when monitoring must stop, so protection can be torn down.
    var onMonitoringLost: (() -> Void)?

    private let monitor: KeyboardEventMonitor
    private var fallbackTimer: Timer?
    private var observers: [Any] = []

    private static let fallbackInterval: TimeInterval = 2

    init(monitor: KeyboardEventMonitor, manager: AccessibilityManager = AccessibilityManager()) {
        self.monitor = monitor
        self.manager = manager

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }
        )
        observers.append(
            DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name("com.apple.accessibility.api"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }
        )

        fallbackTimer = Timer.scheduledTimer(withTimeInterval: Self.fallbackInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        refresh()
    }

    deinit {
        fallbackTimer?.invalidate()
    }

    var repairNeeded: Bool {
        !isTrusted || !monitoringAvailable
    }

    var startError: String? {
        monitor.lastStartError
    }

    func refresh() {
        let trusted = manager.isTrusted
        isTrusted = trusted

        if trusted {
            if !monitor.isRunning {
                monitoringAvailable = monitor.start()
            } else {
                monitoringAvailable = true
            }
        } else if monitoringAvailable || monitor.isRunning {
            monitoringAvailable = false
            monitor.stop()
            onMonitoringLost?()
        }
    }

    func requestAccess() {
        manager.requestAccess()
        refresh()
    }

    func resetPermission(onTeardown: () -> Void) {
        guard !isResetting else { return }
        isResetting = true
        resetMessage = nil
        monitor.stop()
        monitoringAvailable = false
        isTrusted = false
        onTeardown()

        manager.resetAccess { [weak self] succeeded in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isResetting = false
                self.resetMessage =
                    succeeded
                    ? "Accessibility permission reset. Enable PawGuard again in System Settings."
                    : "PawGuard could not reset the permission. You can manage it in System Settings."
                self.refresh()
                self.manager.openSettings()
            }
        }
    }

    func stopMonitoring() {
        monitor.stop()
        monitoringAvailable = false
    }
}
