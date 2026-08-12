import AppKit
import Carbon
import CoreGraphics
import Foundation

/// What is happening on screen around a detection.
///
/// Two situations make blind locking a bad idea: secure input, where the tap
/// receives nothing at all so PawGuard cannot protect anything, and full-screen
/// games, where holding several keys at once is the entire point.
struct DetectionContext: Equatable {
    var isSecureInputEnabled = false
    var frontmostBundleIdentifier: String?
    var frontmostApplicationName: String?
    var isFrontmostFullscreen = false

    /// True when PawGuard should stay out of the way entirely.
    func isProtectionSuppressed(disabledBundleIdentifiers: [String], pauseInFullscreen: Bool) -> Bool {
        if let identifier = frontmostBundleIdentifier, disabledBundleIdentifiers.contains(identifier) {
            return true
        }
        return pauseInFullscreen && isFrontmostFullscreen
    }
}

@MainActor
enum DetectionContextProbe {
    /// While secure input is on, no key events reach any tap. PawGuard is blind
    /// rather than watchful, and the UI has to say so.
    static var isSecureInputEnabled: Bool {
        IsSecureEventInputEnabled()
    }

    static func current() -> DetectionContext {
        var context = DetectionContext()
        context.isSecureInputEnabled = isSecureInputEnabled

        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return context }
        context.frontmostBundleIdentifier = frontmost.bundleIdentifier
        context.frontmostApplicationName = frontmost.localizedName
        context.isFrontmostFullscreen = isFullscreen(processIdentifier: frontmost.processIdentifier)
        return context
    }

    /// A window from the frontmost app that covers a whole screen, including
    /// the menu bar area, is a full-screen game or presentation.
    private static func isFullscreen(processIdentifier: pid_t) -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        let screenFrames = NSScreen.screens.map(\.frame)
        for window in windows {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t, ownerPID == processIdentifier,
                let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                let boundsDictionary = window[kCGWindowBounds as String] as? [String: Any],
                let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary)
            else { continue }

            for frame in screenFrames where bounds.width >= frame.width && bounds.height >= frame.height {
                return true
            }
        }
        return false
    }
}
