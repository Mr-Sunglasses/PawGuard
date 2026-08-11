import SwiftUI

@main
struct PawGuardApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Label("PawGuard", systemImage: appState.isLocked ? "lock.fill" : "pawprint.fill")
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
