import CoreGraphics
import XCTest

@testable import PawGuard

/// Replays whole event streams through the detector and scores the outcome, so
/// tuning is measured rather than argued about.
///
/// Traces live in `Tests/Fixtures` as JSON lines. Generated ones cover the
/// space broadly; recorded ones can be dropped in beside them and are picked up
/// automatically.
final class TraceReplayTests: XCTestCase {
    struct ReplayOutcome {
        var detected = false
        var detectionTime: TimeInterval?
        var peakScore = 0
    }

    private static var fixturesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
    }

    /// Feeds a trace through the detector exactly as the engine would, including
    /// the quarter-second timer evaluations that catch a still paw.
    private func replay(_ samples: [KeyboardEventSample], threshold: Int = DetectionRules.defaultThreshold)
        -> ReplayOutcome
    {
        let detector = CatDetector(threshold: threshold)
        var outcome = ReplayOutcome()
        let tick = DetectionRules.monitorTick
        var nextTick = (samples.first?.timestamp ?? 0) + tick

        func record(_ result: DetectionResult, at time: TimeInterval) {
            outcome.peakScore = max(outcome.peakScore, result.score)
            if result.confidence == .cat, !outcome.detected {
                outcome.detected = true
                outcome.detectionTime = time
            }
        }

        for sample in samples {
            while nextTick < sample.timestamp {
                record(detector.evaluate(at: nextTick), at: nextTick)
                nextTick += tick
            }
            record(detector.process(sample), at: sample.timestamp)
        }
        // Keep evaluating for a moment after the last event, the way the app's
        // timer does when a paw settles and stops producing events.
        let end = (samples.last?.timestamp ?? 0) + 2
        while nextTick <= end {
            record(detector.evaluate(at: nextTick), at: nextTick)
            nextTick += tick
        }
        return outcome
    }

    private func loadFixtures() throws -> [KeyboardTrace] {
        let directory = Self.fixturesDirectory
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        return try files.map { url in
            let name = url.deletingPathExtension().lastPathComponent
            let label: KeyboardTrace.Label = name.hasPrefix("cat-") ? .cat : .human
            let contents = try String(contentsOf: url, encoding: .utf8)
            return try KeyboardTrace.parse(jsonLines: contents, name: name, label: label)
        }
    }

    func testFixtureTracesAreClassifiedCorrectly() throws {
        let traces = try loadFixtures()
        try XCTSkipIf(traces.isEmpty, "No trace fixtures found in \(Self.fixturesDirectory.path)")

        var falsePositives: [String] = []
        var missedCats: [String] = []

        for trace in traces {
            let outcome = replay(trace.samples)
            switch trace.label {
            case .human where outcome.detected:
                falsePositives.append("\(trace.name) (peak \(outcome.peakScore))")
            case .cat where !outcome.detected:
                missedCats.append("\(trace.name) (peak \(outcome.peakScore))")
            default:
                continue
            }
        }

        XCTAssertTrue(falsePositives.isEmpty, "Human traces triggered protection: \(falsePositives)")
        XCTAssertTrue(missedCats.isEmpty, "Cat traces were missed: \(missedCats)")
    }

    // MARK: - Generated corpora

    func testGeneratedHumanTypingNeverTriggersProtection() {
        var falsePositives: [String] = []
        var totalKeys = 0

        for speed in stride(from: 30.0, through: 170.0, by: 10.0) {
            for seed in UInt64(1)...UInt64(12) {
                let samples = TraceGenerator.humanTyping(
                    wordsPerMinute: speed,
                    keyCount: 220,
                    seed: seed &* 7919 &+ UInt64(speed)
                )
                totalKeys += samples.count
                let outcome = replay(samples)
                if outcome.detected {
                    falsePositives.append("\(Int(speed)) wpm seed \(seed) peak \(outcome.peakScore)")
                }
            }
        }

        XCTAssertGreaterThan(totalKeys, 40_000, "corpus should be large enough to be meaningful")
        XCTAssertTrue(falsePositives.isEmpty, "\(falsePositives.count) false positives: \(falsePositives.prefix(5))")
    }

    func testGeneratedHumanTypingStaysWellBelowTheThresholdOnAverage() {
        var peaks: [Int] = []
        for seed in UInt64(1)...UInt64(20) {
            let samples = TraceGenerator.humanTyping(wordsPerMinute: 110, keyCount: 200, seed: seed)
            peaks.append(replay(samples).peakScore)
        }
        let average = Double(peaks.reduce(0, +)) / Double(peaks.count)
        // Not merely under the threshold: comfortably under it, so ordinary
        // variation cannot push a typist over.
        XCTAssertLessThan(average, Double(DetectionRules.defaultThreshold) * 0.6, "peaks: \(peaks)")
    }

    func testGeneratedPawImpactsAreAlwaysCaught() {
        var missed: [String] = []
        var checked = 0
        let anchors: [CGKeyCode] = [3, 13, 40, 8, 32, 46, 15, 87, 97]

        for anchor in anchors {
            for keyCount in 3...6 {
                let keys = Set(TraceGenerator.pawKeys(anchor: anchor, count: keyCount))
                // A paw landing squarely on WASD or the arrow cluster is
                // deliberately exempt; that case has its own test below.
                if KeyboardGeometry.isLikelyIntentionalHold(keys) { continue }

                for seed in UInt64(1)...UInt64(4) {
                    let samples = TraceGenerator.pawImpact(
                        anchor: anchor,
                        keyCount: keyCount,
                        seed: seed,
                        startTime: 0
                    )
                    guard samples.count >= keyCount else { continue }
                    checked += 1
                    let outcome = replay(samples)
                    if !outcome.detected {
                        missed.append("anchor \(anchor) keys \(keyCount) seed \(seed) peak \(outcome.peakScore)")
                    }
                }
            }
        }

        XCTAssertGreaterThan(checked, 80, "the sweep should cover a broad range of impacts")
        XCTAssertTrue(missed.isEmpty, "missed \(missed.count) paw impacts: \(missed.prefix(5))")
    }

    /// A paw covering exactly the keys a gamer holds is genuinely ambiguous, and
    /// PawGuard resolves that ambiguity in favour of the human. Widening the
    /// contact patch by one key removes the exemption.
    func testPawLandingExactlyOnAGamingChordIsExemptUntilItSpreads() {
        let gamingSized = Set(TraceGenerator.pawKeys(anchor: 13, count: 4))
        XCTAssertTrue(KeyboardGeometry.isLikelyIntentionalHold(gamingSized))
        XCTAssertFalse(replay(TraceGenerator.pawImpact(anchor: 13, keyCount: 4, seed: 1, startTime: 0)).detected)

        let spread = Set(TraceGenerator.pawKeys(anchor: 13, count: 5))
        XCTAssertFalse(KeyboardGeometry.isLikelyIntentionalHold(spread))
        XCTAssertTrue(replay(TraceGenerator.pawImpact(anchor: 13, keyCount: 5, seed: 1, startTime: 0)).detected)
    }

    func testPawImpactsAreCaughtQuickly() {
        // A four-key compact impact should be caught within a fraction of a
        // second, not after the paw has already typed a paragraph.
        for anchor in [3, 40, 8, 46] as [CGKeyCode] {
            let samples = TraceGenerator.pawImpact(anchor: anchor, keyCount: 4, seed: 3, startTime: 0)
            let outcome = replay(samples)
            XCTAssertTrue(outcome.detected, "anchor \(anchor) was not detected")
            let latency = outcome.detectionTime ?? .infinity
            XCTAssertLessThan(latency, 0.3, "anchor \(anchor) took \(latency)s to detect")
        }
    }

    func testCatSettlingAcrossTheKeyboardIsCaught() {
        for seed in UInt64(1)...UInt64(5) {
            let samples = TraceGenerator.catSitting(seed: seed, startTime: 0)
            let outcome = replay(samples)
            XCTAssertTrue(outcome.detected, "seed \(seed) peak \(outcome.peakScore)")
        }
    }

    func testTypingThenPawIsCaughtWithoutTheTypingHelping() {
        // The realistic sequence: someone is typing, the cat jumps up.
        let typing = TraceGenerator.humanTyping(wordsPerMinute: 95, keyCount: 60, seed: 11)
        let handoff = (typing.last?.timestamp ?? 0) + 0.4
        let paw = TraceGenerator.pawImpact(anchor: 5, keyCount: 5, seed: 2, startTime: handoff)

        let typingOnly = replay(typing)
        XCTAssertFalse(typingOnly.detected, "typing alone should stay silent (peak \(typingOnly.peakScore))")

        let combined = replay(typing + paw)
        XCTAssertTrue(combined.detected)
        XCTAssertGreaterThanOrEqual(combined.detectionTime ?? 0, handoff)
    }

    /// The case that started all this: a kitten stands on one key and it types
    /// itself across the screen. The old model measured only how long the key
    /// had been down, on a ramp that took a dozen seconds to become decisive —
    /// several hundred characters of damage. Counting the autorepeats instead
    /// catches it while the mess is still a line or two.
    func testAKeyLeftDownIsCaughtWhileTheDamageIsStillSmall() {
        for key in [38, 5, 8, 34] as [CGKeyCode] {
            let outcome = replay(TraceGenerator.heldKeyWithAutorepeat(key, duration: 20))
            XCTAssertTrue(outcome.detected, "key \(key): a letter held for twenty seconds is not typing")
            let latency = outcome.detectionTime ?? .infinity
            XCTAssertLessThan(latency, 4, "key \(key) took \(latency)s, long enough to fill a line")
        }
    }

    /// Holding a key to repeat it is a real thing people do, and while they are
    /// doing it, it is genuinely indistinguishable from a resting paw. Two
    /// separate protections cover it, and both are tested here: the punctuation
    /// people rule off lines with never carries resting evidence at all, and a
    /// stretched letter has to outlast any stretch somebody types on purpose.
    func testHoldingAKeyToRepeatItStaysSilent() {
        // "-----", ".....", ",,,,," — held far past anything a cat would need.
        for key in [27, 43, 47, 24, 44] as [CGKeyCode] {
            let outcome = replay(TraceGenerator.heldKeyWithAutorepeat(key, duration: 10))
            XCTAssertFalse(outcome.detected, "key \(key) triggered (peak \(outcome.peakScore))")
        }
        // "noooooo" — a letter stretched about as far as anyone stretches one.
        for duration in [0.6, 0.9, 1.2, 1.5] {
            let outcome = replay(TraceGenerator.heldKeyWithAutorepeat(31, duration: duration))
            XCTAssertFalse(outcome.detected, "\(duration)s stretch triggered (peak \(outcome.peakScore))")
        }
    }

    /// A kitten's pad covers two keys and no more. Every clustering signal used
    /// to need three, so the smallest real contact there is scored 53 at its
    /// peak and was never caught at any sensitivity.
    func testAKittenPawOnTwoAdjacentKeysIsCaught() {
        for anchor in [4, 40, 8, 15, 34, 17] as [CGKeyCode] {
            let samples = TraceGenerator.kittenPaw(anchor: anchor, keyCount: 2, hold: 4)
            let outcome = replay(samples)
            XCTAssertTrue(outcome.detected, "anchor \(anchor) missed (peak \(outcome.peakScore))")
            let latency = outcome.detectionTime ?? .infinity
            XCTAssertLessThan(latency, 1.5, "anchor \(anchor) took \(latency)s")
        }
    }

    func testAKittenCrossingTheKeyboardIsCaught() {
        var missed: [String] = []
        for seed in UInt64(1)...UInt64(12) {
            let outcome = replay(TraceGenerator.kittenWalk(seed: seed))
            if !outcome.detected { missed.append("seed \(seed) peak \(outcome.peakScore)") }
        }
        // Not every wander is catchable — a few touches far enough apart are a
        // shape typing also makes — but the great majority must be.
        XCTAssertLessThanOrEqual(missed.count, 3, "missed \(missed)")
    }

    /// The hardest human pattern to tell from a cat padding across the keys:
    /// one key at a time, each held long enough to autorepeat. Counting those
    /// holds as paw touches on their own turned every one of these into a
    /// lockout, which is why a lone key only counts when the touch beside it in
    /// time landed within a paw's reach.
    func testSlowDeliberateTypingNeverTriggers() {
        guard let sensitive = SensitivityPreset.sensitive.threshold else {
            return XCTFail("sensitive preset must define a threshold")
        }
        for holds in [0.25...0.45, 0.40...0.70] {
            for seed in UInt64(1)...UInt64(15) {
                let samples = TraceGenerator.deliberateTyping(seed: seed, keyCount: 90, holdRange: holds)
                let outcome = replay(samples, threshold: sensitive)
                XCTAssertFalse(
                    outcome.detected,
                    "holds \(holds) seed \(seed) triggered (peak \(outcome.peakScore))"
                )
            }
        }
    }

    func testLongHoldsOnKeysPeopleLeanOnNeverTrigger() {
        // Delete, arrows, space, and a movement key, each held far past any
        // threshold a resting paw would cross.
        for key in [51, 123, 124, 125, 126, 49, 13, 48, 36] as [CGKeyCode] {
            let outcome = replay(TraceGenerator.heldKeyWithAutorepeat(key, duration: 30))
            XCTAssertFalse(outcome.detected, "key \(key) triggered (peak \(outcome.peakScore))")
        }
    }

    /// The score is a graded scale again, not a rail pinned at 100.
    ///
    /// Under the old clamped sum an ordinary four-key impact already summed
    /// past 100, so `immediateScore` — meant for evidence beyond anything a
    /// human produces — was the common case and the confirmation window was
    /// skipped for most detections.
    func testOrdinaryPawImpactsLeaveRoomForTheConfirmationWindow() {
        var immediate = 0
        var total = 0
        for anchor in [3, 13, 40, 8, 32, 46, 15] as [CGKeyCode] {
            for keyCount in 3...5 {
                let keys = Set(TraceGenerator.pawKeys(anchor: anchor, count: keyCount))
                if KeyboardGeometry.isLikelyIntentionalHold(keys) { continue }
                let outcome = replay(TraceGenerator.pawImpact(anchor: anchor, keyCount: keyCount, seed: 1, startTime: 0))
                total += 1
                if outcome.peakScore >= DetectionRules.immediateScore { immediate += 1 }
            }
        }
        XCTAssertGreaterThan(total, 15)
        XCTAssertLessThan(
            Double(immediate) / Double(total),
            0.5,
            "most detections should still go through the confirmation window"
        )
    }

    /// Evidence still has somewhere to go above an ordinary impact: a cat lying
    /// across the keyboard must outscore a single paw touching down.
    func testMoreEvidenceScoresHigherThanLess() {
        let smallImpact = replay(TraceGenerator.pawImpact(anchor: 13, keyCount: 3, seed: 1, startTime: 0)).peakScore
        let wholeCat = replay(TraceGenerator.catSitting(seed: 1, startTime: 0)).peakScore
        XCTAssertLessThan(smallImpact, wholeCat, "a three-key touch and a whole cat must not score the same")
    }

    func testSensitivePresetDoesNotBreakHumanTyping() {
        // The tightest preset a user can pick still must not fire on typing.
        guard let sensitive = SensitivityPreset.sensitive.threshold else {
            return XCTFail("sensitive preset must define a threshold")
        }
        for seed in UInt64(1)...UInt64(10) {
            let samples = TraceGenerator.humanTyping(wordsPerMinute: 120, keyCount: 200, seed: seed)
            let outcome = replay(samples, threshold: sensitive)
            XCTAssertFalse(outcome.detected, "seed \(seed) peak \(outcome.peakScore) at threshold \(sensitive)")
        }
    }
}
