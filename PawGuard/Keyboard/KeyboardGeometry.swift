import Carbon
import CoreGraphics
import Foundation

/// Which side of the keyboard a key belongs to. Human touch typing alternates
/// hands far more often than a paw does.
enum KeyboardHand {
    case left
    case right
}

/// A key's approximate physical centre in key units, where 1.0 is the width of
/// a standard alphanumeric key. The origin is the top-left of the main block.
struct KeyPoint: Hashable {
    let x: Double
    let y: Double

    func distance(to other: KeyPoint) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return (dx * dx + dy * dy).squareRoot()
    }
}

enum KeyboardLayoutType {
    case ansi
    case iso
    case jis

    static var current: KeyboardLayoutType {
        let type = UInt32(bitPattern: Int32(KBGetLayoutType(Int16(LMGetKbdType()))))
        switch type {
        case UInt32(bitPattern: Int32(kKeyboardISO)): return .iso
        case UInt32(bitPattern: Int32(kKeyboardJIS)): return .jis
        default: return .ansi
        }
    }
}

enum KeyboardGeometry {
    /// Physical positions for the full keyboard, not just the alphanumeric
    /// block. A paw landing on the function row or the numeric keypad has to
    /// produce cluster evidence too, so every key macOS can report needs a
    /// coordinate.
    ///
    /// Virtual key codes are physical, not logical: key code 0 is the key in
    /// the "A" position on QWERTY, AZERTY, and Dvorak alike, so one table works
    /// for every input source. Only the physical enclosure (ANSI/ISO/JIS)
    /// changes the arrangement, which `layoutOverrides` handles.
    private static let ansiPositions: [CGKeyCode: KeyPoint] = [
        // Function row
        53: KeyPoint(x: 0, y: 0),  // Escape
        122: KeyPoint(x: 1, y: 0), 120: KeyPoint(x: 2, y: 0), 99: KeyPoint(x: 3, y: 0),
        118: KeyPoint(x: 4, y: 0), 96: KeyPoint(x: 5, y: 0), 97: KeyPoint(x: 6, y: 0),
        98: KeyPoint(x: 7, y: 0), 100: KeyPoint(x: 8, y: 0), 101: KeyPoint(x: 9, y: 0),
        109: KeyPoint(x: 10, y: 0), 103: KeyPoint(x: 11, y: 0), 111: KeyPoint(x: 12, y: 0),
        105: KeyPoint(x: 15.5, y: 0), 107: KeyPoint(x: 16.5, y: 0), 113: KeyPoint(x: 17.5, y: 0),
        106: KeyPoint(x: 19, y: 0), 64: KeyPoint(x: 20, y: 0), 79: KeyPoint(x: 21, y: 0),
        80: KeyPoint(x: 22, y: 0), 90: KeyPoint(x: 23, y: 0),

        // Number row
        50: KeyPoint(x: 0, y: 1),  // Grave
        18: KeyPoint(x: 1, y: 1), 19: KeyPoint(x: 2, y: 1), 20: KeyPoint(x: 3, y: 1),
        21: KeyPoint(x: 4, y: 1), 23: KeyPoint(x: 5, y: 1), 22: KeyPoint(x: 6, y: 1),
        26: KeyPoint(x: 7, y: 1), 28: KeyPoint(x: 8, y: 1), 25: KeyPoint(x: 9, y: 1),
        29: KeyPoint(x: 10, y: 1), 27: KeyPoint(x: 11, y: 1), 24: KeyPoint(x: 12, y: 1),
        51: KeyPoint(x: 13.5, y: 1),  // Delete

        // Upper letter row
        48: KeyPoint(x: 0.25, y: 2),  // Tab
        12: KeyPoint(x: 1.5, y: 2), 13: KeyPoint(x: 2.5, y: 2), 14: KeyPoint(x: 3.5, y: 2),
        15: KeyPoint(x: 4.5, y: 2), 17: KeyPoint(x: 5.5, y: 2), 16: KeyPoint(x: 6.5, y: 2),
        32: KeyPoint(x: 7.5, y: 2), 34: KeyPoint(x: 8.5, y: 2), 31: KeyPoint(x: 9.5, y: 2),
        35: KeyPoint(x: 10.5, y: 2), 33: KeyPoint(x: 11.5, y: 2), 30: KeyPoint(x: 12.5, y: 2),
        42: KeyPoint(x: 13.5, y: 2),  // Backslash

        // Home row
        57: KeyPoint(x: 0.4, y: 3),  // Caps Lock
        0: KeyPoint(x: 1.8, y: 3), 1: KeyPoint(x: 2.8, y: 3), 2: KeyPoint(x: 3.8, y: 3),
        3: KeyPoint(x: 4.8, y: 3), 5: KeyPoint(x: 5.8, y: 3), 4: KeyPoint(x: 6.8, y: 3),
        38: KeyPoint(x: 7.8, y: 3), 40: KeyPoint(x: 8.8, y: 3), 37: KeyPoint(x: 9.8, y: 3),
        41: KeyPoint(x: 10.8, y: 3), 39: KeyPoint(x: 11.8, y: 3),
        36: KeyPoint(x: 13.1, y: 3),  // Return

        // Lower letter row
        56: KeyPoint(x: 0.6, y: 4),  // Left Shift
        6: KeyPoint(x: 2.3, y: 4), 7: KeyPoint(x: 3.3, y: 4), 8: KeyPoint(x: 4.3, y: 4),
        9: KeyPoint(x: 5.3, y: 4), 11: KeyPoint(x: 6.3, y: 4), 45: KeyPoint(x: 7.3, y: 4),
        46: KeyPoint(x: 8.3, y: 4), 43: KeyPoint(x: 9.3, y: 4), 47: KeyPoint(x: 10.3, y: 4),
        44: KeyPoint(x: 11.3, y: 4),
        60: KeyPoint(x: 12.9, y: 4),  // Right Shift

        // Space row
        63: KeyPoint(x: 0, y: 5),  // Fn
        59: KeyPoint(x: 1, y: 5),  // Left Control
        58: KeyPoint(x: 2, y: 5),  // Left Option
        55: KeyPoint(x: 3.2, y: 5),  // Left Command
        49: KeyPoint(x: 5.8, y: 5),  // Space
        54: KeyPoint(x: 8.4, y: 5),  // Right Command
        61: KeyPoint(x: 9.6, y: 5),  // Right Option
        62: KeyPoint(x: 10.6, y: 5),  // Right Control

        // Arrow cluster
        123: KeyPoint(x: 11.6, y: 5), 126: KeyPoint(x: 12.6, y: 4.6),
        125: KeyPoint(x: 12.6, y: 5), 124: KeyPoint(x: 13.6, y: 5),

        // Navigation cluster on extended keyboards
        114: KeyPoint(x: 15.5, y: 1), 115: KeyPoint(x: 16.5, y: 1), 116: KeyPoint(x: 17.5, y: 1),
        117: KeyPoint(x: 15.5, y: 2), 119: KeyPoint(x: 16.5, y: 2), 121: KeyPoint(x: 17.5, y: 2),

        // Numeric keypad
        71: KeyPoint(x: 19, y: 1), 81: KeyPoint(x: 20, y: 1), 75: KeyPoint(x: 21, y: 1),
        67: KeyPoint(x: 22, y: 1),
        89: KeyPoint(x: 19, y: 2), 91: KeyPoint(x: 20, y: 2), 92: KeyPoint(x: 21, y: 2),
        78: KeyPoint(x: 22, y: 2),
        86: KeyPoint(x: 19, y: 3), 87: KeyPoint(x: 20, y: 3), 88: KeyPoint(x: 21, y: 3),
        69: KeyPoint(x: 22, y: 3.5),
        83: KeyPoint(x: 19, y: 4), 84: KeyPoint(x: 20, y: 4), 85: KeyPoint(x: 21, y: 4),
        82: KeyPoint(x: 19.5, y: 5), 65: KeyPoint(x: 21, y: 5), 76: KeyPoint(x: 22, y: 4.5),
    ]

    /// ISO enclosures move the grave key down beside the left shift and add the
    /// section key at the top left; JIS narrows the space bar and adds keys
    /// around it. Everything else keeps its ANSI position.
    private static let isoOverrides: [CGKeyCode: KeyPoint] = [
        10: KeyPoint(x: 0, y: 1),  // Section, where grave sits on ANSI
        50: KeyPoint(x: 1.65, y: 4),  // Grave, between left shift and Z
        42: KeyPoint(x: 12.6, y: 3),  // Backslash joins the home row
        36: KeyPoint(x: 13.2, y: 2.5),  // Tall return spans two rows
    ]

    private static let jisOverrides: [CGKeyCode: KeyPoint] = [
        93: KeyPoint(x: 4.4, y: 5),  // Yen / Kana row keys around a short space bar
        94: KeyPoint(x: 11.6, y: 4),
        104: KeyPoint(x: 4.6, y: 5), 102: KeyPoint(x: 7.6, y: 5),
        49: KeyPoint(x: 6.1, y: 5),
    ]

    private static let modifierCodes: Set<CGKeyCode> = [
        54, 55, 56, 57, 58, 59, 60, 61, 62, 63,
    ]

    /// Keys that a human presses on purpose but essentially never holds down
    /// together with letter keys. A paw covering them is strong evidence.
    private static let controlKeys: Set<CGKeyCode> = [
        53, 48, 36, 51, 71, 114, 115, 116, 117, 119, 121, 76,
    ]

    private static let functionRowKeys: Set<CGKeyCode> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111,
        105, 107, 113, 106, 64, 79, 80, 90,
    ]

    private static let letterKeys: Set<CGKeyCode> = [
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 15, 16, 17, 31, 32, 33,
        34, 35, 37, 38, 39, 40, 41, 45, 46, 47,
    ]

    /// Keys that insert exactly one character, so one backspace removes what
    /// they typed: letters, digits, punctuation, Space, the ISO and JIS extras,
    /// and the keypad's digits and operators. Return, Tab, Delete, Escape,
    /// navigation, and function keys are deliberately absent.
    private static let textKeys: Set<CGKeyCode> = Set(0...35)
        .union(37...47)
        .union([49, 50])  // Space, grave
        .union([65, 67, 69, 75, 78, 81])  // Keypad . * + / - =
        .union(82...89)  // Keypad 0-7
        .union([91, 92])  // Keypad 8, 9
        .union([93, 94, 95])  // JIS yen, underscore, keypad comma

    // These compact groups are commonly held intentionally for games and
    // navigation. A stable hold inside one of them should not look like a paw.
    private static let commonGamingKeys: Set<CGKeyCode> = [0, 1, 2, 12, 13, 14, 49]  // A S D Q W E Space
    private static let arrowKeys: Set<CGKeyCode> = [123, 124, 125, 126]

    /// Keys a human genuinely leans on for seconds at a time: deleting back
    /// through a line, scrolling, paging, running forward in a game, or holding
    /// a punctuation key to rule off a line of dashes. A long hold on any of
    /// these says nothing, whereas a long hold on a letter key is something
    /// fingers essentially never do.
    ///
    /// Adding a key here only blinds the single-key resting signal. A paw
    /// parked on one of them is still caught by the contact and cluster
    /// signals, which is the right trade: those signals cost nothing in false
    /// positives, and the resting signal is the one that has to stay silent
    /// while somebody holds a key on purpose.
    private static let commonlyHeldKeys: Set<CGKeyCode> =
        arrowKeys
        .union(commonGamingKeys)
        .union([
            51,  // Delete
            117,  // Forward delete
            115, 119,  // Home, End
            116, 121,  // Page up, page down
            48,  // Tab
            36,  // Return
            49,  // Space
            // Punctuation people hold to repeat: rules, ellipses, separators.
            27,  // Minus
            24,  // Equal
            47,  // Period
            43,  // Comma
            44,  // Slash
            42,  // Backslash
            50,  // Grave
        ])

    /// Distance in key units below which two keys are treated as touching for
    /// single-linkage clustering. A cat's paw pad spans roughly two keys.
    static let clusterLinkDistance: Double = 1.85

    /// Overridable so tests can pin a layout. Reads the physical enclosure type
    /// once at first use.
    ///
    /// Unsynchronised on purpose: the app never writes it, and tests write it
    /// only while no tap is running. Guarding every read would put a lock on
    /// the tap thread's hot path for a value that never changes in production.
    nonisolated(unsafe) static var layout: KeyboardLayoutType = .current {
        didSet { cachedPositions = buildPositions() }
    }

    nonisolated(unsafe) private static var cachedPositions: [CGKeyCode: KeyPoint] = buildPositions()

    private static func buildPositions() -> [CGKeyCode: KeyPoint] {
        var positions = ansiPositions
        switch layout {
        case .ansi:
            break
        case .iso:
            positions.merge(isoOverrides) { _, new in new }
        case .jis:
            positions.merge(jisOverrides) { _, new in new }
        }
        return positions
    }

    static func position(for keyCode: CGKeyCode) -> KeyPoint? {
        cachedPositions[keyCode]
    }

    static func isModifier(_ keyCode: CGKeyCode) -> Bool {
        modifierCodes.contains(keyCode)
    }

    /// True for a key whose press a single backspace takes back.
    static func isTextKey(_ keyCode: CGKeyCode) -> Bool {
        textKeys.contains(keyCode)
    }

    static func isKnownKey(_ keyCode: CGKeyCode) -> Bool {
        cachedPositions[keyCode] != nil
    }

    static func hand(for keyCode: CGKeyCode) -> KeyboardHand? {
        guard let point = position(for: keyCode) else { return nil }
        // The main block splits between T/G/B and Y/H/N; everything to the
        // right of the alphanumeric block is reached with the right hand.
        return point.x < 6.2 ? .left : .right
    }

    /// Mean pairwise distance between the given keys, in key units. Lower means
    /// a more compact footprint.
    static func spread(of keyCodes: Set<CGKeyCode>) -> Double? {
        let points = keyCodes.compactMap(position(for:))
        guard points.count >= 2 else { return nil }
        var total = 0.0
        var pairs = 0
        for index in points.indices {
            for other in points.index(after: index)..<points.endIndex {
                total += points[index].distance(to: points[other])
                pairs += 1
            }
        }
        guard pairs > 0 else { return nil }
        return total / Double(pairs)
    }

    /// How compact a group is on a 0-1 scale, where 1 means the keys are
    /// touching and 0 means they are scattered across the keyboard.
    ///
    /// Keys one unit apart are as tight as physically possible, so that is the
    /// top of the scale rather than an unreachable zero spread. The loose end
    /// grows with the square root of the key count, because a paw covering more
    /// keys necessarily covers more area.
    static func compactness(of keyCodes: Set<CGKeyCode>) -> Double {
        let points = keyCodes.compactMap(position(for:))
        guard points.count >= 2, let spread = spread(of: keyCodes) else { return 0 }
        let looseLimit = 1.15 * Double(points.count).squareRoot()
        return 1 - detectionRamp(spread, from: 1.0, to: looseLimit)
    }

    /// True when the keys occupy a compact area consistent with a single paw.
    /// Replaces the old bounding-box test, which accepted sparse keys inside a
    /// wide rectangle and rejected four adjacent keys in one row.
    ///
    /// Two keys count when they are physically touching. A kitten's pad covers
    /// two keys and no more, so a three-key floor here made the smallest real
    /// contact invisible to every clustering signal at once. Two keys are much
    /// weaker evidence than three, and the score reflects that in the ramps
    /// rather than by refusing to see them.
    static func isTightCluster(_ keyCodes: Set<CGKeyCode>) -> Bool {
        let points = keyCodes.compactMap(position(for:))
        guard points.count >= 2, let spread = spread(of: keyCodes) else { return false }
        if points.count == 2 { return spread <= DetectionRules.pawContactDistance }
        return spread <= 1.15 * Double(points.count).squareRoot()
    }

    /// True when two keys are close enough to sit under one paw pad at once.
    static func isPawContact(_ first: CGKeyCode, _ second: CGKeyCode) -> Bool {
        guard first != second,
            let a = position(for: first),
            let b = position(for: second)
        else { return false }
        return a.distance(to: b) <= DetectionRules.pawContactDistance
    }

    /// Groups keys into physically contiguous clusters using single linkage. A
    /// cat lying across the keyboard usually produces two separate compact
    /// groups, which a single-cluster test would miss entirely.
    static func clusters(
        of keyCodes: Set<CGKeyCode>,
        linkDistance: Double = clusterLinkDistance
    ) -> [Set<CGKeyCode>] {
        let placed = keyCodes.filter { position(for: $0) != nil }
        guard !placed.isEmpty else { return [] }

        var remaining = placed
        var result: [Set<CGKeyCode>] = []
        while let seed = remaining.first {
            remaining.remove(seed)
            var cluster: Set<CGKeyCode> = [seed]
            var frontier = [seed]
            while let current = frontier.popLast() {
                guard let currentPoint = position(for: current) else { continue }
                let neighbours = remaining.filter { candidate in
                    guard let candidatePoint = position(for: candidate) else { return false }
                    return currentPoint.distance(to: candidatePoint) <= linkDistance
                }
                for neighbour in neighbours {
                    remaining.remove(neighbour)
                    cluster.insert(neighbour)
                    frontier.append(neighbour)
                }
            }
            result.append(cluster)
        }
        return result.sorted { $0.count > $1.count }
    }

    /// True when a human plausibly holds this key down for several seconds.
    static func isCommonlyHeld(_ keyCode: CGKeyCode) -> Bool {
        commonlyHeldKeys.contains(keyCode) || isModifier(keyCode) || functionRowKeys.contains(keyCode)
    }

    /// Holding a single W to run forward or a single arrow to scroll is as
    /// intentional as holding the whole WASD cluster, so one key qualifies too.
    static func isLikelyIntentionalHold(_ keyCodes: Set<CGKeyCode>) -> Bool {
        guard (1...4).contains(keyCodes.count) else { return false }
        return keyCodes.isSubset(of: commonGamingKeys) || keyCodes.isSubset(of: arrowKeys)
    }

    /// Key combinations that human typing does not produce: a function-row key
    /// or a structural key such as Escape or Return physically held at the same
    /// time as letter keys.
    static func isImprobableCombination(_ keyCodes: Set<CGKeyCode>) -> Bool {
        guard keyCodes.count >= 3 else { return false }
        let letters = keyCodes.intersection(letterKeys)
        guard letters.count >= 2 else { return false }
        if !keyCodes.intersection(functionRowKeys).isEmpty { return true }
        return keyCodes.intersection(controlKeys).count >= 1
    }
}
