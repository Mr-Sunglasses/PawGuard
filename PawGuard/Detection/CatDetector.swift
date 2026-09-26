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
    case sustainedHold
    case sequentialLocality
    case repeatedImpact
    /// Two neighbouring keys held together: the smallest contact a paw makes.
    case pawContact
    /// Several separate settled touches in a row: a cat crossing the keyboard.
    case pawTouches
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
            // An autorepeat for a key the detector is not tracking is proof the
            // key is down: its original press was withheld during a lock, fell
            // in the cooldown that resets the detector, or came before
            // monitoring started. Adopting it is what lets a paw that stays
            // parked through all of that be caught again, rather than
            // streaming repeats into the app forever.
            if !KeyboardGeometry.isModifier(sample.keyCode) {
                heldKeys[sample.keyCode] = heldKeys[sample.keyCode] ?? sample.timestamp
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
            at: timestamp,
            exemptKeySets: allowedKeySets
        )
        return score(features)
    }

    /// Converts features into a 0-100 score.
    ///
    /// Evidence combines as a noisy-OR rather than a clamped sum: each signal
    /// contributes an independent probability that this is a paw, and the
    /// score is the probability that at least one of them is right. Summing
    /// and clamping meant a modest four-key impact already pinned the scale at
    /// 100, which collapsed every grade of evidence into one value and made
    /// `immediateScore` — meant for evidence beyond anything a human produces
    /// — the ordinary case. Under noisy-OR each additional signal has
    /// diminishing returns, the score stays inside 0-100 by construction, and
    /// reaching 95 genuinely requires most signals to fire at once.
    func score(_ features: DetectionFeatures) -> DetectionResult {
        var signals = Set<DetectionSignal>()

        /// Probability that no signal so far indicates a paw. Each term
        /// multiplies in its own complement.
        var innocent = 1.0

        /// Adds one signal's evidence, expressed as a 0-100 weight scaled by
        /// how strongly the feature fired.
        func add(_ weight: Double, _ strength: Double) -> Double {
            let probability = max(0, min(0.99, weight / 100 * strength))
            innocent *= 1 - probability
            return probability
        }

        // Contact credibility. A paw sits; fingers pass through. The same
        // overlap between the same keys is rollover when it lasts forty
        // milliseconds and a contact when it lasts a second, so every overlap
        // and clustering term below is scaled by how credible the contact is
        // rather than counted flat.
        //
        // A contact earns its weight three ways and the strongest wins, because
        // each covers a shape the other two are blind to.

        /// How long an overlap has lasted. The floor is well above zero because
        /// a paw landing flat has to be catchable before it has settled — but
        /// low enough that a heavy-handed typist's rollover no longer scores
        /// like a paw.
        func settled(_ duration: TimeInterval) -> Double {
            DetectionRules.unsettledContactWeight
                + (1 - DetectionRules.unsettledContactWeight)
                * detectionRamp(
                    duration,
                    from: DetectionRules.contactSettleStart,
                    to: DetectionRules.contactSettleEnd
                )
        }

        let simultaneous = Double(features.simultaneousCount)

        // How closely the keys arrived. Duration is blind at the instant a paw
        // lands flat, because nothing has had time to last yet — and that is
        // the moment the detector most wants to act. A paw puts its keys down
        // inside a few dozen milliseconds, while a typist who happens to have
        // four keys down took a quarter of a second to get there and is already
        // lifting the first.
        let arrivedTogether =
            detectionRamp(simultaneous, from: 1, to: 3)
            * (1
                - detectionRamp(
                    features.contactArrivalSpread,
                    from: DetectionRules.arrivalSpreadRampStart,
                    to: DetectionRules.arrivalSpreadRampEnd
                ))

        // Keys that individually outlasted a keystroke, for the contact that
        // neither arrived together nor has fully overlapped yet: a cat stepping
        // onto the keys one at a time and leaving each one down. Two keys past
        // a quarter of a second is not something typing produces, because
        // reaching the second means the first is already on its way back up.
        let settledKeys = detectionRamp(
            Double(features.settledKeyCount),
            from: DetectionRules.settledKeyRampStart,
            to: DetectionRules.settledKeyRampEnd
        )

        // Shape signals are read against how long two keys have overlapped.
        let persistence = max(settled(features.pairHoldDuration), arrivedTogether, settledKeys)
        // Count signals are read against how long *every* held key has been
        // down together, which is the sharper test: a typist reaches five keys
        // at once only in passing, with the fifth landing as the first leaves,
        // so the deepest overlap stays near zero however high the count goes.
        let fullPersistence = max(settled(features.fullHoldDuration), arrivedTogether, settledKeys)

        if add(weights.overlap, detectionRamp(simultaneous, from: 1, to: 5) * fullPersistence) > 0 {
            if features.simultaneousCount >= 3 { signals.insert(.simultaneousKeys) }
        }
        _ = add(weights.extremeOverlap, detectionRamp(simultaneous, from: 5, to: 7) * fullPersistence)

        let clusterStrength =
            features.clusterCompactness
            * detectionRamp(Double(features.largestClusterSize), from: 1, to: 4)
            * persistence
        if add(weights.cluster, clusterStrength) > 0 {
            signals.insert(.physicalCluster)
        }

        if add(weights.rapidCluster, detectionRamp(Double(features.rapidClusterCount), from: 2, to: 5) * persistence)
            > 0
        {
            signals.insert(.rapidCluster)
            signals.insert(.physicalCluster)
        }

        // Synchrony is the one shape signal with no persistence gate. Three keys
        // inside thirty milliseconds is arithmetically out of a typist's reach —
        // the fastest human digraph is twice that — so it can carry the fast
        // path for a paw slamming down flat, before the contact has settled.
        if add(weights.synchrony, detectionRamp(Double(features.synchronyCount), from: 1.8, to: 4.5)) > 0 {
            signals.insert(.impactSynchrony)
        }

        // A second compact impact inside the same window is worth more than the
        // first: one is an accident of rollover, a run of them is a paw walking.
        if add(weights.repeatedImpact, detectionRamp(Double(features.impactCount), from: 1, to: 3)) > 0 {
            signals.insert(.repeatedImpact)
            signals.insert(.physicalCluster)
        }

        // Two neighbouring keys held down together. A kitten's pad covers two
        // keys and no more, which every three-key clustering test above is
        // blind to; duration is what makes it safe, because adjacent-key
        // rollover between fingers is over in a fraction of the time.
        if !features.intentionalHold, !matchesAllowedKeySet(features.heldKeys) {
            //
            // Scaled away as the contact grows: once three or four keys are
            // under it, the cluster signals already describe the same physical
            // paw, and counting it twice would push ordinary impacts past
            // `immediateScore` and rob them of their confirmation window.
            let smallContact = 1 - detectionRamp(Double(features.largestClusterSize), from: 2, to: 4)
            let pairStrength =
                smallContact
                * detectionRamp(
                    features.pawContactDuration,
                    from: DetectionRules.pairContactRampStart,
                    to: DetectionRules.pairContactRampEnd
                )
            if add(weights.pairContact, pairStrength) > 0 {
                signals.insert(.pawContact)
                signals.insert(.physicalCluster)
            }
        }

        // Several separate settled touches inside a few seconds: paw down,
        // paw up, paw down again a few keys over.
        if add(
            weights.pawTouches,
            detectionRamp(
                Double(features.pawTouchCount),
                from: DetectionRules.pawTouchRampStart,
                to: DetectionRules.pawTouchRampEnd
            )
        ) > 0 {
            signals.insert(.pawTouches)
        }

        // Three keys down together, and then staying that way. Replaces
        // counting keys past fixed hold thresholds, which needed three quarters
        // of a second before it could see anything at all.
        let holdStrength =
            0.55
            * detectionRamp(
                features.tripleHoldDuration,
                from: DetectionRules.multiHoldRampStart,
                to: DetectionRules.multiHoldRampMid
            )
            + 0.45
            * detectionRamp(
                features.tripleHoldDuration,
                from: DetectionRules.multiHoldRampMid,
                to: DetectionRules.multiHoldRampEnd
            )
        if add(weights.multiKeyHold, holdStrength) > 0 {
            signals.insert(.multiKeyHold)
        }

        // A single key held far longer than a keystroke, on a key nobody leans
        // on. Catches a paw or a flank resting on one letter, which produces no
        // overlap at all and so fires none of the signals above.
        if !features.intentionalHold, !matchesAllowedKeySet(features.heldKeys) {
            if add(weights.sustainedHold, restingContactStrength(features)) > 0 {
                signals.insert(.sustainedHold)
            }
        }

        // Two compact groups far apart is a cat lying across the keyboard, a
        // shape a single-cluster test cannot see.
        if features.separateClusterCount >= 2 && features.simultaneousCount >= 4 {
            _ = add(weights.multiCluster, fullPersistence)
            signals.insert(.multiCluster)
            signals.insert(.physicalCluster)
        }

        if features.improbableCombination {
            _ = add(weights.improbableCombination, 1)
            signals.insert(.improbableCombination)
        }

        if add(weights.burst, detectionRamp(Double(features.burstCount), from: 6, to: 14)) > 0 {
            signals.insert(.fastBurst)
        }

        // Speed and rhythm only count as evidence alongside real overlap.
        // Sequential speed alone is how fast humans type.
        let overlapGate = detectionRamp(simultaneous, from: 1, to: 3) * fullPersistence
        let rateStrength =
            detectionRamp(
                features.keyRate,
                from: DetectionRules.humanKeyRateFloor,
                to: DetectionRules.humanKeyRateCeiling
            ) * overlapGate
        if add(weights.keyRate, rateStrength) > 0 {
            signals.insert(.nonHumanRate)
        }

        if features.medianInterval.isFinite {
            _ = add(weights.rhythm, (1 - detectionRamp(features.medianInterval, from: 0.02, to: 0.07)) * overlapGate)
        }

        // Several different keys nobody leans on, each autorepeating, inside a
        // few seconds. Stretching a letter for effect stretches one letter; a
        // cat shuffling about produces run after run.
        let floodStrength = detectionRamp(Double(features.repeatingKeyCount), from: 1, to: 3)
        if add(weights.repeatFlood, floodStrength) > 0 {
            signals.insert(.excessiveRepeat)
        }

        // Presses that stay under one paw while human typing would have moved
        // on. Deliberately weak on its own: humans do type short local runs
        // ("sad", "were"), so this raises suspicion rather than deciding.
        let localityStrength = sequentialLocalityStrength(features)
        if add(weights.sequentialLocality, localityStrength) > 0 {
            signals.insert(.sequentialLocality)
        }

        var evidence = 1 - innocent

        // Human-pattern damping.
        //
        // Sequential presses with no overlap are the signature of typing, but
        // only when they wander: a cat crossing the keyboard one key at a time
        // is also sequential. Damping therefore eases from the full
        // `sequentialDamping` towards `localSequentialDamping` as the presses
        // stay under one paw, instead of forgiving every sequential stream.
        //
        // A key that has simply been sitting down is not sequential at all, so
        // a resting paw must not be forgiven as typing.
        //
        // A recent settled touch counts the same way: a cat that has just put a
        // paw down and lifted it again is producing single presses, but they are
        // not typing.
        let looksSequential =
            features.simultaneousCount <= 1
            && features.largestClusterSize < 3
            && features.pawTouchCount == 0
            && features.sustainedHoldDuration < DetectionRules.sustainedHoldRampStart
        if looksSequential {
            let damping =
                weights.sequentialDamping
                + (weights.localSequentialDamping - weights.sequentialDamping) * localityStrength
            evidence *= damping
        }
        if features.intentionalHold || matchesAllowedKeySet(features.heldKeys) {
            evidence *= weights.intentionalHoldDamping
        }
        let looksLikeShortcut =
            features.simultaneousCount <= 2
            || (features.clusterCompactness < 0.4 && features.rapidClusterCount < 3)
        if features.hasShortcutModifier && looksLikeShortcut {
            evidence *= weights.shortcutDamping
        }
        if features.handAlternationRate >= 0.5 && features.simultaneousCount <= 2 {
            evidence *= weights.alternationDamping
        }

        var finalScore = Int(max(0, min(100, evidence * 100)).rounded())

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

    /// How strongly the longest-held key nobody leans on looks like a paw
    /// parked on it.
    ///
    /// Measured two ways, and the stronger wins. Duration is the physical
    /// truth and is what carries the signal for a user who has key repeat
    /// switched off. The repeat count is what matters in practice: it is the
    /// damage the user is watching happen, one character at a time, and it
    /// arrives seconds before duration alone becomes conclusive.
    ///
    /// The two are not independent evidence — with repeat on, one is roughly
    /// the other divided by the repeat interval — so they are combined with
    /// `max` rather than as two noisy-OR terms, which would double-count the
    /// same held key and drag the score up by simply looking at it twice.
    private func restingContactStrength(_ features: DetectionFeatures) -> Double {
        let byDuration = detectionRamp(
            features.sustainedHoldDuration,
            from: DetectionRules.sustainedHoldRampStart,
            to: DetectionRules.sustainedHoldRampEnd
        )
        let byRepeats = detectionRamp(
            Double(features.sustainedRepeatRun),
            from: DetectionRules.repeatRunRampStart,
            to: DetectionRules.repeatRunRampEnd
        )
        return max(byDuration, byRepeats)
    }

    /// Locality only counts once there are enough consecutive presses for it to
    /// mean something, and ramps in above the rate ordinary typing reaches.
    private func sequentialLocalityStrength(_ features: DetectionFeatures) -> Double {
        guard features.localityPairCount >= DetectionRules.minimumLocalityPairs else { return 0 }
        return detectionRamp(features.sequentialLocality, from: DetectionRules.localityRampStart, to: DetectionRules.localityRampEnd)
    }

    private func matchesAllowedKeySet(_ keys: Set<CGKeyCode>) -> Bool {
        guard !keys.isEmpty else { return false }
        return allowedKeySets.contains { keys == $0 || keys.isSubset(of: $0) }
    }
}
