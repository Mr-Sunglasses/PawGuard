import CoreGraphics
import Foundation

@testable import PawGuard

// MARK: - Event construction

func makeSample(
    _ key: CGKeyCode,
    time: TimeInterval,
    type: KeyboardEventKind,
    isRepeat: Bool = false,
    modifiers: CGEventFlags = []
) -> KeyboardEventSample {
    KeyboardEventSample(keyCode: key, timestamp: time, type: type, isRepeat: isRepeat, modifiers: modifiers)
}

// MARK: - Injection spy

/// Stands in for the real injector so tests never post events into the machine
/// running them.
final class SpyKeyboardEventInjector: KeyboardEventInjecting {
    private(set) var releasedKeys: [CGKeyCode] = []
    private(set) var replayedEvents: [KeyboardEventSample] = []
    private(set) var deleteCount = 0
    private(set) var replayCallCount = 0

    func releaseKeys(_ keyCodes: [CGKeyCode]) {
        releasedKeys.append(contentsOf: keyCodes)
    }

    func replay(_ events: [KeyboardEventSample]) {
        replayCallCount += 1
        replayedEvents.append(contentsOf: events)
    }

    func deleteBackward(count: Int) {
        deleteCount += count
    }

    func reset() {
        releasedKeys = []
        replayedEvents = []
        deleteCount = 0
        replayCallCount = 0
    }
}

// MARK: - Clock

/// A wall clock the tests move by hand, so grace-window behaviour can be
/// exercised without sleeping.
final class TestClock {
    private(set) var now: Date

    init(now: Date = Date(timeIntervalSince1970: 1_000_000)) {
        self.now = now
    }

    func advance(by interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
    }
}

// MARK: - Deterministic randomness

/// SplitMix64, so generated traces are identical on every run and a failure can
/// be reproduced from its seed.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func double(in range: ClosedRange<Double>) -> Double {
        Double.random(in: range, using: &self)
    }
}

// MARK: - Traces

/// A recorded or generated stream of keyboard events, with the label needed to
/// score a replay. Stored as JSON lines so real sessions can be captured with a
/// small recorder and committed alongside generated ones.
struct KeyboardTrace {
    enum Label: String {
        case human
        case cat
    }

    struct Event: Codable {
        let key: UInt16
        let time: TimeInterval
        /// "down", "up", or "flags".
        let kind: String
        var repeated: Bool = false
        var flags: UInt64 = 0

        var sample: KeyboardEventSample {
            let type: KeyboardEventKind =
                switch kind {
                case "up": .keyUp
                case "flags": .flagsChanged
                default: .keyDown
                }
            return KeyboardEventSample(
                keyCode: CGKeyCode(key),
                timestamp: time,
                type: type,
                isRepeat: repeated,
                modifiers: CGEventFlags(rawValue: flags)
            )
        }
    }

    let name: String
    let label: Label
    let events: [Event]
    /// For cat traces, when the paw actually landed, so detection latency can
    /// be measured.
    let onsetTime: TimeInterval?

    var samples: [KeyboardEventSample] { events.map(\.sample) }

    static func jsonLines(_ events: [Event]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try events.map { try String(decoding: encoder.encode($0), as: UTF8.self) }.joined(separator: "\n")
    }

    static func parse(jsonLines: String, name: String, label: Label, onsetTime: TimeInterval? = nil) throws
        -> KeyboardTrace
    {
        let decoder = JSONDecoder()
        let events =
            try jsonLines
            .split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { try decoder.decode(Event.self, from: Data($0.utf8)) }
        return KeyboardTrace(name: name, label: label, events: events, onsetTime: onsetTime)
    }
}

// MARK: - Trace generation

enum TraceGenerator {
    /// Letters weighted roughly like English text, so generated typing wanders
    /// across the keyboard the way real typing does.
    private static let commonKeys: [CGKeyCode] = [
        0, 1, 2, 3, 4, 5, 8, 9, 11, 12, 13, 14, 15, 16, 17, 31, 32, 34, 35, 37,
        38, 40, 41, 45, 46, 47, 49, 49, 49, 14, 4, 37, 31, 45, 0, 17,
    ]

    /// Human typing at a given speed, with realistic key hold times. Because a
    /// hold usually outlasts the gap to the next key, this produces genuine
    /// two- and three-key rollover, which is exactly the pattern that must not
    /// trigger protection.
    static func humanTyping(
        wordsPerMinute: Double,
        keyCount: Int,
        seed: UInt64,
        startTime: TimeInterval = 0
    ) -> [KeyboardEventSample] {
        var generator = SeededGenerator(seed: seed)
        var samples: [KeyboardEventSample] = []
        var pendingUps: [(time: TimeInterval, key: CGKeyCode)] = []
        let meanInterval = 60.0 / (wordsPerMinute * 5.0)
        var time = startTime

        for _ in 0..<keyCount {
            let key = commonKeys.randomElement(using: &generator) ?? 0
            // Log-normal-ish jitter: mostly near the mean with occasional pauses.
            let jitter = generator.double(in: 0.55...1.9)
            let interval = meanInterval * jitter
            let hold = generator.double(in: 0.055...0.115)

            while let first = pendingUps.first, first.time <= time {
                samples.append(makeSample(first.key, time: first.time, type: .keyUp))
                pendingUps.removeFirst()
            }

            samples.append(makeSample(key, time: time, type: .keyDown))
            pendingUps.append((time + hold, key))
            pendingUps.sort { $0.time < $1.time }
            time += interval
        }
        for pending in pendingUps.sorted(by: { $0.time < $1.time }) {
            samples.append(makeSample(pending.key, time: pending.time, type: .keyUp))
        }
        return samples.sorted { $0.timestamp < $1.timestamp }
    }

    /// A paw landing: several neighbouring keys struck almost together and then
    /// held.
    /// The keys a paw centred on `anchor` would cover.
    static func pawKeys(anchor: CGKeyCode, count: Int) -> [CGKeyCode] {
        guard let anchorPoint = KeyboardGeometry.position(for: anchor) else { return [] }
        return
            (0...127)
            .map(CGKeyCode.init)
            .filter { !KeyboardGeometry.isModifier($0) }
            .compactMap { key -> (CGKeyCode, Double)? in
                guard let point = KeyboardGeometry.position(for: key) else { return nil }
                return (key, anchorPoint.distance(to: point))
            }
            .filter { $0.1 <= 2.2 }
            .sorted { ($0.1, $0.0) < ($1.1, $1.0) }
            .prefix(count)
            .map(\.0)
    }

    static func pawImpact(
        anchor: CGKeyCode,
        keyCount: Int,
        seed: UInt64,
        startTime: TimeInterval,
        holdDuration: TimeInterval = 2.0
    ) -> [KeyboardEventSample] {
        var generator = SeededGenerator(seed: seed)
        let neighbours = pawKeys(anchor: anchor, count: keyCount)
        guard !neighbours.isEmpty else { return [] }

        var samples: [KeyboardEventSample] = []
        var time = startTime
        for key in neighbours {
            samples.append(makeSample(key, time: time, type: .keyDown))
            time += generator.double(in: 0.004...0.022)
        }
        let releaseStart = startTime + holdDuration
        for (index, key) in neighbours.enumerated() {
            samples.append(makeSample(key, time: releaseStart + Double(index) * 0.012, type: .keyUp))
        }
        return samples.sorted { $0.timestamp < $1.timestamp }
    }

    /// A cat settling across the keyboard: two paw areas pressed a moment apart
    /// and held for a long time.
    static func catSitting(seed: UInt64, startTime: TimeInterval) -> [KeyboardEventSample] {
        let first = pawImpact(anchor: 13, keyCount: 4, seed: seed, startTime: startTime, holdDuration: 6)
        let second = pawImpact(anchor: 40, keyCount: 3, seed: seed &+ 1, startTime: startTime + 0.09, holdDuration: 6)
        return (first + second).sorted { $0.timestamp < $1.timestamp }
    }
}
