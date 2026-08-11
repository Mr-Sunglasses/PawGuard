import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow

    private var accent: Color {
        PawGuardStyle.accent(for: appState.settingsStore.settings.accentTheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                CatAvatarView(path: appState.activeCat?.selectedPhotoPath, size: 44, cornerRadius: 14, accent: accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("PawGuard")
                        .font(.headline)
                    Text(appState.activeCat?.displayName ?? "Tiny paws welcome")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.bottom, 18)

            HStack(spacing: 8) {
                Circle()
                    .fill(appState.isLocked ? accent : (appState.keyboardMonitoringAvailable ? .green : .orange))
                    .frame(width: 8, height: 8)
                Text(appState.statusTitle)
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            Text(appState.statusSubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 16)

            Divider().padding(.vertical, 16)

            HStack(spacing: 12) {
                StatTile(
                    title: "Interventions", value: "\(appState.statisticsStore.stats.detectionCount)", icon: "pawprint.fill", accent: accent
                )
                StatTile(
                    title: "Keys blocked", value: "\(appState.statisticsStore.stats.blockedEventCount)", icon: "keyboard.fill",
                    accent: accent)
            }

            if appState.accessibilityRepairNeeded {
                Label(
                    appState.accessibilityEnabled
                        ? "Keyboard monitoring is unavailable for this build."
                        : "Accessibility permission is required.", systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.top, 14)
                Button("Repair Accessibility") {
                    appState.requestAccessibility()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 8)
            }

            Divider().padding(.vertical, 16)

            Button {
                appState.testCatMode()
            } label: {
                Label("Test Cat Mode", systemImage: "sparkles")
            }
            .buttonStyle(.plain)
            .disabled(appState.isLocked)

            Button {
                openWindow(id: "setup")
            } label: {
                Label(appState.needsOnboarding ? "Finish Setup" : "Cat Profile", systemImage: "person.crop.circle")
            }
            .buttonStyle(.plain)
            .padding(.top, 12)

            SettingsLink {
                Label("Settings…", systemImage: "gearshape")
            }
            .buttonStyle(.plain)
            .padding(.top, 12)

            Divider().padding(.vertical, 16)

            Button("Quit PawGuard") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 320)
        .onAppear {
            if appState.needsOnboarding { openWindow(id: "setup") }
        }
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let icon: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon)
                .foregroundStyle(accent)
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
