import SwiftUI
import UniformTypeIdentifiers

struct CatProfileSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var name = ""
    @State private var showingImporter = false
    @State private var confirmingDeletion = false

    private var profile: CatProfile? { appState.activeCat }

    var body: some View {
        Form {
            Section("Active cat") {
                HStack(spacing: 14) {
                    CatAvatarView(path: profile?.selectedPhotoPath, size: 68, cornerRadius: 20, accent: accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile?.displayName ?? "No cat profile")
                            .font(.headline)
                        Text("Photos remain on this Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                TextField("Cat name", text: $name)
                    .onSubmit(saveName)
                Button("Save Name", action: saveName)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name == profile?.name)
            }

            Section("Profile photos") {
                if let profile, !profile.photoPaths.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(Array(profile.photoPaths.enumerated()), id: \.offset) { index, path in
                                VStack(spacing: 5) {
                                    Button {
                                        appState.selectAvatar(at: index)
                                    } label: {
                                        CatAvatarView(path: path, size: 74, cornerRadius: 16, accent: accent)
                                            .overlay {
                                                if index == profile.selectedAvatarIndex {
                                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                        .strokeBorder(accent, lineWidth: 3)
                                                }
                                            }
                                    }
                                    .buttonStyle(.plain)
                                    Button("Remove") { appState.removePhoto(at: index) }
                                        .buttonStyle(.link)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                } else {
                    Text("Using the generic cat avatar.")
                        .foregroundStyle(.secondary)
                }
                Button("Add or replace photos…") { showingImporter = true }
            }

            if let profile {
                Section {
                    Button("Delete \(profile.displayName)’s Profile…", role: .destructive) {
                        confirmingDeletion = true
                    }
                    Text("Removes the name and every photo PawGuard stored for this cat. Detection is unaffected.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Delete \(profile?.displayName ?? "this cat")’s profile?",
            isPresented: $confirmingDeletion
        ) {
            Button("Delete Profile", role: .destructive) { deleteProfile() }
        } message: {
            Text("Its photos are removed from this Mac. PawGuard will ask you to set up a cat again if none remain.")
        }
        .onAppear { name = profile?.name ?? "" }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.jpeg, .png, .heic],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { appState.importPhotos(urls) }
        }
    }

    private var accent: Color {
        PawGuardStyle.accent(for: appState.settingsStore.settings.accentTheme)
    }

    private func deleteProfile() {
        guard let profile else { return }
        appState.deleteCatProfile(profile.id)
        name = appState.activeCat?.name ?? ""
        if appState.needsOnboarding { openWindow(id: "setup") }
    }

    private func saveName() {
        appState.updateActiveCatName(name.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
