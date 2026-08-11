import Foundation

@MainActor
final class CatProfileStore: ObservableObject {
    @Published private(set) var profiles: [CatProfile]
    @Published private(set) var activeProfileID: UUID?

    private let defaults: UserDefaults
    private let profilesKey = "pawguard.catProfiles"
    private let activeKey = "pawguard.activeCatID"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: profilesKey),
            let decoded = try? JSONDecoder().decode([CatProfile].self, from: data)
        {
            profiles = decoded
        } else {
            profiles = []
        }
        if let rawID = defaults.string(forKey: activeKey) {
            activeProfileID = UUID(uuidString: rawID)
        } else {
            activeProfileID = profiles.first?.id
        }
        if (activeProfileID == nil || !profiles.contains(where: { $0.id == activeProfileID })),
            let first = profiles.first
        {
            activeProfileID = first.id
        }
    }

    var activeProfile: CatProfile? {
        guard let activeProfileID else { return nil }
        return profiles.first { $0.id == activeProfileID }
    }

    @discardableResult
    func createProfile(name: String) -> CatProfile {
        let profile = CatProfile(name: name)
        profiles.append(profile)
        activeProfileID = profile.id
        save()
        return profile
    }

    func setActiveProfile(_ profileID: UUID) {
        guard profiles.contains(where: { $0.id == profileID }) else { return }
        activeProfileID = profileID
        save()
    }

    func update(_ profile: CatProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile
        save()
    }

    func updateActiveName(_ name: String) {
        guard var profile = activeProfile else { return }
        profile.name = name
        update(profile)
    }

    func updateName(_ name: String, for profileID: UUID) {
        guard var profile = profiles.first(where: { $0.id == profileID }) else { return }
        profile.name = name
        update(profile)
    }

    func removePhoto(at index: Int) {
        guard var profile = activeProfile, profile.photoPaths.indices.contains(index) else { return }
        profile.photoPaths.remove(at: index)
        profile.selectedAvatarIndex = min(profile.selectedAvatarIndex, max(0, profile.photoPaths.count - 1))
        update(profile)
    }

    func selectPhoto(at index: Int) {
        guard var profile = activeProfile, profile.photoPaths.indices.contains(index) else { return }
        profile.selectedAvatarIndex = index
        update(profile)
    }

    func save() {
        if let data = try? JSONEncoder().encode(profiles) {
            defaults.set(data, forKey: profilesKey)
        }
        if let activeProfileID {
            defaults.set(activeProfileID.uuidString, forKey: activeKey)
        } else {
            defaults.removeObject(forKey: activeKey)
        }
    }
}
