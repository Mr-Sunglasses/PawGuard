import SwiftUI
import UniformTypeIdentifiers

struct CatProfileSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var name = ""
    @State private var showingImporter = false

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
        }
        .formStyle(.grouped)
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

    private func saveName() {
        appState.updateActiveCatName(name.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
