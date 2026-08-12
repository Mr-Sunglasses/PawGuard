import CoreGraphics
import Foundation

enum DetectionSignal: String, Hashable, Codable {
    case simultaneousKeys
    case fastBurst
    case physicalCluster
    case rapidCluster
    case multiKeyHold
    case excessiveRepeat
    case impactSynchrony
    case multiCluster
    case improbableCombination
    case nonHumanRate
}

enum DetectionConfidence: String, Codable {
    case none
    case suspicious
    case cat
}

struct DetectionResult {
    let score: Int
    let signals: Set<DetectionSignal>
    let confidence: DetectionConfidence
    let simultaneousKeyCount: Int
    let burstKeyCount: Int
    let rapidClusterKeyCount: Int
    let heldKeyCount: Int
    let hasPhysicalCluster: Bool
    /// True when the evidence is beyond anything a human produces, so
    /// protection engages without waiting for the confirmation window.
    let isImmediate: Bool
    let features: DetectionFeatures

    static let empty = DetectionResult(
        score: 0,
        signals: [],
        confidence: .none,
        simultaneousKeyCount: 0,
        burstKeyCount: 0,
        rapidClusterKeyCount: 0,
        heldKeyCount: 0,
        hasPhysicalCluster: false,
        isImmediate: false,
        features: DetectionFeatures()
    )
}

/// Scores keyboard activity against patterns a paw produces and fingers do not.
///
/// Not thread-safe on its own; `KeyboardEngine` owns the serialization.
final class CatDetector {
    private var eventBuffer = RollingEventBuffer()
    private var heldKeys: [CGKeyCode: TimeInterval] = [:]
    private var latestModifiers: CGEventFlags = []
    private(set) var threshold: Int
    private(set) var weights: DetectionWeights

    /// Key sets the user has repeatedly told us are not a cat.
    var allowedKeySets: [Set<CGKeyCode>] = []

    init(threshold: Int = DetectionRules.defaultThreshold, weights: DetectionWeights = .default) {
        self.threshold = threshold
        self.weights = weights
    }

    func updateThreshold(_ threshold: Int) {
        self.threshold = max(30, min(100, threshold))
    }

    func updateWeights(_ weights: DetectionWeights) {
        self.weights = weights
    }

    func reset() {
        eventBuffer.removeAll()
        heldKeys.removeAll(keepingCapacity: true)
        latestModifiers = []
    }

    var currentHeldKeys: Set<CGKeyCode> { Set(heldKeys.keys) }

    func process(_ sample: KeyboardEventSample) -> DetectionResult {
        latestModifiers = sample.modifiers
        switch sample.type {
        case .keyDown:
            if !KeyboardGeometry.isModifier(sample.keyCode) {
                if !sample.isRepeat {
                    heldKeys[sample.keyCode] = heldKeys[sample.keyCode] ?? sample.timestamp
                }
            }
        case .keyUp:
            heldKeys.removeValue(forKey: sample.keyCode)
        case .flagsChanged:
            break
        }

        eventBuffer.append(sample)
        return currentResult(at: sample.timestamp)
    }

    /// Re-evaluates held keys even when a paw is resting still and macOS has
    /// not emitted an autorepeat event. The timestamp uses system uptime, the
    /// same monotonic clock `KeyboardEventMonitor` converts event stamps into.
    func evaluate(at timestamp: TimeInterval) -> DetectionResult {
        eventBuffer.trim(through: timestamp)
        dropStaleHolds(at: timestamp)
        return currentResult(at: timestamp)
    }

    /// Replaces the inferred held-key set with the hardware's own view.
    ///
    /// `CGEventSource.keyState` reports what is physically down, which fixes
    /// key-ups lost to a disabled tap and catches a paw that was already
    /// resting on the keyboard before monitoring started.
    func reconcileHeldKeys(with physicalKeys: Set<CGKeyCode>, at timestamp: TimeInterval) {
        for key in heldKeys.keys where !physicalKeys.contains(key) {
            heldKeys.removeValue(forKey: key)
        }
        for key in physicalKeys where !KeyboardGeometry.isModifier(key) {
            if heldKeys[key] == nil {
                heldKeys[key] = timestamp
            }
        }
    }

    /// Drops keys whose key-up never arrived. Without this a lost event pins a
    /// key down forever and every later evaluation sees a phantom long hold.
    private func dropStaleHolds(at timestamp: TimeInterval) {
        for (key, start) in heldKeys where timestamp - start > DetectionRules.staleHoldTimeout {
            heldKeys.removeValue(forKey: key)
        }
    }

    private func currentResult(at timestamp: TimeInterval) -> DetectionResult {
        let features = DetectionFeatures.extract(
            heldKeys: heldKeys,
            samples: eventBuffer.samples,
            modifiers: latestModifiers,
            at: timestamp
        )
        return score(features)
    }

    /// Converts features into a 0-100 score. Every term is a smooth ramp, so a
    /// single extra key shifts the score by a few points rather than tens.
    func score(_ features: DetectionFeatures) -> DetectionResult {
        var score = 0.0
        var signals = Set<DetectionSignal>()

        let simultaneous = Double(features.simultaneousCount)
        let overlap = weights.overlap * detectionRamp(simultaneous, from: 1, to: 5)
        if overlap > 0 {
            score += overlap
            if features.simultaneousCount >= 3 { signals.insert(.simultaneousKeys) }
        }
        score += weights.extremeOverlap * detectionRamp(simultaneous, from: 5, to: 7)

        let clusterScore =
            weights.cluster * features.clusterCompactness
            * detectionRamp(Double(features.largestClusterSize), from: 2, to: 5)
        if clusterScore > 0 {
            score += clusterScore
            signals.insert(.physicalCluster)
        }

        let rapidCluster = weights.rapidCluster * detectionRamp(Double(features.rapidClusterCount), from: 2, to: 5)
        if rapidCluster > 0 {
            score += rapidCluster
            signals.insert(.rapidCluster)
            signals.insert(.physicalCluster)
        }

        let synchrony = weights.synchrony * detectionRamp(Double(features.synchronyCount), from: 2, to: 5)
        if synchrony > 0 {
            score += synchrony
            signals.insert(.impactSynchrony)
        }

        let holdScore =
            weights.multiKeyHold
            * (0.55 * detectionRamp(Double(features.longHeldCount), from: 1, to: 3)
                + 0.45 * detectionRamp(Double(features.extendedHeldCount), from: 1, to: 3))
        if holdScore > 0 {
            score += holdScore
            signals.insert(.multiKeyHold)
        }

        // Two compact groups far apart is a cat lying across the keyboard, a
        // shape a single-cluster test cannot see.
        if features.separateClusterCount >= 2 && features.simultaneousCount >= 4 {
            score += weights.multiCluster
            signals.insert(.multiCluster)
            signals.insert(.physicalCluster)
        }

        if features.improbableCombination {
            score += weights.improbableCombination
            signals.insert(.improbableCombination)
        }

        let burst = weights.burst * detectionRamp(Double(features.burstCount), from: 6, to: 14)
        if burst > 0 {
            score += burst
            signals.insert(.fastBurst)
        }

        // Speed and rhythm only count as evidence alongside real overlap.
        // Sequential speed alone is how fast humans type.
        let overlapGate = detectionRamp(simultaneous, from: 1, to: 3)
        let rate =
            weights.keyRate
            * detectionRamp(
                features.keyRate,
                from: DetectionRules.humanKeyRateFloor,
                to: DetectionRules.humanKeyRateCeiling
            ) * overlapGate
        if rate > 0 {
            score += rate
            signals.insert(.nonHumanRate)
        }

        if features.medianInterval.isFinite {
            score += weights.rhythm * (1 - detectionRamp(features.medianInterval, from: 0.02, to: 0.07)) * overlapGate
        }

        if features.repeatCount >= 3 && features.simultaneousCount >= 2 {
            score += weights.excessiveRepeat
            signals.insert(.excessiveRepeat)
        }

        // Human-pattern damping.
        let looksSequential = features.simultaneousCount <= 1 && features.largestClusterSize < 3
        if looksSequential {
            score *= weights.sequentialDamping
        }
        if features.intentionalHold || matchesAllowedKeySet(features.heldKeys) {
            score *= weights.intentionalHoldDamping
        }
        let looksLikeShortcut =
            features.simultaneousCount <= 2
            || (features.clusterCompactness < 0.4 && features.rapidClusterCount < 3)
        if features.hasShortcutModifier && looksLikeShortcut {
            score *= weights.shortcutDamping
        }
        if features.handAlternationRate >= 0.5 && features.simultaneousCount <= 2 {
            score *= weights.alternationDamping
        }

        var finalScore = Int(max(0, min(100, score)).rounded())

        // A known human control cluster stays non-triggering even when key
        // repeat makes it look like a long hold. Unrelated keys in the rolling
        // burst remove this exemption.
        if (features.intentionalHold || matchesAllowedKeySet(features.heldKeys)) && features.burstCount <= 4 {
            finalScore = min(finalScore, max(0, threshold - 1))
        }

        let isImmediate = finalScore >= DetectionRules.immediateScore
        let confidence: DetectionConfidence
        if finalScore >= threshold {
            confidence = .cat
        } else if finalScore >= max(25, threshold / 2) {
            confidence = .suspicious
        } else {
            confidence = .none
        }

        return DetectionResult(
            score: finalScore,
            signals: signals,
            confidence: confidence,
            simultaneousKeyCount: features.simultaneousCount,
            burstKeyCount: features.burstCount,
            rapidClusterKeyCount: features.rapidClusterCount,
            heldKeyCount: features.simultaneousCount,
            hasPhysicalCluster: signals.contains(.physicalCluster),
            isImmediate: isImmediate,
            features: features
        )
    }

    private func matchesAllowedKeySet(_ keys: Set<CGKeyCode>) -> Bool {
        guard !keys.isEmpty else { return false }
        return allowedKeySets.contains { keys == $0 || keys.isSubset(of: $0) }
    }
}
