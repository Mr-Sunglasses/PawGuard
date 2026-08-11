import XCTest

@testable import PawGuard

final class CatMessageTests: XCTestCase {
    func testDetectionMessagesNeverSuggestReadingUserContent() {
        for _ in 0..<50 {
            let message = CatMessage.detected(catName: "Milo")
            XCTAssertFalse(message.localizedCaseInsensitiveContains("code"))
            XCTAssertFalse(message.localizedCaseInsensitiveContains("text"))
            XCTAssertFalse(message.localizedCaseInsensitiveContains("typing content"))
        }
    }

    func testPersonalizedMessagesRenderValuesInsteadOfInterpolationSource() {
        XCTAssertEqual(CatMessage.released(catName: "Milo"), "Milo has left the keyboard ✨")
        XCTAssertEqual(CatMessage.subtitle(remaining: 17.2), "Input is paused for 18 more seconds.")
        XCTAssertFalse(CatMessage.subtitle(remaining: 17.2).contains("max("))
    }
}
