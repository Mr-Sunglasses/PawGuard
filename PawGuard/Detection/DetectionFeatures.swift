import CoreGraphics
import Foundation

/// Everything the score is derived from, extracted once per evaluation.
///
/// Keeping extraction separate from scoring means the features can be logged,
/// replayed, and tested on their own, and the score stays readable.
struct DetectionFeatures {
    /// Non-modifier keys physically down right now.
    var heldKeys: Set<CGKeyCode> = []
    var simultaneousCount: Int = 0

    /// Largest physically contiguous group of held keys, and how tightly it is
    /// packed on a 0-1 scale.
    var largestClusterSize: Int = 0
    var clusterCompactness: Double = 0
    /// Separate contiguous groups of two or more keys, as produced by a cat
    /// lying across the keyboard with its chest on one area and a paw on another.
    var separateClusterCount: Int = 0

    /// Largest tight cluster formed by key-downs inside `simultaneousWindow`.
    var rapidClusterCount: Int = 0
    /// Most key-downs landing inside `synchronyWindow`; a paw lands far more
    /// simultaneously than fingers roll.
    var synchronyCount: Int = 0

    var burstCount: Int = 0
    /// Sustained unique keys per second over the general window.
    var keyRate: Double = 0
    /// Median gap between successive key-downs. Human digraphs bottom out
    /// around 50 ms; a paw impact is far below that.
    var medianInterval: TimeInterval = .infinity
    /// Fraction of successive key-downs that switch hands. Fast human typing
    /// alternates; a paw does not.
    var handAlternationRate: Double = 0

    var longHeldCount: Int = 0
    var extendedHeldCount: Int = 0
    var maxHoldDuration: TimeInterval = 0
    var repeatCount: Int = 0

    var improbableCombination: Bool = false
    var intentionalHold: Bool = false
    var hasShortcutModifier: Bool = false

    static func extract(
        heldKeys: [CGKeyCode: TimeInterval],
        samples: [KeyboardEventSample],
        modifiers: CGEventFlags,
        at timestamp: TimeInterval
    ) -> DetectionFeatures {
        var features = DetectionFeatures()

        let held = Set(heldKeys.keys)
        features.heldKeys = held
        features.simultaneousCount = held.count

        let clusters = KeyboardGeometry.clusters(of: held)
        if let largest = clusters.first {
            features.largestClusterSize = largest.count
            features.clusterCompactness = KeyboardGeometry.compactness(of: largest)
        }
        features.separateClusterCount = clusters.filter { $0.count >= 2 }.count

        // Only key-downs inside the rolling window, oldest first. Repeats and
        // modifiers are excluded so autorepeat cannot inflate timing features.
        var keyDowns: [KeyboardEventSample] = []
        for sample in samples {
            guard sample.type == .keyDown, !sample.isRepeat else { continue }
            guard !KeyboardGeometry.isModifier(sample.keyCode) else { continue }
            let age = timestamp - sample.timestamp
            guard age >= 0, age <= DetectionRules.generalWindow else { continue }
            keyDowns.append(sample)
        }
        keyDowns.sort { $0.timestamp < $1.timestamp }

        var burstKeys = Set<CGKeyCode>()
        var windowKeys = Set<CGKeyCode>()
        for sample in keyDowns {
            windowKeys.insert(sample.keyCode)
            if timestamp - sample.timestamp <= DetectionRules.fastBurstWindow {
                burstKeys.insert(sample.keyCode)
            }
        }
        features.burstCount = burstKeys.count
        features.keyRate = Double(windowKeys.count) / DetectionRules.generalWindow
        features.rapidClusterCount = maximumRapidClusterCount(in: keyDowns)
        features.synchronyCount = maximumSynchronyCount(in: keyDowns)
        features.medianInterval = medianInterval(in: keyDowns)
        features.handAlternationRate = handAlternationRate(in: keyDowns)

        features.longHeldCount =
            heldKeys.values.filter {
                timestamp - $0 >= DetectionRules.holdThreshold
            }.count
        features.extendedHeldCount =
            heldKeys.values.filter {
                timestamp - $0 >= DetectionRules.extendedHoldThreshold
            }.count
        features.maxHoldDuration = heldKeys.values.map { timestamp - $0 }.max() ?? 0

        features.repeatCount =
            samples.filter {
                $0.type == .keyDown && $0.isRepeat && timestamp >= $0.timestamp
                    && timestamp - $0.timestamp <= DetectionRules.fastBurstWindow
            }.count

        features.improbableCombination = KeyboardGeometry.isImprobableCombination(held)
        features.intentionalHold = KeyboardGeometry.isLikelyIntentionalHold(held)
        let shortcutModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate]
        features.hasShortcutModifier = !modifiers.intersection(shortcutModifiers).isEmpty

        return features
    }

    /// Largest set of keys that both land inside `simultaneousWindow` and form
    /// a tight cluster. A paw often lands as a compact three- or four-key impact.
    private static func maximumRapidClusterCount(in keyDowns: [KeyboardEventSample]) -> Int {
        guard keyDowns.count >= 3 else { return 0 }
        var maximum = 0
        for startIndex in keyDowns.indices {
            var keys = Set<CGKeyCode>()
            for sample in keyDowns[startIndex...] {
                guard sample.timestamp - keyDowns[startIndex].timestamp <= DetectionRules.simultaneousWindow else {
                    break
                }
                keys.insert(sample.keyCode)
                if keys.count >= 3, KeyboardGeometry.isTightCluster(keys) {
                    maximum = max(maximum, keys.count)
                }
            }
        }
        return maximum
    }

    private static func maximumSynchronyCount(in keyDowns: [KeyboardEventSample]) -> Int {
        guard !keyDowns.isEmpty else { return 0 }
        var maximum = 0
        for startIndex in keyDowns.indices {
            var keys = Set<CGKeyCode>()
            for sample in keyDowns[startIndex...] {
                guard sample.timestamp - keyDowns[startIndex].timestamp <= DetectionRules.synchronyWindow else {
                    break
                }
                keys.insert(sample.keyCode)
            }
            maximum = max(maximum, keys.count)
        }
        return maximum
    }

    private static func medianInterval(in keyDowns: [KeyboardEventSample]) -> TimeInterval {
        guard keyDowns.count >= 3 else { return .infinity }
        var intervals: [TimeInterval] = []
        for index in 1..<keyDowns.count {
            intervals.append(keyDowns[index].timestamp - keyDowns[index - 1].timestamp)
        }
        intervals.sort()
        let middle = intervals.count / 2
        if intervals.count.isMultiple(of: 2) {
            return (intervals[middle - 1] + intervals[middle]) / 2
        }
        return intervals[middle]
    }

    private static func handAlternationRate(in keyDowns: [KeyboardEventSample]) -> Double {
        let hands = keyDowns.compactMap { KeyboardGeometry.hand(for: $0.keyCode) }
        guard hands.count >= 3 else { return 0 }
        var switches = 0
        for index in 1..<hands.count where hands[index] != hands[index - 1] {
            switches += 1
        }
        return Double(switches) / Double(hands.count - 1)
    }
}
