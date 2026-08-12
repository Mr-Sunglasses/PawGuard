import CoreGraphics
import XCTest

@testable import PawGuard

final class KeyboardGeometryTests: XCTestCase {
    override func setUp() {
        super.setUp()
        KeyboardGeometry.layout = .ansi
    }

    func testEveryKeyTheDetectorCanSeeHasAPosition() {
        // A paw on the function row or the numeric keypad has to produce
        // cluster evidence, which it cannot do without coordinates.
        let mustBePlaced: [CGKeyCode] = [
            53, 122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111,  // Escape and F1-F12
            51, 48, 36, 57, 49,  // Delete, Tab, Return, Caps Lock, Space
            123, 124, 125, 126,  // Arrows
            82, 83, 84, 85, 86, 87, 88, 89, 91, 92, 65, 67, 69, 75, 78, 81,  // Keypad
            115, 116, 117, 119, 121,  // Navigation cluster
        ]
        for key in mustBePlaced {
            XCTAssertNotNil(KeyboardGeometry.position(for: key), "key code \(key) has no position")
        }
    }

    func testAdjacentKeysAreOneUnitApart() {
        guard let f = KeyboardGeometry.position(for: 3), let g = KeyboardGeometry.position(for: 5) else {
            return XCTFail("home row keys must be placed")
        }
        XCTAssertEqual(f.distance(to: g), 1, accuracy: 0.001)
    }

    func testFourAdjacentKeysInOneRowCountAsTight() {
        // The old bounding-box rule rejected this because the row spanned more
        // than its width allowance.
        XCTAssertTrue(KeyboardGeometry.isTightCluster([3, 5, 4, 38]))  // F G H J
    }

    func testSparseKeysInsideAWideBoxAreNotTight() {
        // Q, P, Z and slash sit inside a large rectangle but are nowhere near
        // each other.
        XCTAssertFalse(KeyboardGeometry.isTightCluster([12, 35, 6, 44]))
    }

    func testTypingRolloverKeysAreNotTight() {
        XCTAssertFalse(KeyboardGeometry.isTightCluster([4, 14, 37]))  // H E L
    }

    func testCompactnessRewardsTouchingKeys() {
        let touching = KeyboardGeometry.compactness(of: [3, 5, 4])  // F G H
        let scattered = KeyboardGeometry.compactness(of: [12, 35, 6])  // Q P Z
        XCTAssertGreaterThan(touching, 0.5)
        XCTAssertEqual(scattered, 0, accuracy: 0.001)
    }

    func testSingleLinkageFindsTwoSeparateClusters() {
        // A cat lying across the keyboard: one group on the left, one on the right.
        let clusters = KeyboardGeometry.clusters(of: [12, 13, 40, 37])
        XCTAssertEqual(clusters.count, 2)
        XCTAssertTrue(clusters.allSatisfy { $0.count == 2 })
    }

    func testTouchingKeysFormASingleCluster() {
        XCTAssertEqual(KeyboardGeometry.clusters(of: [3, 5, 4, 38]).count, 1)
    }

    func testHandAssignmentSplitsTheKeyboard() {
        XCTAssertEqual(KeyboardGeometry.hand(for: 0), .left)  // A
        XCTAssertEqual(KeyboardGeometry.hand(for: 37), .right)  // L
        XCTAssertEqual(KeyboardGeometry.hand(for: 17), .left)  // T
        XCTAssertEqual(KeyboardGeometry.hand(for: 16), .right)  // Y
    }

    func testFunctionKeysHeldWithLettersAreImprobable() {
        XCTAssertTrue(KeyboardGeometry.isImprobableCombination([96, 97, 3, 5]))
    }

    func testOrdinaryLetterGroupsAreNotImprobable() {
        XCTAssertFalse(KeyboardGeometry.isImprobableCombination([3, 5, 4, 38]))
    }

    func testShortcutChordsAreNotImprobable() {
        // Modifiers are tracked separately and never reach this test.
        XCTAssertFalse(KeyboardGeometry.isImprobableCombination([0, 1]))
    }

    func testIsoLayoutMovesTheGraveKey() {
        KeyboardGeometry.layout = .iso
        defer { KeyboardGeometry.layout = .ansi }
        guard let grave = KeyboardGeometry.position(for: 50) else { return XCTFail("grave must be placed") }
        XCTAssertEqual(grave.y, 4, accuracy: 0.001)
        XCTAssertNotNil(KeyboardGeometry.position(for: 10))
    }

    func testGamingAndArrowHoldsStayExempt() {
        XCTAssertTrue(KeyboardGeometry.isLikelyIntentionalHold([0, 1, 2, 13]))
        XCTAssertTrue(KeyboardGeometry.isLikelyIntentionalHold([123, 126]))
        XCTAssertFalse(KeyboardGeometry.isLikelyIntentionalHold([3, 5, 4, 38]))
    }
}
