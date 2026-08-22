import CoreGraphics
import XCTest

@testable import PawGuard

final class DetectionFeatureTests: XCTestCase {
    private func features(
        held: [CGKeyCode: TimeInterval],
        samples: [KeyboardEventSample],
        at timestamp: TimeInterval,
        modifiers: CGEventFlags = []
    ) -> DetectionFeatures {
        DetectionFeatures.extract(heldKeys: held, samples: samples, modifiers: modifiers, at: timestamp)
    }

    func testSynchronyCountsNearSimultaneousImpacts() {
        let samples = [
            makeSample(3, time: 0, type: .keyDown),
            makeSample(5, time: 0.006, type: .keyDown),
            makeSample(4, time: 0.011, type: .keyDown),
            makeSample(38, time: 0.018, type: .keyDown),
        ]
        let extracted = features(held: [3: 0, 5: 0.006, 4: 0.011, 38: 0.018], samples: samples, at: 0.02)
        XCTAssertEqual(extracted.synchronyCount, 4)
    }

    func testSynchronyIgnoresStaggeredHumanRollover() {
        let samples = (0..<4).map { makeSample(CGKeyCode(3 + $0), time: Double($0) * 0.06, type: .keyDown) }
        let extracted = features(held: [:], samples: samples, at: 0.2)
        XCTAssertEqual(extracted.synchronyCount, 1)
    }

    func testMedianIntervalMeasuresTypingRhythm() {
        let samples = (0..<5).map { makeSample(CGKeyCode(3 + $0), time: Double($0) * 0.12, type: .keyDown) }
        let extracted = features(held: [:], samples: samples, at: 0.5)
        XCTAssertEqual(extracted.medianInterval, 0.12, accuracy: 0.001)
    }

    func testHandAlternationIsHighForOrdinaryTyping() {
        // Alternating left and right hands, as touch typing does.
        let keys: [CGKeyCode] = [0, 38, 1, 40, 2, 37]
        let samples = keys.enumerated().map { makeSample($0.element, time: Double($0.offset) * 0.1, type: .keyDown) }
        let extracted = features(held: [:], samples: samples, at: 0.6)
        XCTAssertEqual(extracted.handAlternationRate, 1, accuracy: 0.001)
    }

    func testHandAlternationIsLowForAOneSidedPaw() {
        let keys: [CGKeyCode] = [38, 40, 37, 41]
        let samples = keys.enumerated().map { makeSample($0.element, time: Double($0.offset) * 0.01, type: .keyDown) }
        let extracted = features(held: [:], samples: samples, at: 0.05)
        XCTAssertEqual(extracted.handAlternationRate, 0, accuracy: 0.001)
    }

    func testSeparateClustersAreCounted() {
        let held: [CGKeyCode: TimeInterval] = [12: 0, 13: 0, 40: 0, 37: 0]
        let extracted = features(held: held, samples: [], at: 0.1)
        XCTAssertEqual(extracted.separateClusterCount, 2)
    }

    func testKeyRateIsSustainedNotInstantaneous() {
        // Seven keys inside a fifth of a second is a burst, but over the
        // one-and-a-fifth-second window it is not a sustained rate.
        let samples = (0..<7).map { makeSample(CGKeyCode(3 + $0), time: Double($0) * 0.03, type: .keyDown) }
        let extracted = features(held: [:], samples: samples, at: 0.2)
        XCTAssertEqual(extracted.keyRate, 7 / DetectionRules.generalWindow, accuracy: 0.001)
        XCTAssertLessThan(extracted.keyRate, DetectionRules.humanKeyRateFloor)
    }

    func testCoHoldDurationsReadOffTheSortedHolds() {
        // Held for 1.6s, 1.5s and 0.8s respectively at the moment of extraction.
        let held: [CGKeyCode: TimeInterval] = [3: 0, 5: 0.1, 4: 0.8]
        let extracted = features(held: held, samples: [], at: 1.6)
        XCTAssertEqual(extracted.maxHoldDuration, 1.6, accuracy: 0.001)
        XCTAssertEqual(extracted.pairHoldDuration, 1.5, accuracy: 0.001, "two keys have overlapped this long")
        XCTAssertEqual(extracted.tripleHoldDuration, 0.8, accuracy: 0.001, "all three only since the last one landed")
        XCTAssertEqual(extracted.fullHoldDuration, 0.8, accuracy: 0.001, "the shortest hold gates the whole set")
    }

    /// The measure that separates a paw from rollover. A typist reaches four
    /// keys down at once only in passing — the fourth lands as the first is
    /// already leaving — so however high the count climbs, the depth of the
    /// overlap stays near zero.
    func testFullHoldDurationStaysNearZeroForRollover() {
        let held: [CGKeyCode: TimeInterval] = [4: 0.30, 38: 0.36, 15: 0.42, 1: 0.47]
        let rollover = features(held: held, samples: [], at: 0.5)
        XCTAssertEqual(rollover.simultaneousCount, 4)
        XCTAssertEqual(rollover.fullHoldDuration, 0.03, accuracy: 0.001)

        // The same four keys under a paw: they landed together and stayed.
        let paw: [CGKeyCode: TimeInterval] = [4: 0.0, 38: 0.01, 15: 0.02, 1: 0.03]
        let contact = features(held: paw, samples: [], at: 0.5)
        XCTAssertEqual(contact.simultaneousCount, 4)
        XCTAssertEqual(contact.fullHoldDuration, 0.47, accuracy: 0.001)
    }

    // MARK: - Paw contacts

    /// A kitten's pad covers two keys and no more, which every three-key
    /// clustering test is blind to. Duration is what makes the pair safe to
    /// count: adjacent-key rollover between fingers is over in a fraction of
    /// the time a paw stays put.
    func testPawContactMeasuresNeighbouringKeysHeldTogether() {
        let extracted = features(held: [4: 0, 38: 0.05], samples: [], at: 1.2)
        XCTAssertEqual(extracted.pawContactDuration, 1.15, accuracy: 0.001)
        XCTAssertEqual(extracted.pawTouchCount, 1)
    }

    func testPawContactIgnoresKeysTooFarApartForOnePaw() {
        // Q and the right-hand semicolon: held together, but no pad spans that.
        let extracted = features(held: [12: 0, 41: 0], samples: [], at: 1.2)
        XCTAssertEqual(extracted.pawContactDuration, 0, "these are two hands, not one paw")
    }

    func testPawContactIgnoresRollover() {
        // Two adjacent keys overlapping the way fast typing overlaps them.
        let samples = [
            makeSample(4, time: 0, type: .keyDown),
            makeSample(38, time: 0.05, type: .keyDown),
            makeSample(4, time: 0.10, type: .keyUp),
            makeSample(38, time: 0.16, type: .keyUp),
        ]
        let extracted = features(held: [:], samples: samples, at: 0.4)
        XCTAssertEqual(extracted.pawContactDuration, 0.05, accuracy: 0.001)
        XCTAssertEqual(extracted.pawTouchCount, 0, "an overlap this brief is rollover, not a contact")
    }

    /// A cat crossing the keyboard sets a paw down, lifts it, and sets it down
    /// again a few keys over. Each touch is weak; the run of them is not.
    func testPawTouchesCountsSeparateContacts() {
        var samples: [KeyboardEventSample] = []
        for (index, pair) in [[4, 38], [15, 17], [45, 46]].enumerated() {
            let base = Double(index) * 1.0
            for key in pair { samples.append(makeSample(CGKeyCode(key), time: base, type: .keyDown)) }
            for key in pair { samples.append(makeSample(CGKeyCode(key), time: base + 0.6, type: .keyUp)) }
        }
        let extracted = features(held: [:], samples: samples, at: 2.8)
        XCTAssertEqual(extracted.pawTouchCount, 3)
    }

    func testOneWideContactIsASingleTouch() {
        // Four keys under one paw all overlap each other; that is one touch,
        // not the six its pairs would suggest.
        let held: [CGKeyCode: TimeInterval] = [32: 0, 34: 0, 38: 0, 40: 0]  // U I J K
        let extracted = features(held: held, samples: [], at: 1.0)
        XCTAssertEqual(extracted.pawTouchCount, 1)
    }

    /// A chord the user holds on purpose is not a paw touch — and the test has
    /// to happen during extraction, because the contact features look back over
    /// several seconds and would otherwise see a released WASD hold as a touch
    /// long after any exemption that inspects the currently held keys has
    /// stopped applying.
    func testIntentionalChordsAreNotPawTouches() {
        var samples: [KeyboardEventSample] = []
        for key in [CGKeyCode(0), 1] { samples.append(makeSample(key, time: 0, type: .keyDown)) }
        for key in [CGKeyCode(0), 1] { samples.append(makeSample(key, time: 1.2, type: .keyUp)) }
        let extracted = features(held: [:], samples: samples, at: 2.0)
        XCTAssertEqual(extracted.pawTouchCount, 0, "A and S is a gaming hold, released or not")
        XCTAssertEqual(extracted.pawContactDuration, 0)
    }

    func testAllowlistedChordIsNotAPawTouchAfterRelease() {
        var samples: [KeyboardEventSample] = []
        for key in [CGKeyCode(38), 40] { samples.append(makeSample(key, time: 0, type: .keyDown)) }
        for key in [CGKeyCode(38), 40] { samples.append(makeSample(key, time: 1.2, type: .keyUp)) }

        let unlearned = DetectionFeatures.extract(heldKeys: [:], samples: samples, modifiers: [], at: 2.0)
        XCTAssertEqual(unlearned.pawTouchCount, 1)

        let learned = DetectionFeatures.extract(
            heldKeys: [:],
            samples: samples,
            modifiers: [],
            at: 2.0,
            exemptKeySets: [[38, 40]]
        )
        XCTAssertEqual(learned.pawTouchCount, 0)
    }

    // MARK: - Contact credibility

    /// The measure that lets a paw be caught as it lands, before anything has
    /// had time to persist.
    func testArrivalSpreadSeparatesAFlatPawFromRollover() {
        let paw: [CGKeyCode: TimeInterval] = [3: 0, 5: 0.02, 4: 0.04, 38: 0.06]
        let landed = features(held: paw, samples: [], at: 0.06)
        XCTAssertEqual(landed.contactArrivalSpread, 0.06, accuracy: 0.001)

        let rollover: [CGKeyCode: TimeInterval] = [4: 0, 38: 0.075, 15: 0.15, 1: 0.225]
        let typing = features(held: rollover, samples: [], at: 0.225)
        XCTAssertEqual(typing.contactArrivalSpread, 0.225, accuracy: 0.001)
    }

    /// A cat stepping onto the keys one at a time and leaving them there: the
    /// keys arrive at typing speed and the newest has only just landed, so
    /// neither arrival spread nor full overlap sees it. What gives it away is
    /// that two of them have already outlasted any keystroke.
    func testSettledKeyCountSeesKeysLeftDownOneAtATime() {
        let stepped: [CGKeyCode: TimeInterval] = [38: 0, 40: 0.08, 32: 0.16, 34: 0.24, 46: 0.32]
        let extracted = features(held: stepped, samples: [], at: 0.32)
        XCTAssertEqual(extracted.settledKeyCount, 2)

        // The same five keys reached by typing: every one is about to lift.
        let rolling: [CGKeyCode: TimeInterval] = [38: 0.12, 40: 0.17, 32: 0.22, 34: 0.27, 46: 0.32]
        XCTAssertEqual(features(held: rolling, samples: [], at: 0.32).settledKeyCount, 0)
    }

    // MARK: - Autorepeat volume

    /// The repeats are the damage: every one is a character to delete
    /// afterwards, and they arrive seconds before hold duration alone becomes
    /// conclusive.
    func testRepeatRunCountsAutorepeatsOnKeysNobodyLeansOn() {
        var samples = [makeSample(38, time: 0, type: .keyDown)]
        for index in 1...20 {
            samples.append(makeSample(38, time: 0.375 + Double(index) * 0.09, type: .keyDown, isRepeat: true))
        }
        let extracted = features(held: [38: 0], samples: samples, at: 2.3)
        XCTAssertEqual(extracted.sustainedRepeatRun, 20)
        XCTAssertEqual(extracted.repeatingKeyCount, 1)
    }

    func testRepeatRunIgnoresKeysPeopleHoldOnPurpose() {
        var samples = [makeSample(51, time: 0, type: .keyDown)]
        for index in 1...20 {
            samples.append(makeSample(51, time: 0.375 + Double(index) * 0.09, type: .keyDown, isRepeat: true))
        }
        let extracted = features(held: [51: 0], samples: samples, at: 2.3)
        XCTAssertEqual(extracted.sustainedRepeatRun, 0, "holding delete says nothing about a cat")
        XCTAssertEqual(extracted.repeatingKeyCount, 0)
    }

    /// Stretching a letter for effect stretches one letter. A cat shuffling
    /// about produces run after run on different keys.
    func testRepeatingKeyCountSeesSeparateRuns() {
        let run = DetectionRules.minimumRepeatRun
        var samples: [KeyboardEventSample] = []
        for (index, key) in [CGKeyCode(38), 15, 45].enumerated() {
            let base = Double(index) * 1.3
            samples.append(makeSample(key, time: base, type: .keyDown))
            for step in 1...run {
                samples.append(makeSample(key, time: base + 0.2 + Double(step) * 0.06, type: .keyDown, isRepeat: true))
            }
            samples.append(makeSample(key, time: base + 1.1, type: .keyUp))
        }
        let extracted = features(held: [:], samples: samples, at: 3.9)
        XCTAssertEqual(extracted.repeatingKeyCount, 3)
    }

    /// Slow deliberate typing reaches a couple of repeats per key. The flood
    /// signal has to need keys genuinely parked on, not merely dwelt on.
    func testShortRepeatsDoNotCountAsRuns() {
        var samples: [KeyboardEventSample] = []
        for (index, key) in [CGKeyCode(38), 15, 45].enumerated() {
            let base = Double(index) * 1.0
            samples.append(makeSample(key, time: base, type: .keyDown))
            for step in 1...(DetectionRules.minimumRepeatRun - 1) {
                samples.append(makeSample(key, time: base + 0.2 + Double(step) * 0.02, type: .keyDown, isRepeat: true))
            }
            samples.append(makeSample(key, time: base + 0.6, type: .keyUp))
        }
        XCTAssertEqual(features(held: [:], samples: samples, at: 3.0).repeatingKeyCount, 0)
    }

    func testAutorepeatDoesNotInflateTimingFeatures() {
        var samples = [makeSample(3, time: 0, type: .keyDown)]
        for index in 1..<20 {
            samples.append(makeSample(3, time: Double(index) * 0.03, type: .keyDown, isRepeat: true))
        }
        let extracted = features(held: [3: 0], samples: samples, at: 0.6)
        XCTAssertEqual(extracted.keyRate, 1 / DetectionRules.generalWindow, accuracy: 0.001)
        XCTAssertEqual(extracted.synchronyCount, 1)
        XCTAssertFalse(extracted.medianInterval.isFinite)
    }

    // MARK: - Repeated impacts

    func testImpactCountSeesEachSeparatePawTouch() {
        // Three compact three-key touches, each a few keys further along, the
        // way a cat crossing the keyboard sets a paw down and lifts it again.
        var samples: [KeyboardEventSample] = []
        for (index, group) in [[12, 13, 14], [0, 1, 2], [6, 7, 8]].enumerated() {
            let base = Double(index) * 0.4
            for (offset, key) in group.enumerated() {
                samples.append(makeSample(CGKeyCode(key), time: base + Double(offset) * 0.008, type: .keyDown))
            }
        }
        let extracted = features(held: [:], samples: samples, at: 1.0)
        XCTAssertEqual(extracted.impactCount, 3)
    }

    func testImpactCountIgnoresHumanRollover() {
        // Typing at 130 wpm: keys overlap, but they arrive far too spread out
        // to be one impact, and they wander across the keyboard.
        let keys: [CGKeyCode] = [4, 38, 15, 1, 17, 45, 11, 40]
        let samples = keys.enumerated().map { makeSample($0.element, time: Double($0.offset) * 0.055, type: .keyDown) }
        let extracted = features(held: [:], samples: samples, at: 0.5)
        XCTAssertEqual(extracted.impactCount, 0)
    }

    // MARK: - Sequential locality

    func testSequentialLocalityIsHighForKeysUnderOnePaw() {
        // Q W E R T Y U I: every step lands on the neighbouring key.
        let keys: [CGKeyCode] = [12, 13, 14, 15, 17, 16, 32, 34]
        let samples = keys.enumerated().map { makeSample($0.element, time: Double($0.offset) * 0.1, type: .keyDown) }
        let extracted = features(held: [:], samples: samples, at: 0.8)
        XCTAssertEqual(extracted.localityPairCount, keys.count - 1)
        XCTAssertEqual(extracted.sequentialLocality, 1.0, accuracy: 0.001)
    }

    func testSequentialLocalityIsLowForTypingThatWanders() {
        // Alternating hands across the board, as ordinary typing does.
        let keys: [CGKeyCode] = [4, 31, 0, 37, 13, 40, 6, 34]
        let samples = keys.enumerated().map { makeSample($0.element, time: Double($0.offset) * 0.1, type: .keyDown) }
        let extracted = features(held: [:], samples: samples, at: 0.8)
        XCTAssertLessThan(extracted.sequentialLocality, 0.4)
    }

    func testSequentialLocalityIgnoresAKeyRepeatingInPlace() {
        // A doubled letter says nothing about where the paw moved next.
        let samples = [
            makeSample(4, time: 0, type: .keyDown),
            makeSample(4, time: 0.1, type: .keyDown),
            makeSample(31, time: 0.2, type: .keyDown),
        ]
        let extracted = features(held: [:], samples: samples, at: 0.3)
        XCTAssertEqual(extracted.localityPairCount, 1, "the repeated key contributes no pair")
    }

    // MARK: - Sustained holds

    func testSustainedHoldIgnoresKeysPeopleActuallyLeanOn() {
        // Delete, an arrow and a movement key, all held for half a minute.
        let held: [CGKeyCode: TimeInterval] = [51: 0, 125: 0, 13: 0]
        let extracted = features(held: held, samples: [], at: 30)
        XCTAssertEqual(extracted.maxHoldDuration, 30, accuracy: 0.001)
        XCTAssertEqual(extracted.sustainedHoldDuration, 0, "none of these say anything about a cat")
    }

    func testSustainedHoldMeasuresKeysNobodyHolds() {
        let extracted = features(held: [38: 0, 51: 2], samples: [], at: 20)
        XCTAssertEqual(extracted.sustainedHoldDuration, 20, accuracy: 0.001, "the letter, not the delete key")
    }

    func testShortcutModifiersAreDetected() {
        let extracted = features(held: [1: 0], samples: [], at: 0.1, modifiers: .maskCommand)
        XCTAssertTrue(extracted.hasShortcutModifier)
    }

    func testRampIsClampedAtBothEnds() {
        XCTAssertEqual(detectionRamp(0, from: 1, to: 5), 0, accuracy: 0.001)
        XCTAssertEqual(detectionRamp(3, from: 1, to: 5), 0.5, accuracy: 0.001)
        XCTAssertEqual(detectionRamp(9, from: 1, to: 5), 1, accuracy: 0.001)
    }
}
