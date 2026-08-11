import AppKit
import SwiftUI

private final class PawOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class CatOverlayController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<CatDetectedView>?
    private var profile: CatProfile?
    private var remaining: TimeInterval = 0
    private var total: TimeInterval = 20
    private var accent: AccentTheme = .automatic
    private var isTest = false
    private var message = "Tiny paws detected."
    private var unlockAction: (() -> Void)?

    func show(
        profile: CatProfile?,
        remaining: TimeInterval,
        accent: AccentTheme,
        total: TimeInterval,
        isTest: Bool,
        onUnlock: @escaping () -> Void
    ) {
        self.profile = profile
        self.remaining = remaining
        self.total = total
        self.accent = accent
        self.isTest = isTest
        self.unlockAction = onUnlock
        if !isTest && message == "Tiny paws detected." {
            message = CatMessage.detected(catName: profile?.displayName ?? "your cat")
        } else if isTest {
            message = "Meet your keyboard guardian"
        }
        if panel == nil { createPanel() }
        updateRootView()
        positionPanel()
        panel?.orderFrontRegardless()
    }

    func update(remaining: TimeInterval) {
        self.remaining = remaining
        guard panel != nil else { return }
        updateRootView()
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
        message = "Tiny paws detected."
        unlockAction = nil
    }

    private func createPanel() {
        let panel = PawOverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 224),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hasShadow = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        self.panel = panel
    }

    private func updateRootView() {
        guard let panel else { return }
        let view = CatDetectedView(
            profile: profile,
            message: message,
            remaining: remaining,
            total: total,
            accentTheme: accent,
            isTest: isTest,
            onUnlock: { [weak self] in self?.unlockAction?() }
        )
        if let hostingView {
            hostingView.rootView = view
        } else {
            let hostingView = NSHostingView(rootView: view)
            hostingView.frame = panel.contentView?.bounds ?? .zero
            hostingView.autoresizingMask = [.width, .height]
            panel.contentView = hostingView
            self.hostingView = hostingView
        }
    }

    private func positionPanel() {
        guard let panel else { return }
        let mouseLocation = NSEvent.mouseLocation
        let screen =
            NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else { return }
        let frame = panel.frame
        let origin = NSPoint(
            x: visibleFrame.midX - frame.width / 2,
            y: visibleFrame.maxY - frame.height - 64
        )
        panel.setFrameOrigin(origin)
    }
}
