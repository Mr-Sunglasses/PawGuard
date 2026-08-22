import Foundation

enum DetectionRules {
    /// Two key-downs closer than this are effectively one physical impact.
    static let synchronyWindow: TimeInterval = 0.030
    static let simultaneousWindow: TimeInterval = 0.120
    static let fastBurstWindow: TimeInterval = 0.450
    static let generalWindow: TimeInterval = 1.200
    /// How far back the contact and autorepeat features look. Longer than
    /// `generalWindow` because a paw that touches down, lifts, and touches down
    /// again a few keys over is one gesture spread over seconds, and because a
    /// run of autorepeats only becomes conclusive after a couple of them.
    static let contactWindow: TimeInterval = 4.0
    /// The rolling buffer has to cover every window that reads from it.
    static let bufferWindow: TimeInterval = max(generalWindow, contactWindow)

    /// How often the engine re-evaluates held keys and advances protection.
    ///
    /// Every hold-based detection is quantised to this, so it is a floor on
    /// latency for a paw that has settled and stopped producing events. The
    /// expensive part of a tick — probing the window server for what is
    /// physically down — runs on a divisor rather than every time.
    static let monitorTick: TimeInterval = 0.10

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

    /// How far apart two key-downs can be and still plausibly sit under the
    /// same paw. Slightly wider than `clusterLinkDistance` because a paw in
    /// motion drifts between presses.
    static let pawReachDistance: Double = 2.2

    /// Successive presses only carry locality evidence once there are enough of
    /// them to be more than chance. Four or five adjacent letters in a row is
    /// an ordinary English word; a dozen is not.
    static let minimumLocalityPairs = 6
    /// Ordinary typing reaches a surprising amount of local run: short words
    /// sit under one hand. Evidence only ramps in above the rate recorded human
    /// sessions actually produce.
    static let localityRampStart: Double = 0.70
    static let localityRampEnd: Double = 0.95

    // MARK: - Contact persistence

    /// A paw sits; fingers pass through. Overlap between keys is only evidence
    /// in proportion to how long that overlap lasts, so the same three keys
    /// mean one thing in a typist's rollover and another under a paw.
    ///
    /// Evidence ramps from `unsettledContactWeight` at the instant of contact
    /// to full weight once two keys have been down together this long.
    static let contactSettleStart: TimeInterval = 0.05
    static let contactSettleEnd: TimeInterval = 0.24
    /// What an instantaneous, not-yet-settled overlap is still worth. Not zero:
    /// a paw landing flat has to be catchable before it has finished settling.
    static let unsettledContactWeight: Double = 0.30

    /// Two keys this close together are neighbours one paw pad covers. Tighter
    /// than `clusterLinkDistance`, which chains across a whole contact patch.
    static let pawContactDistance: Double = 1.7

    /// A kitten's paw often covers only two keys, which every three-key
    /// clustering test is blind to. Two neighbouring keys held together this
    /// long is the smallest contact worth calling a paw: human rollover between
    /// adjacent keys is over in well under a fifth of a second.
    static let pairContactRampStart: TimeInterval = 0.30
    static let pairContactRampEnd: TimeInterval = 1.00
    /// Overlap shorter than this is rollover, and is not counted as a contact
    /// at all when reconstructing past touches.
    static let minimumContactOverlap: TimeInterval = 0.22

    /// A single key nobody leans on, held this long, is a paw touch in its own
    /// right. A kitten crossing the keyboard often puts down one key at a time.
    ///
    /// Set well past the half second it takes to become unusual, because slow
    /// deliberate typing lands there: a hesitant typist, or one working around
    /// a motor impairment, holds each key long enough to autorepeat, and a
    /// lower floor turned every one of those keystrokes into a paw touch.
    static let singleTouchMinimumHold: TimeInterval = 0.75

    /// Held keys that have individually outlasted a keystroke. One is
    /// unremarkable — a slow typist rests on a key that long. Two at once is
    /// not something typing produces: reaching a second key means the first is
    /// already on its way back up.
    static let settledKeyRampStart: Double = 1
    static let settledKeyRampEnd: Double = 2

    /// How closely the held keys arrived together. A paw puts its keys down
    /// inside a few dozen milliseconds; a typist who happens to have four down
    /// at once took a quarter of a second to get there.
    static let arrivalSpreadRampStart: TimeInterval = 0.05
    static let arrivalSpreadRampEnd: TimeInterval = 0.18

    /// Separate paw touches inside `contactWindow`. One is a touch; a run of
    /// them a second apart is a cat walking across the keyboard.
    static let pawTouchRampStart: Double = 1
    static let pawTouchRampEnd: Double = 3

    /// How long two, three, and four keys have been down together. Replaces
    /// counting keys past fixed hold thresholds, which could not see a two-key
    /// contact at all and needed three quarters of a second to see a three-key
    /// one.
    static let multiHoldRampStart: TimeInterval = 0.25
    static let multiHoldRampMid: TimeInterval = 1.10
    static let multiHoldRampEnd: TimeInterval = 2.50

    // MARK: - Resting contact

    /// A key nobody leans on, held far past any keystroke. Measured two ways —
    /// how long it has been down, and how many autorepeats it has fired — and
    /// the stronger of the two is used.
    ///
    /// The duration ramp is the one that works when the user has key repeat
    /// switched off. The repeat ramp is the one that matters in practice: a
    /// paw parked on a letter fires a repeat every few dozen milliseconds, and
    /// each one is a character that has to be deleted afterwards.
    static let sustainedHoldRampStart: TimeInterval = 1.4
    static let sustainedHoldRampEnd: TimeInterval = 7.0

    /// Stretching a letter for effect — "noooo", "hmmm" — is a real thing
    /// people do, and for a dozen repeats it is indistinguishable from a paw.
    /// Evidence ramps in above the longest stretch anyone types by hand and is
    /// decisive by three dozen, which no human produces on purpose.
    static let repeatRunRampStart: Double = 14
    static let repeatRunRampEnd: Double = 36
    /// A run shorter than this is not a run. Long enough that a key held for
    /// around a second — which slow typing does reach — cannot qualify, so the
    /// flood signal needs keys genuinely parked on, not merely dwelt on.
    static let minimumRepeatRun = 10

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
    var overlap: Double = 62
    var extremeOverlap: Double = 62
    var cluster: Double = 56
    var rapidCluster: Double = 42
    var synchrony: Double = 58
    var multiKeyHold: Double = 58
    var multiCluster: Double = 34
    var improbableCombination: Double = 38
    var burst: Double = 16
    var keyRate: Double = 24
    var rhythm: Double = 18
    var sequentialLocality: Double = 22
    var repeatedImpact: Double = 46
    /// A paw covering two neighbouring keys and staying there. The smallest
    /// contact a kitten makes, and the one the three-key clustering signals
    /// cannot see at all.
    var pairContact: Double = 72
    /// Separate paw touches in a row: a cat crossing the keyboard.
    var pawTouches: Double = 58
    /// One key nobody leans on, held or autorepeating far past a keystroke.
    var sustainedHold: Double = 92
    /// Several different keys nobody leans on, each autorepeating, inside a few
    /// seconds. A person stretching a letter stretches one letter.
    var repeatFlood: Double = 64

    /// Multipliers applied after the evidence is combined.
    ///
    /// `sequentialDamping` is the floor: it applies to sequential typing that
    /// also wanders across the keyboard the way human typing does. Sequential
    /// presses that stay under one paw are damped only to
    /// `localSequentialDamping`.
    var sequentialDamping: Double = 0.25
    var localSequentialDamping: Double = 0.75
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
