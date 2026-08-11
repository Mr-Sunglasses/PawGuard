import CoreGraphics
import Foundation

enum DetectionSignal: String, Hashable, Codable {
    case simultaneousKeys
    case fastBurst
    case physicalCluster
    case multiKeyHold
    case excessiveRepeat
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
    let heldKeyCount: Int
    let hasPhysicalCluster: Bool

    static let empty = DetectionResult(
        score: 0,
        signals: [],
        confidence: .none,
        simultaneousKeyCount: 0,
        burstKeyCount: 0,
        heldKeyCount: 0,
        hasPhysicalCluster: false
    )
}

final class CatDetector {
    private var eventBuffer = RollingEventBuffer()
    private var heldKeys: [CGKeyCode: TimeInterval] = [:]
    private(set) var threshold: Int

    init(threshold: Int = DetectionRules.defaultThreshold) {
        self.threshold = threshold
    }

    func updateThreshold(_ threshold: Int) {
        self.threshold = max(30, min(100, threshold))
    }

    func reset() {
        eventBuffer.removeAll()
        heldKeys.removeAll(keepingCapacity: true)
    }

    func process(_ sample: KeyboardEventSample) -> DetectionResult {
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
        return currentResult(at: sample.timestamp, modifiers: sample.modifiers)
    }

    private func currentResult(at timestamp: TimeInterval, modifiers: CGEventFlags) -> DetectionResult {
        let burstKeyDowns = eventBuffer.samples.filter {
            $0.type == .keyDown && !KeyboardGeometry.isModifier($0.keyCode) && !$0.isRepeat
                && timestamp - $0.timestamp <= DetectionRules.fastBurstWindow
        }
        // Simultaneous means physically overlapping presses. Counting recent key-downs
        // after their key-up would mistake fast human typing for a paw resting on keys.
        let simultaneousKeys = Set(heldKeys.keys)
        let burstKeys = Set(burstKeyDowns.map(\.keyCode))
        let held = Set(heldKeys.keys)
        let heldHasCluster = KeyboardGeometry.isTightCluster(simultaneousKeys)
        let burstHasCluster = KeyboardGeometry.isTightCluster(burstKeys)
        let simultaneousCount = simultaneousKeys.count
        let burstCount = burstKeys.count
        let heldCount = held.count
        let longHeldCount = heldKeys.values.filter { timestamp - $0 >= DetectionRules.holdThreshold }.count
        let extendedHeldCount = heldKeys.values.filter { timestamp - $0 >= DetectionRules.extendedHoldThreshold }.count
        let repeatCount = eventBuffer.samples.filter {
            $0.type == .keyDown && $0.isRepeat && timestamp - $0.timestamp <= DetectionRules.fastBurstWindow
        }.count

        var score = 0
        var signals = Set<DetectionSignal>()

        switch simultaneousCount {
        case 6...:
            score += 100
            signals.insert(.simultaneousKeys)
        case 5:
            score += 58
            signals.insert(.simultaneousKeys)
        case 4:
            score += 32
            signals.insert(.simultaneousKeys)
        case 3:
            score += 14
            signals.insert(.simultaneousKeys)
        case 2:
            score += 4
        default:
            break
        }

        switch burstCount {
        case 12...:
            score += 35
            signals.insert(.fastBurst)
        case 9...:
            score += 22
            signals.insert(.fastBurst)
        case 7...:
            score += 12
            signals.insert(.fastBurst)
        case 5...:
            score += 5
            signals.insert(.fastBurst)
        default:
            break
        }

        if heldHasCluster {
            switch simultaneousCount {
            case 5...:
                score += 32
                signals.insert(.physicalCluster)
            case 4:
                score += 22
                signals.insert(.physicalCluster)
            case 3:
                score += 10
                signals.insert(.physicalCluster)
            default:
                break
            }
        }

        // A paw can roll across neighboring keys instead of pressing all of
        // them at precisely the same instant. Require both a clustered burst
        // and real overlap so fast sequential human typing is not enough.
        let rollingCluster = burstHasCluster && burstCount >= 5 && simultaneousCount >= 2
        if rollingCluster {
            score += 30
            signals.insert(.physicalCluster)
        }

        if longHeldCount >= 4 {
            score += 45
            signals.insert(.multiKeyHold)
        } else if longHeldCount >= 3 {
            score += 30
            signals.insert(.multiKeyHold)
        } else if longHeldCount >= 2 {
            score += 12
            signals.insert(.multiKeyHold)
        }
        if extendedHeldCount >= 3 {
            score += 30
            signals.insert(.multiKeyHold)
        }
        if repeatCount >= 3 && heldCount >= 2 {
            score += 15
            signals.insert(.excessiveRepeat)
        }

        let looksSequential = simultaneousCount <= 1 && !heldHasCluster && heldCount <= 1
        if looksSequential {
            score -= 20
        }

        let intentionalHold = KeyboardGeometry.isLikelyIntentionalHold(held)
        if intentionalHold {
            score -= 55
        }

        let shortcutModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate]
        if !modifiers.intersection(shortcutModifiers).isEmpty && simultaneousCount <= 4 {
            score -= 30
        }
        score = max(0, score)

        // A stable, known human control cluster stays non-triggering even when
        // key repeat makes it look like a long hold. Unrelated keys in the
        // rolling burst remove this exemption.
        if intentionalHold && burstCount <= 4 {
            score = min(score, max(0, threshold - 1))
        }

        let hasCluster = heldHasCluster || rollingCluster
        let immediate = simultaneousCount >= 6 || (simultaneousCount >= 5 && heldHasCluster && !intentionalHold)
        let confidence: DetectionConfidence
        if immediate || score >= threshold {
            confidence = .cat
        } else if score >= max(25, threshold / 2) {
            confidence = .suspicious
        } else {
            confidence = .none
        }

        return DetectionResult(
            score: score,
            signals: signals,
            confidence: confidence,
            simultaneousKeyCount: simultaneousCount,
            burstKeyCount: burstCount,
            heldKeyCount: heldCount,
            hasPhysicalCluster: hasCluster
        )
    }
}
