import SwiftUI

struct AppearanceSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section("Accent") {
                Picker("Theme", selection: $settings.settings.accentTheme) {
                    ForEach(AccentTheme.allCases) { theme in
                        HStack {
                            Circle().fill(PawGuardStyle.accent(for: theme)).frame(width: 10, height: 10)
                            Text(theme.title)
                        }
                        .tag(theme)
                    }
                }
                .pickerStyle(.menu)
            }
            Section("Overlay") {
                Toggle("Show cat photo", isOn: $settings.settings.showCatPhoto)
                Picker("Animation intensity", selection: $settings.settings.animationIntensity) {
                    Text("Subtle").tag(0.45)
                    Text("Standard").tag(0.8)
                    Text("Playful").tag(1.0)
                }
            }
            Section {
                Label("PawGuard follows the macOS Reduce Motion setting automatically.", systemImage: "accessibility")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
