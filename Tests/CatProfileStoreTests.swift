import Foundation
import XCTest

@testable import PawGuard

@MainActor
final class CatProfileStoreTests: XCTestCase {
    func testProfileCreationRenameAndAvatarSelectionPersist() {
        let suiteName = "PawGuardTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = CatProfileStore(defaults: defaults)
        let profile = store.createProfile(name: "Milo")
        XCTAssertEqual(store.activeProfile?.displayName, "Milo")

        var updated = profile
        updated.name = "Luna"
        updated.photoPaths = ["/tmp/avatar-a.jpg", "/tmp/avatar-b.jpg"]
        store.update(updated)
        store.selectPhoto(at: 1)

        let restored = CatProfileStore(defaults: defaults)
        XCTAssertEqual(restored.activeProfile?.name, "Luna")
        XCTAssertEqual(restored.activeProfile?.selectedAvatarIndex, 1)
        XCTAssertEqual(restored.activeProfile?.photoPaths.count, 2)
    }

    func testProfileWithoutPhotoUsesGenericFallbackData() {
        let profile = CatProfile(name: "Oscar")
        XCTAssertNil(profile.selectedPhotoPath)
        XCTAssertEqual(profile.displayName, "Oscar")
    }

    func testInvalidActiveProfileFallsBackToFirstProfile() {
        let suiteName = "PawGuardTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = CatProfile(name: "First")
        let data = try! JSONEncoder().encode([first])
        defaults.set(data, forKey: "pawguard.catProfiles")
        defaults.set(UUID().uuidString, forKey: "pawguard.activeCatID")

        let restored = CatProfileStore(defaults: defaults)
        XCTAssertEqual(restored.activeProfile?.id, first.id)
    }
}
