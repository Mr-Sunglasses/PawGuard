import CoreGraphics
import Foundation

struct KeyPosition: Hashable {
    let row: Int
    let x: Double
}

enum KeyboardGeometry {
    // Approximate ANSI MacBook positions. The detector only uses relative proximity.
    private static let positions: [CGKeyCode: KeyPosition] = [
        50: .init(row: 0, x: 0),
        18: .init(row: 0, x: 1), 19: .init(row: 0, x: 2), 20: .init(row: 0, x: 3),
        21: .init(row: 0, x: 4), 23: .init(row: 0, x: 5), 22: .init(row: 0, x: 6),
        26: .init(row: 0, x: 7), 28: .init(row: 0, x: 8), 25: .init(row: 0, x: 9),
        29: .init(row: 0, x: 10), 27: .init(row: 0, x: 11), 24: .init(row: 0, x: 12),
        12: .init(row: 1, x: 0.4), 13: .init(row: 1, x: 1.4), 14: .init(row: 1, x: 2.4),
        15: .init(row: 1, x: 3.4), 17: .init(row: 1, x: 4.4), 16: .init(row: 1, x: 5.4),
        32: .init(row: 1, x: 6.4), 34: .init(row: 1, x: 7.4), 31: .init(row: 1, x: 8.4),
        35: .init(row: 1, x: 9.4), 33: .init(row: 1, x: 10.4), 30: .init(row: 1, x: 11.4),
        0: .init(row: 2, x: 0.7), 1: .init(row: 2, x: 1.7), 2: .init(row: 2, x: 2.7),
        3: .init(row: 2, x: 3.7), 5: .init(row: 2, x: 4.7), 4: .init(row: 2, x: 5.7),
        38: .init(row: 2, x: 6.7), 40: .init(row: 2, x: 7.7), 37: .init(row: 2, x: 8.7),
        41: .init(row: 2, x: 9.7), 39: .init(row: 2, x: 10.7), 42: .init(row: 2, x: 11.7),
        6: .init(row: 3, x: 1.1), 7: .init(row: 3, x: 2.1), 8: .init(row: 3, x: 3.1),
        9: .init(row: 3, x: 4.1), 11: .init(row: 3, x: 5.1), 45: .init(row: 3, x: 6.1),
        46: .init(row: 3, x: 7.1), 43: .init(row: 3, x: 8.1), 47: .init(row: 3, x: 9.1),
        44: .init(row: 3, x: 10.1),
        48: .init(row: 4, x: 0), 49: .init(row: 4, x: 4.8),
    ]

    private static let modifierCodes: Set<CGKeyCode> = [
        54, 55, 56, 57, 58, 59, 60, 61, 62, 63,
    ]

    // These compact groups are commonly held intentionally for games and
    // navigation. A stable hold inside one of them should not look like a paw.
    private static let commonGamingKeys: Set<CGKeyCode> = [0, 1, 2, 12, 13, 14, 49]  // A S D Q W E Space
    private static let arrowKeys: Set<CGKeyCode> = [123, 124, 125, 126]

    static func position(for keyCode: CGKeyCode) -> KeyPosition? {
        positions[keyCode]
    }

    static func isModifier(_ keyCode: CGKeyCode) -> Bool {
        modifierCodes.contains(keyCode)
    }

    static func isTightCluster(_ keyCodes: Set<CGKeyCode>) -> Bool {
        let positions = keyCodes.compactMap(position(for:))
        guard positions.count >= 3 else { return false }
        let xValues = positions.map(\.x)
        let rows = positions.map(\.row)
        guard let minX = xValues.min(), let maxX = xValues.max(),
            let minRow = rows.min(), let maxRow = rows.max()
        else { return false }
        return maxX - minX <= 3.6 && maxRow - minRow <= 2
    }

    static func isLikelyIntentionalHold(_ keyCodes: Set<CGKeyCode>) -> Bool {
        guard (2...4).contains(keyCodes.count) else { return false }
        return keyCodes.isSubset(of: commonGamingKeys) || keyCodes.isSubset(of: arrowKeys)
    }
}
