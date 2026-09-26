import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow

    private var accent: Color {
        PawGuardStyle.accent(for: appState.settingsStore.settings.accentTheme)
    }

    private var statusColor: Color {
        if appState.isLocked { return accent }
        if !appState.keyboardMonitoringAvailable || appState.isManuallyPaused { return .orange }
        return .green
    }

    private var repairMessage: String {
        switch appState.accessibilityStage {
        case .needsRelaunch:
            return "Permission is granted, but this launch cannot watch the keyboard. Relaunch to fix it."
        case .ready:
            return "Keyboard monitoring is unavailable."
        case .awaitingGrant:
            return appState.accessibilityEnabled
                ? "Starting keyboard monitoring…"
                : "Waiting for Accessibility permission."
        case .unstableSignature:
            return "This ad-hoc build cannot keep Accessibility permission across rebuilds. Run a signed build."
        case .notGranted:
            return "Accessibility permission is required."
        }
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
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(appState.statusTitle)
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            Text(appState.statusSubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 16)

            // The overlay can be switched off, and the emergency shortcut is
            // easy to forget, so the menu always offers a way out of a lock.
            if appState.isLocked {
                HStack(spacing: 8) {
                    Button("Unlock Keyboard") { appState.unlockNow() }
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                    Button("It Was Me") { appState.reportFalseAlarm() }
                        .buttonStyle(.bordered)
                        .help("Unlocks the keyboard and teaches PawGuard that this was not your cat.")
                }
                .controlSize(.small)
                .padding(.top, 12)
                .padding(.leading, 16)
            }

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
                Label(repairMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
                // A stale grant cannot be repaired from inside this process, so
                // offering "Repair" for it would just fail quietly.
                Button(appState.accessibilityStage == .needsRelaunch ? "Relaunch PawGuard" : "Repair Accessibility") {
                    if appState.accessibilityStage == .needsRelaunch {
                        appState.relaunchForAccessibility()
                    } else {
                        appState.requestAccessibility()
                    }
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

            if appState.isManuallyPaused {
                Button {
                    appState.resumeProtection()
                } label: {
                    Label("Resume Protection", systemImage: "play.circle")
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
            } else {
                Menu {
                    Button("For 15 Minutes") { appState.pauseProtection(for: 15 * 60) }
                    Button("For 1 Hour") { appState.pauseProtection(for: 60 * 60) }
                    Button("Until I Resume") { appState.pauseProtection(for: nil) }
                } label: {
                    Label("Pause Protection", systemImage: "pause.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .padding(.top, 12)
            }

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
