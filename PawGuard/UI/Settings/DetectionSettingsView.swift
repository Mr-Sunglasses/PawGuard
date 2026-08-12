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
                if settings.settings.sensitivity == .custom {
                    HStack {
                        Text("Threshold")
                        Slider(
                            value: Binding(
                                get: { Double(settings.settings.customThreshold) },
                                set: { settings.settings.customThreshold = Int($0.rounded()) }
                            ), in: 30...100, step: 1)
                        Text("\(settings.settings.customThreshold)")
                            .monospacedDigit()
                            .frame(width: 32, alignment: .trailing)
                    }
                }
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("Active threshold", value: activeThresholdDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Behaviour") {
                Toggle("Confirm before locking", isOn: $settings.settings.useGraceWindow)
                Text(
                    "Borderline activity is held back for a moment instead of locking straight away. If it turns out to be you, those keystrokes are delivered as though nothing happened."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Toggle("Offer to undo what the cat typed", isOn: $settings.settings.offerUndo)
                Text("The alert can remove the characters that landed before PawGuard stepped in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Learning") {
                Toggle("Adapt to how you type", isOn: $settings.settings.adaptiveCalibration)
                Text(
                    "Unlocking within a few seconds tells PawGuard it was wrong; letting a lock finish tells it it was right. Nothing leaves this Mac."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if settings.settings.adaptiveCalibration {
                    LabeledContent("Threshold adjustment", value: offsetDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LabeledContent(
                        "Chords you have excused",
                        value: "\(appState.calibrationStore.profile.allowedKeySets.count)"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Button("Reset What PawGuard Has Learned") {
                        appState.calibrationStore.resetLearning()
                    }
                    .controlSize(.small)
                }
            }

            Section("When to stand down") {
                Toggle("Pause while a full-screen app is frontmost", isOn: $settings.settings.pauseInFullscreen)
                Text("Holding several keys at once is normal in games, so PawGuard stays out of the way.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let identifier = appState.detectionContext.frontmostBundleIdentifier,
                    identifier != Bundle.main.bundleIdentifier
                {
                    let name = appState.detectionContext.frontmostApplicationName ?? identifier
                    if settings.settings.disabledBundleIdentifiers.contains(identifier) {
                        Button("Protect \(name) Again") {
                            appState.enableProtection(forBundleIdentifier: identifier)
                        }
                        .controlSize(.small)
                    } else {
                        Button("Never Protect \(name)") {
                            appState.disableProtection(forBundleIdentifier: identifier)
                        }
                        .controlSize(.small)
                    }
                }

                if !settings.settings.disabledBundleIdentifiers.isEmpty {
                    ForEach(settings.settings.disabledBundleIdentifiers, id: \.self) { identifier in
                        HStack {
                            Text(identifier)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Remove") {
                                appState.enableProtection(forBundleIdentifier: identifier)
                            }
                            .controlSize(.mini)
                        }
                    }
                }
            }

            if appState.isSecureInputActive {
                Section("Secure input") {
                    Label(
                        "A password field currently has secure input turned on. No app can observe the keyboard while that is true, so PawGuard cannot protect it.",
                        systemImage: "exclamationmark.lock"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
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
                    let detection = appState.currentDetection
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Score         \(detection.score) / \(activeThresholdDescription)")
                        Text("Held keys     \(detection.heldKeyCount)")
                        Text("Burst count   \(detection.burstKeyCount)")
                        Text("Rapid cluster \(detection.rapidClusterKeyCount)")
                        Text("Synchrony     \(detection.features.synchronyCount)")
                        Text("Clusters      \(detection.features.separateClusterCount)")
                        Text(
                            "Compactness   "
                                + String(format: "%.2f", detection.features.clusterCompactness)
                        )
                        Text("Key rate      " + String(format: "%.1f/s", detection.features.keyRate))
                        Text("Signals       \(detection.signals.map(\.rawValue).sorted().joined(separator: ", "))")
                    }
                    .font(.caption.monospaced())
                }
            #endif
        }
        .formStyle(.grouped)
    }

    private var activeThresholdDescription: String {
        let base = settings.settings.detectionThreshold
        let effective = appState.calibrationStore.effectiveThreshold(
            base: base,
            adaptive: settings.settings.adaptiveCalibration
        )
        return effective == base ? "\(base)" : "\(effective) (you set \(base))"
    }

    private var offsetDescription: String {
        let offset = appState.calibrationStore.profile.thresholdOffset
        if offset == 0 { return "None yet" }
        return offset > 0 ? "+\(offset) (harder to trigger)" : "\(offset) (easier to trigger)"
    }

    private var description: String {
        switch settings.settings.sensitivity {
        case .relaxed: "Higher threshold; best if you type quickly or use keyboard shortcuts often."
        case .balanced: "A balanced threshold for everyday typing and occasional cat activity."
        case .sensitive: "Lower threshold; useful for a particularly enthusiastic keyboard companion."
        case .custom: "Choose a threshold between 30 and 100."
        }
    }
}
