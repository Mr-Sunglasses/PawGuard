import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsView(settings: appState.settingsStore)
                .tabItem { Label("General", systemImage: "slider.horizontal.3") }
            CatProfileSettingsView()
                .tabItem { Label("Cat Profile", systemImage: "cat.fill") }
            DetectionSettingsView(settings: appState.settingsStore)
                .tabItem { Label("Detection", systemImage: "waveform.path.ecg") }
            AppearanceSettingsView(settings: appState.settingsStore)
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            StatisticsView()
                .tabItem { Label("Statistics", systemImage: "chart.bar") }
        }
        .padding(20)
        .frame(width: 600, height: 430)
        .environmentObject(appState)
    }
}

private struct GeneralSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section("Protection") {
                Toggle("Show protection overlay", isOn: $settings.settings.showProtectionOverlay)
                Toggle("Play protection sound", isOn: $settings.settings.playProtectionSound)
                Toggle("Extend lock when activity continues", isOn: $settings.settings.extendOnActivity)
                Picker("Lock duration", selection: $settings.settings.lockDuration) {
                    ForEach(PawGuardSettings.lockDurations, id: \.self) { duration in
                        Text("\(Int(duration)) seconds").tag(duration)
                    }
                }
            }
            Section("Startup") {
                Toggle(
                    "Start PawGuard at login",
                    isOn: Binding(
                        get: { settings.settings.launchAtLogin },
                        set: { appState.setLaunchAtLogin($0) }
                    ))
            }
            Section("Accessibility") {
                Label(accessibilityStatusTitle, systemImage: accessibilityStatusIcon)
                    .foregroundStyle(accessibilityStatusColor)
                Text(
                    "PawGuard needs Accessibility permission to monitor and temporarily pause keyboard input. Resetting only affects PawGuard."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Button(appState.accessibilityRepairNeeded ? "Repair Accessibility" : "Open Accessibility Settings") {
                    appState.requestAccessibility()
                }
                Button("Reset Accessibility Permission") {
                    appState.resetAccessibilityPermission()
                }
                .disabled(appState.isResettingAccessibility)
                if appState.isResettingAccessibility {
                    ProgressView("Resetting permission…")
                        .controlSize(.small)
                }
                if let message = appState.accessibilityResetMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Label(
                    "PawGuard uses only ephemeral keyboard metadata. It never reads or stores typed characters.", systemImage: "lock.shield"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Section("Emergency unlock") {
                LabeledContent("Shortcut", value: "⌃⌥⌘ Esc")
                Text(
                    "This shortcut immediately restores keyboard input if protection activates at the wrong time. Mouse and trackpad input always remain available."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var accessibilityStatusTitle: String {
        if !appState.accessibilityEnabled { return "Accessibility permission required" }
        if !appState.keyboardMonitoringAvailable { return "Permission granted, monitor unavailable" }
        return "Keyboard protection is ready"
    }

    private var accessibilityStatusIcon: String {
        appState.keyboardMonitoringAvailable ? "checkmark.shield.fill" : "exclamationmark.triangle.fill"
    }

    private var accessibilityStatusColor: Color {
        appState.keyboardMonitoringAvailable ? .green : .orange
    }
}
