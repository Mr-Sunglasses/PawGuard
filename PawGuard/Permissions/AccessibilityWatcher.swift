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
/// What the user needs to do next, if anything.
enum AccessibilityStage: Equatable {
    /// Permission has not been granted, and PawGuard has not asked yet.
    case notGranted
    /// The prompt is up or System Settings is open; PawGuard is waiting.
    case awaitingGrant
    /// Granted, and the keyboard monitor is live. Nothing to do.
    case ready
    /// Granted, but macOS keeps refusing the event tap. Only a relaunch clears
    /// this.
    case needsRelaunch
    /// The grant cannot stick, because this build is ad-hoc signed and the
    /// permission is bound to a binary that the next build replaces.
    case unstableSignature
}

@MainActor
final class AccessibilityWatcher: ObservableObject {
    @Published private(set) var isTrusted = false
    @Published private(set) var monitoringAvailable = false
    @Published private(set) var isResetting = false
    @Published private(set) var resetMessage: String?
    @Published private(set) var stage: AccessibilityStage = .notGranted

    /// Set once the user has been sent to System Settings, so the UI can say
    /// "waiting for you" instead of repeating the same instruction.
    private var hasRequestedAccess = false
    /// Consecutive failures to bring the tap up while macOS says we are
    /// trusted. A grant that has genuinely taken effect works on the first try,
    /// so a run of failures means the grant is stale rather than slow.
    private var failedStartAttempts = 0
    private static let failedStartsBeforeRelaunch = 3

    let manager: AccessibilityGranting

    /// Called when monitoring must stop, so protection can be torn down.
    var onMonitoringLost: (() -> Void)?

    private let monitor: KeyboardMonitoring
    private var fallbackTimer: Timer?
    private var observers: [Any] = []

    private static let fallbackInterval: TimeInterval = 2

    /// True when this build's Accessibility grant cannot outlive a rebuild.
    private let hasUnstableSignature: Bool

    /// `pollsSystemState` is off in tests, which drive `refresh()` by hand
    /// rather than waiting on a timer or on notifications from the real system.
    init(
        monitor: KeyboardMonitoring,
        manager: AccessibilityGranting = AccessibilityManager(),
        pollsSystemState: Bool = true,
        hasUnstableSignature: Bool = CodeSignatureInfo.isAdHocSigned
    ) {
        self.monitor = monitor
        self.manager = manager
        self.hasUnstableSignature = hasUnstableSignature

        guard pollsSystemState else {
            refresh()
            return
        }

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

        // `.common` matters: a timer left in the default mode stops firing while
        // a menu or a scroll is tracking, which is exactly when the menu bar is
        // open and the user is looking at the status it is supposed to keep
        // current.
        let timer = Timer(timeInterval: Self.fallbackInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        fallbackTimer = timer
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
        let wasTrusted = isTrusted
        isTrusted = trusted

        guard trusted else {
            if monitoringAvailable || monitor.isRunning {
                monitoringAvailable = false
                monitor.stop()
                onMonitoringLost?()
            }
            failedStartAttempts = 0
            // Having asked and still not been trusted is the moment the ad-hoc
            // case becomes worth raising: the grant the user just made was
            // bound to a binary that no longer exists, so waiting quietly would
            // wait forever.
            if hasRequestedAccess {
                stage = hasUnstableSignature ? .unstableSignature : .awaitingGrant
            } else {
                stage = .notGranted
            }
            return
        }

        // Permission just appeared. Anything the monitor learned while it was
        // being refused is stale, so start counting attempts afresh.
        if !wasTrusted {
            failedStartAttempts = 0
        }

        // `isRunning` is not enough. A tap macOS disabled underneath us leaves
        // the port in place, so a monitor that has stopped seeing keystrokes
        // would otherwise keep reporting itself as available.
        if monitor.isRunning, !monitor.isTapActive {
            monitor.recover()
        }

        if !monitor.isRunning {
            let started = monitor.start()
            monitoringAvailable = started
            failedStartAttempts = started ? 0 : failedStartAttempts + 1
        } else {
            monitoringAvailable = monitor.isTapActive
            if monitoringAvailable { failedStartAttempts = 0 }
        }

        if monitoringAvailable {
            stage = .ready
        } else {
            stage = failedStartAttempts >= Self.failedStartsBeforeRelaunch ? .needsRelaunch : .awaitingGrant
        }
    }

    func requestAccess() {
        hasRequestedAccess = true
        manager.requestAccess()
        refresh()
    }

    /// Quits and reopens PawGuard so macOS re-evaluates the event tap.
    func relaunch() {
        manager.relaunch()
    }

    func resetPermission(onTeardown: () -> Void) {
        guard !isResetting else { return }
        isResetting = true
        resetMessage = nil
        monitor.stop()
        monitoringAvailable = false
        isTrusted = false
        // The user is being sent back to System Settings to grant it again, so
        // the next refusal is expected rather than a stale grant.
        hasRequestedAccess = true
        failedStartAttempts = 0
        stage = .awaitingGrant
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
