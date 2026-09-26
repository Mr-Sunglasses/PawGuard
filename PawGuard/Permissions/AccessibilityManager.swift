import AppKit
import ApplicationServices

/// The permission surface the watcher depends on, so its state machine can be
/// tested without touching the real TCC database.
protocol AccessibilityGranting: AnyObject {
    var isTrusted: Bool { get }
    func requestAccess()
    func openSettings()
    func relaunch()
    func resetAccess(completion: @escaping @Sendable (Bool) -> Void)
}

final class AccessibilityManager: AccessibilityGranting {
    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    func requestAccess() {
        // The literal value of `kAXTrustedCheckOptionPrompt`. The imported
        // global is a mutable C variable, which strict concurrency rejects.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openSettings()
    }

    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Quits and reopens PawGuard.
    ///
    /// macOS decides whether a process may create an event tap when it asks,
    /// and it does not always revisit that for a process that was already
    /// running when the permission was granted — most reliably when the
    /// permission was granted to an earlier build of the same bundle, which
    /// leaves an entry that looks enabled in System Settings while every
    /// `tapCreate` still fails. Nothing in-process clears that. A fresh launch
    /// does, so PawGuard offers it rather than telling the user to do it.
    func relaunch() {
        guard let bundleURL = Bundle.main.bundleURL as URL? else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    func resetAccess(completion: @escaping @Sendable (Bool) -> Void) {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.pawguard.app"
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", "Accessibility", bundleIdentifier]

            let succeeded: Bool
            do {
                try process.run()
                process.waitUntilExit()
                succeeded = process.terminationStatus == 0
            } catch {
                succeeded = false
            }

            DispatchQueue.main.async {
                completion(succeeded)
            }
        }
    }
}
