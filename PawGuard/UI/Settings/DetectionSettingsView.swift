import SwiftUI

struct DetectionSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section("Sensitivity") {
                Picker("Preset", selection: $settings.settings.sensitivity) {
                    ForEach(SensitivityPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                if appState.settingsStore.settings.sensitivity == .custom {
                    HStack {
                        Text("Threshold")
                        Slider(
                            value: Binding(
                                get: { Double(appState.settingsStore.settings.customThreshold) },
                                set: { appState.settingsStore.settings.customThreshold = Int($0.rounded()) }
                            ), in: 30...100, step: 1)
                        Text("\(appState.settingsStore.settings.customThreshold)")
                            .monospacedDigit()
                            .frame(width: 32, alignment: .trailing)
                    }
                }
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("Active threshold", value: "\(appState.settingsStore.settings.detectionThreshold)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Protection preview") {
                Button {
                    appState.testCatMode()
                } label: {
                    Label("Preview Protection Overlay", systemImage: "sparkles")
                }
                .disabled(appState.isLocked || appState.isTestOverlayVisible)
                Text("The preview shows the complete alert without blocking any keyboard input.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Privacy") {
                Label(
                    "Detection looks at timing, physical key positions, and overlapping presses. It never converts key codes into text.",
                    systemImage: "eye.slash"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            #if DEBUG
                Section("Developer") {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Current score  \(appState.currentDetection.score)")
                        Text("Held keys     \(appState.currentDetection.heldKeyCount)")
                        Text("Burst count   \(appState.currentDetection.burstKeyCount)")
                        Text("Rapid cluster \(appState.currentDetection.rapidClusterKeyCount)")
                        Text("Cluster       \(appState.currentDetection.hasPhysicalCluster ? "yes" : "no")")
                        Text("Threshold     \(appState.settingsStore.settings.detectionThreshold)")
                    }
                    .font(.caption.monospaced())
                }
            #endif
        }
        .formStyle(.grouped)
    }

    private var description: String {
        switch appState.settingsStore.settings.sensitivity {
        case .relaxed: "Higher threshold; best if you type quickly or use keyboard shortcuts often."
        case .balanced: "A balanced threshold for everyday typing and occasional cat activity."
        case .sensitive: "Lower threshold; useful for a particularly enthusiastic keyboard companion."
        case .custom: "Choose a threshold between 30 and 100."
        }
    }
}
