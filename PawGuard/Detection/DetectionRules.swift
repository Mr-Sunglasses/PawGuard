import Foundation

enum DetectionRules {
    /// Two key-downs closer than this are effectively one physical impact.
    static let synchronyWindow: TimeInterval = 0.030
    static let simultaneousWindow: TimeInterval = 0.120
    static let fastBurstWindow: TimeInterval = 0.450
    static let generalWindow: TimeInterval = 1.200
    static let holdThreshold: TimeInterval = 0.700
    static let extendedHoldThreshold: TimeInterval = 1.500
    static let defaultThreshold = 70
    static let cooldown: TimeInterval = 3
    static let activityExtension: TimeInterval = 8

    /// How long input is silently buffered while a borderline detection is
    /// confirmed. Short enough to be imperceptible when it turns out to be a
    /// human, long enough for a paw to settle.
    static let graceWindow: TimeInterval = 0.180

    /// A detection at or above this score is acted on immediately, with no
    /// grace window. Reserved for evidence a human cannot produce.
    static let immediateScore = 95

    /// Held keys with no event of any kind for this long are assumed to have
    /// had their key-up lost and are dropped.
    static let staleHoldTimeout: TimeInterval = 30

    /// Fastest sustained unique-key rate a human reaches, in keys per second.
    /// Competitive typists peak near 15; sustained rates above this are not
    /// produced by fingers.
    static let humanKeyRateCeiling: Double = 21
    static let humanKeyRateFloor: Double = 13
}

/// Every tunable in the score, in one place, so the detector reads as a policy
/// rather than a pile of literals. Codable so a profile can carry its own
/// calibrated copy.
struct DetectionWeights: Codable, Equatable {
    var overlap: Double = 52
    var extremeOverlap: Double = 30
    var cluster: Double = 44
    var rapidCluster: Double = 30
    var synchrony: Double = 30
    var multiKeyHold: Double = 46
    var multiCluster: Double = 24
    var improbableCombination: Double = 28
    var burst: Double = 16
    var keyRate: Double = 24
    var rhythm: Double = 18
    var excessiveRepeat: Double = 14

    /// Multipliers applied after the evidence is summed.
    var sequentialDamping: Double = 0.25
    var intentionalHoldDamping: Double = 0.22
    var shortcutDamping: Double = 0.45
    var alternationDamping: Double = 0.6

    static let `default` = DetectionWeights()
}

/// Linear ramp from 0 at `start` to 1 at `end`, clamped at both ends. Used
/// instead of integer step functions so one extra key cannot swing the score by
/// tens of points.
func detectionRamp(_ value: Double, from start: Double, to end: Double) -> Double {
    guard end > start else { return value >= end ? 1 : 0 }
    return max(0, min(1, (value - start) / (end - start)))
}
