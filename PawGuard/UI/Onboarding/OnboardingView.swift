import Combine
import SwiftUI
import UniformTypeIdentifiers

/// The setup flow, in order.
///
/// `welcome` and `ready` are bookends and are not numbered; everything between
/// them is a step the user is counted through. `avatar` only appears when there
/// are photos to choose from, so the count is computed from the steps this run
/// will actually show rather than from the case order — otherwise skipping
/// photos made the counter jump from "Step 2 of 5" to "Step 4 of 5".
private enum OnboardingStep: Int, CaseIterable, Comparable {
    case welcome
    case name
    case photos
    case avatar
    case permission
    case sensitivity
    case ready

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var isNumbered: Bool { self != .welcome && self != .ready }
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

    private var hasPhotos: Bool { profile?.photoPaths.isEmpty == false }

    /// The numbered steps this run will show. The avatar picker is only one of
    /// them once there is something to pick from.
    private var numberedSteps: [OnboardingStep] {
        OnboardingStep.allCases.filter { $0.isNumbered && ($0 != .avatar || hasPhotos) }
    }

    private var stepPosition: Int? {
        numberedSteps.firstIndex(of: step).map { $0 + 1 }
    }

    private var accent: Color {
        PawGuardStyle.accent(for: appState.settingsStore.settings.accentTheme)
    }

    /// How far along the bar sits, counting the welcome screen as empty and the
    /// final screen as full.
    private var progress: Double {
        switch step {
        case .welcome: return 0
        case .ready: return 1
        default:
            guard let position = stepPosition, !numberedSteps.isEmpty else { return 0 }
            return Double(position) / Double(numberedSteps.count + 1)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ProgressView(value: progress)
                .tint(accent)
                .padding(.horizontal, 28)
                .padding(.top, 14)

            Group {
                switch step {
                case .welcome:
                    WelcomeView(accent: accent) { advance(to: .name) }
                case .name:
                    CatNameView(name: $name, accent: accent, continueAction: commitName)
                case .photos:
                    CatPhotoImportView(
                        catName: profile?.displayName ?? name,
                        photoCount: profile?.photoPaths.count ?? 0,
                        accent: accent,
                        isDropTargeted: $isDropTargeted,
                        choosePhotos: { showingImporter = true },
                        continueAction: { advance(to: hasPhotos ? .avatar : .permission) },
                        skipAction: { advance(to: .permission) }
                    )
                    .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
                        importDroppedPhotos(providers)
                    }
                case .avatar:
                    AvatarPickerView(
                        profile: profile,
                        selectedIndex: $selectedAvatarIndex,
                        accent: accent,
                        continueAction: {
                            appState.selectAvatar(at: selectedAvatarIndex)
                            advance(to: .permission)
                        },
                        skipAction: { advance(to: .permission) }
                    )
                case .permission:
                    PermissionView(
                        stage: appState.accessibilityStage,
                        accent: accent,
                        enableAction: appState.requestAccessibility,
                        openSettingsAction: appState.openAccessibilitySettings,
                        relaunchAction: appState.relaunchForAccessibility,
                        refreshAction: appState.refreshAccessibility,
                        continueAction: { advance(to: .sensitivity) }
                    )
                case .sensitivity:
                    SensitivitySetupView(
                        settings: appState.settingsStore,
                        accent: accent,
                        continueAction: { advance(to: .ready) }
                    )
                case .ready:
                    ReadyView(
                        catName: profile?.displayName ?? appState.activeCat?.displayName ?? "your cat",
                        monitoringReady: appState.accessibilityStage == .ready,
                        accent: accent,
                        finishAction: finish
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
        }
        .frame(width: 580, height: 640)
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

    private var header: some View {
        HStack(spacing: 10) {
            if let previous = previousStep {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { step = previous }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Go back")
            }
            Label("PawGuard", systemImage: "pawprint.fill")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Spacer()
            if let position = stepPosition {
                Text("Step \(position) of \(numberedSteps.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
    }

    /// The step the back button returns to, skipping any the flow did not show.
    private var previousStep: OnboardingStep? {
        let shown = OnboardingStep.allCases.filter { $0 != .avatar || hasPhotos }
        guard let index = shown.firstIndex(of: step), index > 0 else { return nil }
        return shown[index - 1]
    }

    private func advance(to next: OnboardingStep) {
        withAnimation(.easeInOut(duration: 0.18)) { step = next }
    }

    private func commitName() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let draftProfileID, appState.profileStore.profiles.contains(where: { $0.id == draftProfileID }) {
            appState.updateCatName(trimmed, profileID: draftProfileID)
        } else {
            draftProfileID = appState.createCatProfile(named: trimmed).id
        }
        advance(to: .photos)
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

// MARK: - Shared chrome

private struct OnboardingCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 20) { content }
            .frame(maxWidth: 470)
            .padding(32)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }
}

private struct StepHeading: View {
    let icon: String
    let title: String
    let subtitle: String
    let accent: Color
    var iconColor: Color?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 50))
                .foregroundStyle(iconColor ?? accent)
                .symbolRenderingMode(.hierarchical)
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct PrimaryButton: View {
    let title: String
    let accent: Color
    let action: () -> Void
    var isDisabled = false

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(accent)
            .disabled(isDisabled)
    }
}

// MARK: - Welcome

private struct WelcomeView: View {
    let accent: Color
    let continueAction: () -> Void

    var body: some View {
        OnboardingCard {
            StepHeading(
                icon: "pawprint.circle.fill",
                title: "Meet your keyboard guardian",
                subtitle: "PawGuard notices the telltale rhythm of tiny paws and gives your keyboard a quiet break.",
                accent: accent
            )
            VStack(alignment: .leading, spacing: 12) {
                PrivacyRow(
                    icon: "keyboard",
                    title: "Timing, not text",
                    detail: "Only key positions and timing are examined — never characters or words."
                )
                PrivacyRow(
                    icon: "lock.shield",
                    title: "Nothing is recorded",
                    detail: "Your typing is never stored, logged, or sent anywhere."
                )
                PrivacyRow(
                    icon: "photo",
                    title: "Photos stay put",
                    detail: "Cat photos live on this Mac and nowhere else."
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            PrimaryButton(title: "Get Started", accent: accent, action: continueAction)
        }
    }
}

private struct PrivacyRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Cat name

private struct CatNameView: View {
    @Binding var name: String
    let accent: Color
    let continueAction: () -> Void

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        OnboardingCard {
            StepHeading(
                icon: "heart.circle.fill",
                title: "What's your cat's name?",
                subtitle: "PawGuard will use it for a few friendly messages while it protects your keyboard.",
                accent: accent
            )
            TextField("Cat name", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .onSubmit(continueAction)
            PrimaryButton(title: "Continue", accent: accent, action: continueAction, isDisabled: trimmed.isEmpty)
        }
    }
}

// MARK: - Photos

private struct CatPhotoImportView: View {
    let catName: String
    let photoCount: Int
    let accent: Color
    @Binding var isDropTargeted: Bool
    let choosePhotos: () -> Void
    let continueAction: () -> Void
    let skipAction: () -> Void

    var body: some View {
        OnboardingCard {
            StepHeading(
                icon: "photo.on.rectangle.angled",
                title: "Add some photos of \(catName)",
                subtitle: "Photos personalise the alert PawGuard shows. They stay on this Mac, and you can add more later.",
                accent: accent
            )
            VStack(spacing: 10) {
                Image(systemName: isDropTargeted ? "arrow.down.doc.fill" : "arrow.down.doc")
                    .font(.title2)
                    .foregroundStyle(isDropTargeted ? accent : .secondary)
                Text(isDropTargeted ? "Drop to add" : "Drag photos here")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("Up to 5 · JPEG, PNG or HEIC")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.primary.opacity(isDropTargeted ? 0.09 : 0.04))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        isDropTargeted ? accent : Color.primary.opacity(0.12),
                        style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [5, 4])
                    )
            }
            .animation(.easeInOut(duration: 0.12), value: isDropTargeted)

            Button("Choose Photos…", action: choosePhotos)
                .buttonStyle(.bordered)
                .controlSize(.large)

            if photoCount > 0 {
                Label(
                    "\(photoCount) photo\(photoCount == 1 ? "" : "s") added",
                    systemImage: "checkmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(.green)
                PrimaryButton(title: "Continue", accent: accent, action: continueAction)
            } else {
                Button("Skip for now", action: skipAction)
                    .buttonStyle(.link)
            }
        }
    }
}

// MARK: - Avatar

private struct AvatarPickerView: View {
    let profile: CatProfile?
    @Binding var selectedIndex: Int
    let accent: Color
    let continueAction: () -> Void
    let skipAction: () -> Void

    private var photoPaths: [String] { profile?.photoPaths ?? [] }

    var body: some View {
        OnboardingCard {
            StepHeading(
                icon: "person.crop.square.badge.camera",
                title: "Pick \(profile?.displayName ?? "your cat")'s profile photo",
                subtitle: "This is the photo PawGuard shows when tiny paws take over.",
                accent: accent
            )
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(Array(photoPaths.enumerated()), id: \.offset) { index, path in
                        Button {
                            selectedIndex = index
                        } label: {
                            CatAvatarView(path: path, size: 100, cornerRadius: 22, accent: accent)
                                .overlay {
                                    if selectedIndex == index {
                                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                                            .strokeBorder(accent, lineWidth: 4)
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.title2)
                                            .foregroundStyle(accent)
                                            .background(Circle().fill(.regularMaterial))
                                            .offset(x: 42, y: -42)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .help("Use this photo")
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 4)
            }
            .scrollIndicators(.hidden)
            HStack {
                Button("Use generic avatar", action: skipAction)
                    .buttonStyle(.link)
                Spacer()
                PrimaryButton(title: "Continue", accent: accent, action: continueAction)
            }
        }
        .onAppear { selectedIndex = min(selectedIndex, max(0, photoPaths.count - 1)) }
    }
}

// MARK: - Permission

private struct PermissionView: View {
    let stage: AccessibilityStage
    let accent: Color
    let enableAction: () -> Void
    let openSettingsAction: () -> Void
    let relaunchAction: () -> Void
    let refreshAction: () -> Void
    let continueAction: () -> Void

    /// Created once and held, rather than rebuilt on every body evaluation —
    /// a publisher built inline is a new timer each time the view redraws.
    @State private var poll = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        OnboardingCard {
            switch stage {
            case .ready:
                readyContent
            case .needsRelaunch:
                relaunchContent
            case .unstableSignature:
                unstableSignatureContent
            case .notGranted, .awaitingGrant:
                grantContent
            }
        }
        .onReceive(poll) { _ in refreshAction() }
        .animation(.easeInOut(duration: 0.2), value: stage)
    }

    private var readyContent: some View {
        VStack(spacing: 20) {
            StepHeading(
                icon: "checkmark.shield.fill",
                title: "Keyboard protection is on",
                subtitle: "PawGuard can see keystrokes as they arrive and hold them back when a paw lands.",
                accent: accent,
                iconColor: .green
            )
            PrimaryButton(title: "Continue", accent: accent, action: continueAction)
        }
    }

    private var grantContent: some View {
        VStack(spacing: 20) {
            StepHeading(
                icon: "lock.shield",
                title: "Allow keyboard protection",
                subtitle:
                    "macOS requires your permission before any app can watch the keyboard. PawGuard needs it to hold back a cat's keystrokes — it never records what you type.",
                accent: accent
            )

            VStack(alignment: .leading, spacing: 11) {
                InstructionRow(number: 1, text: "Open **Privacy & Security → Accessibility**")
                InstructionRow(number: 2, text: "Find **PawGuard** in the list")
                InstructionRow(number: 3, text: "Turn the switch **on**")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))

            if stage == .awaitingGrant {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for permission…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Open System Settings again", action: openSettingsAction)
                    .buttonStyle(.bordered)
            } else {
                PrimaryButton(title: "Open System Settings", accent: accent, action: enableAction)
            }

            Button("I'll do this later", action: continueAction)
                .buttonStyle(.link)
        }
    }

    /// The developer-build case: the permission was granted, but to a binary
    /// the next build replaced. Nothing the user does in System Settings will
    /// make it stick, so say so instead of spinning.
    private var unstableSignatureContent: some View {
        VStack(spacing: 18) {
            StepHeading(
                icon: "hammer.circle.fill",
                title: "This build can't keep permission",
                subtitle:
                    "macOS ties an Accessibility grant to the exact copy of the app it was given to. This build is signed ad hoc, so every rebuild replaces that copy and the grant stops counting.",
                accent: accent,
                iconColor: .orange
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(
                    "The PawGuard row still showing in System Settings belongs to the previous build. Switching it off and on will not help — it has to be removed and added again."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Divider()
                Text("To make it stick, run a signed build:")
                    .font(.caption.weight(.medium))
                Text("make run")
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                Text(
                    "That signs PawGuard with your Apple Development certificate, which stays the same across rebuilds, so the permission survives."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 10) {
                Button("Open System Settings", action: openSettingsAction)
                    .buttonStyle(.bordered)
                Button("Check again", action: refreshAction)
                    .buttonStyle(.bordered)
            }
            Button("Continue without protection", action: continueAction)
                .buttonStyle(.link)
        }
    }

    private var relaunchContent: some View {
        VStack(spacing: 20) {
            StepHeading(
                icon: "arrow.clockwise.circle.fill",
                title: "One relaunch and you're set",
                subtitle:
                    "macOS shows PawGuard as allowed, but it decided this launch could not watch the keyboard and will not revisit that while the app is running. Reopening PawGuard clears it.",
                accent: accent,
                iconColor: .orange
            )
            PrimaryButton(title: "Relaunch PawGuard", accent: accent, action: relaunchAction)
            VStack(spacing: 6) {
                Text("Still stuck after relaunching?")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(
                    "Switch PawGuard off and on again in Accessibility. A permission granted to an earlier build of the app can linger as an entry that looks enabled but no longer counts."
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                Button("Open System Settings", action: openSettingsAction)
                    .buttonStyle(.link)
                    .font(.caption)
            }
            Button("Continue without protection", action: continueAction)
                .buttonStyle(.link)
        }
    }
}

private struct InstructionRow: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.primary.opacity(0.08)))
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Sensitivity

private struct SensitivitySetupView: View {
    @ObservedObject var settings: SettingsStore
    let accent: Color
    let continueAction: () -> Void

    private var explanation: String {
        switch settings.settings.sensitivity {
        case .relaxed:
            return "Steps in only for unmistakable paws. Best for very fast typists, heavy shortcut use, or gaming."
        case .balanced:
            return "The recommended default. Catches a paw landing while leaving ordinary typing alone."
        case .sensitive:
            return "Steps in earlier. Good if your cat is a regular visitor and you would rather it acted sooner."
        case .custom:
            return "Your own threshold, tuned in Settings under Detection."
        }
    }

    var body: some View {
        OnboardingCard {
            StepHeading(
                icon: "dial.medium",
                title: "Choose your sensitivity",
                subtitle: "You can change this at any time in Settings.",
                accent: accent
            )
            Picker("Sensitivity", selection: $settings.settings.sensitivity) {
                ForEach(SensitivityPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .top)
                .animation(.easeInOut(duration: 0.15), value: settings.settings.sensitivity)

            Label("If PawGuard ever gets it wrong, press ⌃⌥⌘⎋ to unlock straight away.", systemImage: "key")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            PrimaryButton(title: "Continue", accent: accent, action: continueAction)
        }
    }
}

// MARK: - Ready

private struct ReadyView: View {
    let catName: String
    let monitoringReady: Bool
    let accent: Color
    let finishAction: () -> Void

    var body: some View {
        OnboardingCard {
            StepHeading(
                icon: monitoringReady ? "checkmark.circle.fill" : "pawprint.circle.fill",
                title: "PawGuard is ready",
                subtitle: "We'll keep an eye out for \(catName)'s tiny paws. The mouse and trackpad always keep working.",
                accent: accent,
                iconColor: monitoringReady ? .green : accent
            )

            if !monitoringReady {
                Label(
                    "Protection is off until Accessibility is granted. You can finish that from the menu bar whenever you like.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }

            VStack(alignment: .leading, spacing: 10) {
                PrivacyRow(
                    icon: "menubar.arrow.up.rectangle",
                    title: "Live from the menu bar",
                    detail: "Status, statistics, and settings sit behind the paw icon."
                )
                PrivacyRow(
                    icon: "sparkles",
                    title: "Try it first",
                    detail: "Use Test Cat Mode to see exactly what happens when a paw lands."
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            PrimaryButton(title: "Start PawGuard", accent: accent, action: finishAction)
        }
    }
}
