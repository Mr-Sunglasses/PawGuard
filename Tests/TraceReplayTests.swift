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
        var nextTick = (samples.first?.timestamp ?? 0) + 0.25

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
                nextTick += 0.25
            }
            record(detector.process(sample), at: sample.timestamp)
        }
        // Keep evaluating for a moment after the last event, the way the app's
        // timer does when a paw settles and stops producing events.
        let end = (samples.last?.timestamp ?? 0) + 2
        while nextTick <= end {
            record(detector.evaluate(at: nextTick), at: nextTick)
            nextTick += 0.25
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
