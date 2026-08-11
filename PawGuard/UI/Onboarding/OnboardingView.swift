import Combine
import SwiftUI
import UniformTypeIdentifiers

private enum OnboardingStep: Int, CaseIterable {
    case welcome
    case name
    case photos
    case avatar
    case permission
    case sensitivity
    case ready
}

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var step: OnboardingStep = .welcome
    @State private var name = ""
    @State private var draftProfileID: UUID?
    @State private var selectedAvatarIndex = 0
    @State private var showingImporter = false
    @State private var isDropTargeted = false

    private var profile: CatProfile? {
        guard let draftProfileID else { return appState.activeCat }
        return appState.profileStore.profiles.first { $0.id == draftProfileID }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("PawGuard", systemImage: "pawprint.fill")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
                if step != .welcome && step != .ready {
                    Text("Step \(step.rawValue) of 5")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)

            ProgressView(value: Double(step.rawValue), total: Double(OnboardingStep.ready.rawValue))
                .tint(PawGuardStyle.accent(for: appState.settingsStore.settings.accentTheme))
                .padding(.horizontal, 28)
                .padding(.top, 15)

            Group {
                switch step {
                case .welcome:
                    WelcomeView { step = .name }
                case .name:
                    CatNameView(name: $name) {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        if let draftProfileID,
                            appState.profileStore.profiles.contains(where: { $0.id == draftProfileID })
                        {
                            appState.updateCatName(trimmed, profileID: draftProfileID)
                        } else {
                            let created = appState.createCatProfile(named: trimmed)
                            draftProfileID = created.id
                        }
                        step = .photos
                    }
                case .photos:
                    CatPhotoImportView(
                        catName: profile?.displayName ?? name,
                        photoCount: profile?.photoPaths.count ?? 0,
                        isDropTargeted: $isDropTargeted,
                        choosePhotos: { showingImporter = true },
                        continueAction: { step = (profile?.photoPaths.isEmpty == false) ? .avatar : .permission },
                        skipAction: { step = .permission }
                    )
                    .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
                        importDroppedPhotos(providers)
                    }
                case .avatar:
                    AvatarPickerView(
                        profile: profile,
                        selectedIndex: $selectedAvatarIndex,
                        continueAction: {
                            appState.selectAvatar(at: selectedAvatarIndex)
                            step = .permission
                        },
                        skipAction: { step = .permission }
                    )
                case .permission:
                    PermissionView(
                        isEnabled: appState.accessibilityEnabled,
                        monitoringAvailable: appState.keyboardMonitoringAvailable,
                        enableAction: appState.requestAccessibility,
                        refreshAction: appState.refreshAccessibility,
                        continueAction: { step = .sensitivity }
                    )
                case .sensitivity:
                    SensitivitySetupView(
                        settings: appState.settingsStore,
                        continueAction: { step = .ready }
                    )
                case .ready:
                    ReadyView(
                        catName: profile?.displayName ?? appState.activeCat?.displayName ?? "your cat",
                        finishAction: finish
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 560, height: 610)
        .background(Color(nsColor: .windowBackgroundColor))
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.jpeg, .png, .heic],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                appState.importPhotos(urls, for: draftProfileID)
            }
        }
        .onAppear {
            if let activeCat = appState.activeCat, name.isEmpty {
                name = activeCat.name
                draftProfileID = activeCat.id
            }
        }
    }

    private func finish() {
        appState.completeOnboarding()
        dismiss()
    }

    private func importDroppedPhotos(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in
                    appState.importPhotos([url], for: draftProfileID)
                }
            }
        }
        return true
    }
}

private struct OnboardingCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 22) { content }
            .frame(maxWidth: 460)
            .padding(34)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }
}

struct WelcomeView: View {
    let continueAction: () -> Void

    var body: some View {
        OnboardingCard {
            Image(systemName: "pawprint.circle.fill")
                .font(.system(size: 70, weight: .regular))
                .foregroundStyle(PawGuardStyle.accent(for: .automatic))
            VStack(spacing: 8) {
                Text("Meet your keyboard guardian")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("PawGuard notices the telltale rhythm of tiny paws and gives your keyboard a quiet break.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 10) {
                PrivacyRow(icon: "keyboard", text: "Only keyboard timing and physical key metadata are used")
                PrivacyRow(icon: "lock.shield", text: "Your typing is never recorded or stored")
                PrivacyRow(icon: "photo", text: "Cat photos stay on this Mac")
            }
            Button("Get Started", action: continueAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(PawGuardStyle.accent(for: .automatic))
        }
    }
}

private struct PrivacyRow: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}

struct CatNameView: View {
    @Binding var name: String
    let continueAction: () -> Void

    var body: some View {
        OnboardingCard {
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 54))
                .foregroundStyle(PawGuardStyle.accent(for: .automatic))
            VStack(spacing: 8) {
                Text("What's your cat's name?")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("PawGuard will use it for a few friendly messages while it protects your keyboard.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            TextField("Cat name", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .onSubmit(continueAction)
            Button("Continue", action: continueAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(PawGuardStyle.accent(for: .automatic))
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

struct CatPhotoImportView: View {
    let catName: String
    let photoCount: Int
    @Binding var isDropTargeted: Bool
    let choosePhotos: () -> Void
    let continueAction: () -> Void
    let skipAction: () -> Void

    var body: some View {
        OnboardingCard {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundStyle(PawGuardStyle.accent(for: .automatic))
            VStack(spacing: 8) {
                Text("Add some photos of \(catName)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("Photos personalize PawGuard and stay only on this Mac. One photo is enough, and you can add more later.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: 10) {
                Image(systemName: "arrow.down.doc")
                    .font(.title2)
                    .foregroundStyle(isDropTargeted ? PawGuardStyle.accent(for: .automatic) : .secondary)
                Text(isDropTargeted ? "Drop photos here" : "Drag photos here")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(Color.primary.opacity(isDropTargeted ? 0.09 : 0.04), in: RoundedRectangle(cornerRadius: 14))
            Button("Choose Photos…", action: choosePhotos)
                .buttonStyle(.borderedProminent)
                .tint(PawGuardStyle.accent(for: .automatic))
            if photoCount > 0 {
                Text("\(photoCount) photo\(photoCount == 1 ? "" : "s") added")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Continue", action: continueAction)
                    .buttonStyle(.bordered)
            } else {
                Button("Skip for now", action: skipAction)
                    .buttonStyle(.link)
            }
        }
    }
}

struct AvatarPickerView: View {
    let profile: CatProfile?
    @Binding var selectedIndex: Int
    let continueAction: () -> Void
    let skipAction: () -> Void

    var body: some View {
        OnboardingCard {
            Text("Choose \(profile?.displayName ?? "your cat")'s profile photo")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
            Text("This is the photo PawGuard will show when tiny paws take over.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(Array((profile?.photoPaths ?? []).enumerated()), id: \.offset) { index, path in
                        Button {
                            selectedIndex = index
                        } label: {
                            CatAvatarView(path: path, size: 100, cornerRadius: 22, accent: PawGuardStyle.accent(for: .automatic))
                                .overlay {
                                    if selectedIndex == index {
                                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                                            .strokeBorder(PawGuardStyle.accent(for: .automatic), lineWidth: 4)
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.title2)
                                            .foregroundStyle(PawGuardStyle.accent(for: .automatic))
                                            .background(Circle().fill(.regularMaterial))
                                            .offset(x: 42, y: -42)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 12)
            }
            HStack {
                Button("Use generic avatar", action: skipAction)
                    .buttonStyle(.link)
                Spacer()
                Button("Continue", action: continueAction)
                    .buttonStyle(.borderedProminent)
                    .tint(PawGuardStyle.accent(for: .automatic))
            }
        }
        .onAppear { selectedIndex = min(selectedIndex, max(0, (profile?.photoPaths.count ?? 1) - 1)) }
    }
}

struct PermissionView: View {
    let isEnabled: Bool
    let monitoringAvailable: Bool
    let enableAction: () -> Void
    let refreshAction: () -> Void
    let continueAction: () -> Void

    var body: some View {
        OnboardingCard {
            Image(systemName: isEnabled ? "checkmark.shield.fill" : "lock.shield")
                .font(.system(size: 54))
                .foregroundStyle(isEnabled ? .green : PawGuardStyle.accent(for: .automatic))
            VStack(spacing: 8) {
                Text("Allow keyboard protection")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(
                    "PawGuard needs Accessibility permission so it can detect and temporarily block accidental keyboard input. Your typing is never recorded."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
            if isEnabled {
                Label("Accessibility Enabled", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                if !monitoringAvailable {
                    Text(
                        "macOS has granted permission, but PawGuard cannot start its keyboard monitor yet. Run the signed build and relaunch if this does not clear."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                }
                Button("Continue", action: continueAction)
                    .buttonStyle(.borderedProminent)
                    .tint(PawGuardStyle.accent(for: .automatic))
            } else {
                Button("Enable Accessibility", action: enableAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(PawGuardStyle.accent(for: .automatic))
                Button("I'll do this later", action: continueAction)
                    .buttonStyle(.link)
            }
        }
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            refreshAction()
        }
    }
}

struct SensitivitySetupView: View {
    @ObservedObject var settings: SettingsStore
    let continueAction: () -> Void

    var body: some View {
        OnboardingCard {
            Image(systemName: "dial.medium")
                .font(.system(size: 52))
                .foregroundStyle(PawGuardStyle.accent(for: .automatic))
            VStack(spacing: 8) {
                Text("Choose your sensitivity")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("Balanced is a good starting point for most keyboards. You can change this later in Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Picker("Sensitivity", selection: $settings.settings.sensitivity) {
                ForEach(SensitivityPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            Button("Continue", action: continueAction)
                .buttonStyle(.borderedProminent)
                .tint(PawGuardStyle.accent(for: .automatic))
        }
    }
}

private struct ReadyView: View {
    let catName: String
    let finishAction: () -> Void

    var body: some View {
        OnboardingCard {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 66))
                .foregroundStyle(.green)
            VStack(spacing: 8) {
                Text("PawGuard is ready")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("We'll keep an eye out for \(catName)'s tiny paws. Mouse and trackpad input always stay available.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Start PawGuard", action: finishAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(PawGuardStyle.accent(for: .automatic))
        }
    }
}
