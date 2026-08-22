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
    /// How many separate compact impacts landed inside the rolling window. One
    /// is a paw touching down; several in a row is a cat walking. Fingers
    /// produce a compact simultaneous strike only by accident, and never
    /// repeatedly.
    var impactCount: Int = 0

    var burstCount: Int = 0
    /// Sustained unique keys per second over the general window.
    var keyRate: Double = 0
    /// Median gap between successive key-downs. Human digraphs bottom out
    /// around 50 ms; a paw impact is far below that.
    var medianInterval: TimeInterval = .infinity
    /// Fraction of successive key-downs that switch hands. Fast human typing
    /// alternates; a paw does not.
    var handAlternationRate: Double = 0

    /// Fraction of successive key-downs that land within a paw's reach of each
    /// other. Human typing wanders across the keyboard between keystrokes; a paw
    /// walking or padding stays in one small area. Only meaningful once
    /// `localityPairCount` is large enough to be more than chance.
    var sequentialLocality: Double = 0
    var localityPairCount: Int = 0

    /// How long at least two, and at least three, keys have been down together
    /// right now. This is the measure that separates a paw from rollover: the
    /// same three keys mean one thing when they overlap for forty milliseconds
    /// and another when they overlap for a second.
    var pairHoldDuration: TimeInterval = 0
    var tripleHoldDuration: TimeInterval = 0
    /// How long *every* currently held key has been down together — the
    /// shortest of the current holds. A typist reaches five keys down at once
    /// only in passing, with the fifth just landed as the first is leaving, so
    /// this stays near zero however many keys the count reaches. Under a paw
    /// all five landed together and this grows with the contact.
    var fullHoldDuration: TimeInterval = 0
    var maxHoldDuration: TimeInterval = 0
    /// How long the currently held keys took to arrive: the gap between the
    /// first of them landing and the last.
    ///
    /// This is the one measure of contact credibility available at the instant
    /// a paw lands flat, when nothing has had time to persist yet. A paw puts
    /// its keys down inside a few dozen milliseconds; a typist reaching four
    /// keys down at once took a quarter of a second to get there, and is about
    /// to start lifting them.
    var contactArrivalSpread: TimeInterval = 0
    /// How many held keys have been down longer than any keystroke lasts.
    ///
    /// Covers the contact that neither arrival spread nor full-overlap
    /// duration can see: a cat stepping onto the keys one at a time and simply
    /// leaving them there. The keys arrive at typing speed, and the newest has
    /// only just landed, but three of them have been down for a quarter of a
    /// second — and a typist never leaves three keys down that long.
    var settledKeyCount: Int = 0

    /// Longest time two keys close enough to sit under one paw pad have been
    /// down together, anywhere in the contact window — including a contact that
    /// has already lifted. A kitten's pad covers two keys and no more, so this
    /// is the smallest real contact there is.
    var pawContactDuration: TimeInterval = 0
    /// Separate settled contacts inside the contact window. A cat crossing the
    /// keyboard sets a paw down, lifts it, and sets it down again a few keys
    /// over; each touch is weak and the run of them is not.
    var pawTouchCount: Int = 0

    /// Longest hold on a key a human does not lean on. Holding delete, an
    /// arrow, or a movement key for seconds is ordinary; holding a letter key
    /// that long is not something fingers do.
    var sustainedHoldDuration: TimeInterval = 0
    /// Most autorepeats one such key has fired during a single hold. This is
    /// the damage the user actually sees: every repeat is one more character to
    /// delete afterwards.
    var sustainedRepeatRun: Int = 0
    /// How many different keys nobody leans on have fired a run of autorepeats
    /// inside the contact window. A person stretching a letter stretches one
    /// letter; a cat shuffling produces run after run.
    var repeatingKeyCount: Int = 0

    var improbableCombination: Bool = false
    var intentionalHold: Bool = false
    var hasShortcutModifier: Bool = false

    /// - Parameter exemptKeySets: chords the user holds on purpose — the
    ///   gaming and arrow clusters, plus anything they have taught PawGuard to
    ///   ignore. Contacts inside one of these are not paw touches, and the test
    ///   has to happen here rather than in the score: the contact features look
    ///   back over several seconds, so a chord that has already been released
    ///   would otherwise sail past an exemption that only ever inspects the
    ///   keys held right now.
    static func extract(
        heldKeys: [CGKeyCode: TimeInterval],
        samples: [KeyboardEventSample],
        modifiers: CGEventFlags,
        at timestamp: TimeInterval,
        exemptKeySets: [Set<CGKeyCode>] = []
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
        features.impactCount = impactCount(in: keyDowns)
        features.medianInterval = medianInterval(in: keyDowns)
        features.handAlternationRate = handAlternationRate(in: keyDowns)
        let locality = sequentialLocality(in: keyDowns)
        features.sequentialLocality = locality.rate
        features.localityPairCount = locality.pairs

        // How long two and three keys have been down together, read straight
        // off the sorted hold durations: the second-longest hold is how long at
        // least two keys have overlapped, the third-longest how long three have.
        let durations = heldKeys.values.map { timestamp - $0 }.sorted(by: >)
        features.maxHoldDuration = durations.first ?? 0
        features.pairHoldDuration = durations.count >= 2 ? durations[1] : 0
        features.tripleHoldDuration = durations.count >= 3 ? durations[2] : 0
        features.fullHoldDuration = durations.count >= 2 ? (durations.last ?? 0) : 0
        features.contactArrivalSpread =
            durations.count >= 2 ? features.maxHoldDuration - features.fullHoldDuration : 0
        features.settledKeyCount = durations.filter { $0 >= DetectionRules.contactSettleEnd }.count

        features.sustainedHoldDuration =
            heldKeys
            .filter { !KeyboardGeometry.isCommonlyHeld($0.key) }
            .values
            .map { timestamp - $0 }
            .max() ?? 0

        let holds = holdIntervals(heldKeys: heldKeys, samples: samples, at: timestamp)
        let isExempt = { (keys: Set<CGKeyCode>) -> Bool in
            KeyboardGeometry.isLikelyIntentionalHold(keys)
                || exemptKeySets.contains { keys.isSubset(of: $0) }
        }
        let contacts = contactSummary(of: holds, isExempt: isExempt)
        features.pawContactDuration = contacts.longestPairOverlap
        features.pawTouchCount = contacts.touchCount

        let repeats = repeatSummary(of: holds, samples: samples, at: timestamp, isExempt: isExempt)
        features.sustainedRepeatRun = repeats.longestRun
        features.repeatingKeyCount = repeats.repeatingKeys

        features.improbableCombination = KeyboardGeometry.isImprobableCombination(held)
        features.intentionalHold = KeyboardGeometry.isLikelyIntentionalHold(held)
        let shortcutModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate]
        features.hasShortcutModifier = !modifiers.intersection(shortcutModifiers).isEmpty

        return features
    }

    // MARK: - Contacts

    /// One stretch of time a key spent physically down, inside the contact
    /// window. A key pressed, released, and pressed again produces two.
    struct HoldInterval {
        let key: CGKeyCode
        let start: TimeInterval
        let end: TimeInterval

        var duration: TimeInterval { end - start }

        func overlap(with other: HoldInterval) -> TimeInterval {
            max(0, min(end, other.end) - max(start, other.start))
        }
    }

    /// Reconstructs how long each key was down over the contact window.
    ///
    /// The instantaneous held-key set only says what is down now, which cannot
    /// see a paw that touched down, lifted, and came down again a few keys over
    /// — the shape a cat crossing the keyboard actually makes. Holds still open
    /// are closed at `timestamp`, and a key already down when the window opened
    /// is clipped to the window rather than dropped.
    static func holdIntervals(
        heldKeys: [CGKeyCode: TimeInterval],
        samples: [KeyboardEventSample],
        at timestamp: TimeInterval
    ) -> [HoldInterval] {
        let windowStart = timestamp - DetectionRules.contactWindow
        var intervals: [HoldInterval] = []
        var open: [CGKeyCode: TimeInterval] = [:]

        for sample in samples.sorted(by: { $0.timestamp < $1.timestamp }) {
            guard !KeyboardGeometry.isModifier(sample.keyCode) else { continue }
            guard sample.timestamp <= timestamp else { continue }
            switch sample.type {
            case .keyDown:
                guard !sample.isRepeat, open[sample.keyCode] == nil else { continue }
                open[sample.keyCode] = max(sample.timestamp, windowStart)
            case .keyUp:
                guard let start = open.removeValue(forKey: sample.keyCode) else { continue }
                let end = max(start, min(sample.timestamp, timestamp))
                if end > windowStart { intervals.append(HoldInterval(key: sample.keyCode, start: start, end: end)) }
            case .flagsChanged:
                continue
            }
        }

        // Whatever is still down closes at now. A key held since before the
        // window opened has no key-down in the buffer, so its start comes from
        // the held-key set instead.
        for (key, start) in heldKeys {
            let effectiveStart = max(open[key] ?? start, windowStart)
            open.removeValue(forKey: key)
            guard timestamp > effectiveStart else { continue }
            intervals.append(HoldInterval(key: key, start: effectiveStart, end: timestamp))
        }
        for (key, start) in open where timestamp > start {
            intervals.append(HoldInterval(key: key, start: start, end: timestamp))
        }
        return intervals
    }

    /// Finds settled paw contacts: two neighbouring keys down together for
    /// longer than rollover lasts, or one key nobody leans on held past any
    /// keystroke. Contacts overlapping in time are one touch, so a three-key
    /// patch counts once and three touches in a row count three times.
    private static func contactSummary(
        of holds: [HoldInterval],
        isExempt: (Set<CGKeyCode>) -> Bool
    ) -> (longestPairOverlap: TimeInterval, touchCount: Int) {
        var longest: TimeInterval = 0
        /// A contact's time on the keyboard and roughly where it sat.
        var spans: [(start: TimeInterval, end: TimeInterval, at: KeyPoint, isPair: Bool)] = []

        for index in holds.indices {
            for other in holds.index(after: index)..<holds.endIndex {
                let a = holds[index]
                let b = holds[other]
                guard KeyboardGeometry.isPawContact(a.key, b.key) else { continue }
                guard !isExempt([a.key, b.key]) else { continue }
                let overlap = a.overlap(with: b)
                guard overlap > 0 else { continue }
                longest = max(longest, overlap)
                guard overlap >= DetectionRules.minimumContactOverlap,
                    let point = KeyboardGeometry.position(for: a.key)
                else { continue }
                spans.append((max(a.start, b.start), min(a.end, b.end), point, true))
            }
        }

        // A single key nobody leans on, held past anything a keystroke lasts,
        // is a touch too: a kitten crossing the keyboard often puts down one
        // key at a time. On its own that shape is indistinguishable from slow,
        // deliberate typing — a hesitant typist holds each key just as long —
        // so a lone key only counts once another touch lands within a paw's
        // reach of it. A paw pads around one patch of keyboard; the letters a
        // person is looking for are wherever the words take them.
        for hold in holds
        where !KeyboardGeometry.isCommonlyHeld(hold.key) && !isExempt([hold.key])
            && hold.duration >= DetectionRules.singleTouchMinimumHold
        {
            guard let point = KeyboardGeometry.position(for: hold.key) else { continue }
            spans.append((hold.start, hold.end, point, false))
        }

        spans.sort { $0.start < $1.start }
        // A lone key counts only when the touch immediately before or after it
        // in time landed within a paw's reach. Comparing against *any* other
        // touch in the window is far too generous: over four seconds some pair
        // of letters is always going to be neighbours by chance.
        let admitted = spans.indices.filter { index in
            guard !spans[index].isPair else { return true }
            let neighbours = [index - 1, index + 1].filter(spans.indices.contains)
            return neighbours.contains {
                spans[index].at.distance(to: spans[$0].at) <= DetectionRules.pawReachDistance
            }
        }.map { spans[$0] }

        guard let first = admitted.first else { return (longest, 0) }
        var touches = 1
        var currentEnd = first.end
        for span in admitted.dropFirst() {
            if span.start > currentEnd {
                touches += 1
                currentEnd = span.end
            } else {
                currentEnd = max(currentEnd, span.end)
            }
        }
        return (longest, touches)
    }

    /// Counts autorepeats per hold, on keys a human does not lean on.
    ///
    /// Autorepeat is the part of this the user actually sees. A paw parked on a
    /// letter fires one every few dozen milliseconds, and every one of them is
    /// a character to delete afterwards, so the count is both evidence and the
    /// measure of the damage being done.
    private static func repeatSummary(
        of holds: [HoldInterval],
        samples: [KeyboardEventSample],
        at timestamp: TimeInterval,
        isExempt: (Set<CGKeyCode>) -> Bool
    ) -> (longestRun: Int, repeatingKeys: Int) {
        let candidates = holds.filter { !KeyboardGeometry.isCommonlyHeld($0.key) && !isExempt([$0.key]) }
        guard !candidates.isEmpty else { return (0, 0) }

        var runs: [Int] = Array(repeating: 0, count: candidates.count)
        for sample in samples {
            guard sample.type == .keyDown, sample.isRepeat, sample.timestamp <= timestamp else { continue }
            guard
                let index = candidates.firstIndex(where: {
                    $0.key == sample.keyCode && sample.timestamp >= $0.start && sample.timestamp <= $0.end
                })
            else { continue }
            runs[index] += 1
        }

        var repeatingKeys = Set<CGKeyCode>()
        for (index, count) in runs.enumerated() where count >= DetectionRules.minimumRepeatRun {
            repeatingKeys.insert(candidates[index].key)
        }
        return (runs.max() ?? 0, repeatingKeys.count)
    }

    // MARK: - Timing

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

    /// Counts distinct compact impacts: groups of three or more keys landing
    /// together in one tight patch, each counted once.
    ///
    /// A cat crossing the keyboard sets down a paw, lifts it, and sets it down
    /// again a few keys over. Every one of those touches is a weak signal on
    /// its own — three keys held half a second is under every hold threshold —
    /// but a run of them is a shape fingers do not make.
    private static func impactCount(in keyDowns: [KeyboardEventSample]) -> Int {
        guard keyDowns.count >= 3 else { return 0 }
        var count = 0
        var index = keyDowns.startIndex
        while index < keyDowns.endIndex {
            var keys = Set<CGKeyCode>()
            var next = index
            while next < keyDowns.endIndex,
                keyDowns[next].timestamp - keyDowns[index].timestamp <= DetectionRules.synchronyWindow
            {
                keys.insert(keyDowns[next].keyCode)
                next += 1
            }
            if keys.count >= 3, KeyboardGeometry.isTightCluster(keys) {
                count += 1
                // Consume the impact so its own keys cannot seed another.
                index = next
            } else {
                index += 1
            }
        }
        return count
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

    /// How often one key-down lands within a paw's reach of the one before it.
    ///
    /// Measured over consecutive presses rather than held keys, so it sees the
    /// one pattern the overlap signals cannot: a cat crossing the keyboard
    /// pressing keys one at a time, which is otherwise indistinguishable from
    /// slow sequential typing.
    private static func sequentialLocality(in keyDowns: [KeyboardEventSample]) -> (rate: Double, pairs: Int) {
        guard keyDowns.count >= 2 else { return (0, 0) }
        var near = 0
        var pairs = 0
        for index in 1..<keyDowns.count {
            guard let previous = KeyboardGeometry.position(for: keyDowns[index - 1].keyCode),
                let current = KeyboardGeometry.position(for: keyDowns[index].keyCode)
            else { continue }
            // Ignore a key repeating in place: that is autorepeat or a double
            // letter, not evidence about where the next press landed.
            guard keyDowns[index].keyCode != keyDowns[index - 1].keyCode else { continue }
            pairs += 1
            if previous.distance(to: current) <= DetectionRules.pawReachDistance { near += 1 }
        }
        guard pairs > 0 else { return (0, 0) }
        return (Double(near) / Double(pairs), pairs)
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
