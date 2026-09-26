import AppKit
import SwiftUI

@main
struct PawGuardApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            // The label is the one view that exists from launch: the popover's
            // content is not built until the user clicks the icon. Setup used to
            // be opened from there, so a first-time user saw nothing at all
            // until they thought to open a menu they had no reason to open.
            MenuBarLabel(
                isLocked: appState.isLocked,
                isPaused: appState.isManuallyPaused,
                shouldOfferSetup: appState.shouldOfferSetupOnLaunch
            )
        }
        .menuBarExtraStyle(.window)

        Window("PawGuard Setup", id: "setup") {
            OnboardingView()
                .environmentObject(appState)
        }
        .defaultSize(width: 560, height: 610)
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

/// The menu bar icon, plus the one place PawGuard can act at launch.
///
/// PawGuard is an agent app with no Dock icon and no main window, so without
/// this a first run is completely silent.
private struct MenuBarLabel: View {
    let isLocked: Bool
    let isPaused: Bool
    /// Returns true exactly once, the first time setup is due.
    let shouldOfferSetup: () -> Bool

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Label("PawGuard", systemImage: isLocked ? "lock.fill" : (isPaused ? "pause.circle" : "pawprint.fill"))
            .task {
                guard shouldOfferSetup() else { return }
                openWindow(id: "setup")
                NSApp.activate(ignoringOtherApps: true)
            }
    }
}
