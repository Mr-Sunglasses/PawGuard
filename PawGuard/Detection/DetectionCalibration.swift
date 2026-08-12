import CoreGraphics
import Foundation

/// The shape of one detection, with no key identities beyond the physical codes
/// needed to recognise a repeat of the same intentional chord. Never contains
/// characters, text, or anything about the app that had focus.
struct DetectionSnapshot: Codable, Equatable {
    var date: Date
    var score: Int
    var simultaneousCount: Int
    var heldKeys: [UInt16]
    var clusterCompactness: Double
    var signals: [String]
    var wasFalsePositive: Bool?

    init(date: Date = .now, result: DetectionResult) {
        self.date = date
        score = result.score
        simultaneousCount = result.simultaneousKeyCount
        heldKeys = result.features.heldKeys.sorted()
        clusterCompactness = result.features.clusterCompactness
        signals = result.signals.map(\.rawValue).sorted()
        wasFalsePositive = nil
    }
}

/// What PawGuard has learned about this particular user and cat.
struct CalibrationProfile: Codable, Equatable {
    /// Added to the user's chosen threshold. Positive means harder to trigger.
    var thresholdOffset: Int = 0
    /// Chords the user has repeatedly told us are intentional.
    var allowedKeySets: [[UInt16]] = []
    /// How often this user genuinely overlaps three or more keys while typing.
    var overlapSampleCount: Int = 0
    var heavyOverlapCount: Int = 0
    var observedPeakKeyRate: Double = 0
    var falsePositiveCount: Int = 0
    var confirmedCount: Int = 0

    static let maximumOffset = 20
    static let minimumOffset = -10

    var overlapRate: Double {
        guard overlapSampleCount > 0 else { return 0 }
        return Double(heavyOverlapCount) / Double(overlapSampleCount)
    }
}

/// Learns from the user instead of shipping one set of constants for everyone.
///
/// The signal is free and unambiguous: hitting emergency unlock seconds after a
/// lock means PawGuard was wrong. Letting the lock run its course means it was
/// right.
@MainActor
final class CalibrationStore: ObservableObject {
    @Published private(set) var profile: CalibrationProfile
    @Published private(set) var recentDetections: [DetectionSnapshot] = []

    /// A lock dismissed faster than this is treated as a false positive.
    static let falsePositiveWindow: TimeInterval = 6
    private static let historyLimit = 25
    /// How many overlap samples accumulate before the profile is updated.
    static let calibrationBatchSize = 400

    private var pendingOverlapSamples = 0
    private var pendingHeavyOverlaps = 0
    private var pendingPeakKeyRate: Double = 0

    private let defaults: UserDefaults
    private let profileKey = "pawguard.calibration"
    private let historyKey = "pawguard.detectionHistory"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: profileKey),
            let decoded = try? JSONDecoder().decode(CalibrationProfile.self, from: data)
        {
            profile = decoded
        } else {
            profile = CalibrationProfile()
        }
        if let data = defaults.data(forKey: historyKey),
            let decoded = try? JSONDecoder().decode([DetectionSnapshot].self, from: data)
        {
            recentDetections = decoded
        }
    }

    var allowedKeySets: [Set<CGKeyCode>] {
        profile.allowedKeySets.map { Set($0) }
    }

    func effectiveThreshold(base: Int, adaptive: Bool) -> Int {
        guard adaptive else { return base }
        return max(30, min(100, base + profile.thresholdOffset))
    }

    func recordDetection(_ result: DetectionResult) {
        recentDetections.insert(DetectionSnapshot(result: result), at: 0)
        if recentDetections.count > Self.historyLimit {
            recentDetections.removeLast(recentDetections.count - Self.historyLimit)
        }
        saveHistory()
    }

    /// The user dismissed a lock almost immediately: PawGuard was wrong.
    func recordFalsePositive() {
        guard !recentDetections.isEmpty else { return }
        recentDetections[0].wasFalsePositive = true
        profile.falsePositiveCount += 1
        profile.thresholdOffset = min(CalibrationProfile.maximumOffset, profile.thresholdOffset + 5)

        // A chord that has now been wrong twice is something this user does on
        // purpose. Stop treating it as evidence at all.
        let keys = recentDetections[0].heldKeys
        if keys.count >= 2 {
            let priorMisses = recentDetections.filter { $0.wasFalsePositive == true && $0.heldKeys == keys }.count
            if priorMisses >= 2, !profile.allowedKeySets.contains(keys) {
                profile.allowedKeySets.append(keys)
            }
        }
        save()
    }

    /// The lock ran its course, so the detection stood.
    func recordConfirmedDetection() {
        guard !recentDetections.isEmpty else { return }
        if recentDetections[0].wasFalsePositive == nil {
            recentDetections[0].wasFalsePositive = false
        }
        profile.confirmedCount += 1
        // Decay a previously raised threshold back towards the user's setting.
        if profile.thresholdOffset > 0, profile.confirmedCount.isMultiple(of: 3) {
            profile.thresholdOffset -= 1
        }
        save()
    }

    /// Passive calibration during ordinary use. A user who genuinely overlaps
    /// three keys all day needs a higher bar than one who never does.
    ///
    /// This runs on every keystroke, so it accumulates into plain counters and
    /// only touches the published profile once a batch completes. Publishing
    /// per keystroke would redraw the whole UI as fast as the user can type.
    func observe(_ features: DetectionFeatures) {
        guard features.simultaneousCount >= 1 else { return }
        pendingOverlapSamples += 1
        if features.simultaneousCount >= 3 { pendingHeavyOverlaps += 1 }
        pendingPeakKeyRate = max(pendingPeakKeyRate, features.keyRate)
        guard pendingOverlapSamples >= Self.calibrationBatchSize else { return }

        profile.overlapSampleCount = pendingOverlapSamples
        profile.heavyOverlapCount = pendingHeavyOverlaps
        profile.observedPeakKeyRate = max(profile.observedPeakKeyRate, pendingPeakKeyRate)
        if profile.overlapRate > 0.12, profile.thresholdOffset < CalibrationProfile.maximumOffset {
            profile.thresholdOffset += 1
        }
        profile.overlapSampleCount = 0
        profile.heavyOverlapCount = 0
        pendingOverlapSamples = 0
        pendingHeavyOverlaps = 0
        save()
    }

    func resetLearning() {
        profile = CalibrationProfile()
        recentDetections = []
        pendingOverlapSamples = 0
        pendingHeavyOverlaps = 0
        pendingPeakKeyRate = 0
        save()
        saveHistory()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: profileKey)
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(recentDetections) else { return }
        defaults.set(data, forKey: historyKey)
    }
}
