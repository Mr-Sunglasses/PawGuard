import Foundation

struct CatProfile: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var photoPaths: [String]
    var selectedAvatarIndex: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        photoPaths: [String] = [],
        selectedAvatarIndex: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.photoPaths = photoPaths
        self.selectedAvatarIndex = selectedAvatarIndex
        self.createdAt = createdAt
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "your cat" : trimmed
    }

    var selectedPhotoPath: String? {
        guard !photoPaths.isEmpty else { return nil }
        let index = min(max(selectedAvatarIndex, 0), photoPaths.count - 1)
        return photoPaths[index]
    }
}
