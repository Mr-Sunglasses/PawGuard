# Detection model

PawGuard uses deterministic local heuristics. It does not inspect characters, words, applications, windows, documents, clipboard data, or cat photos.

## Input metadata

Each in-memory sample contains only:

- Virtual key code
- Key down, key up, or modifier-state event
- Monotonic timestamp
- Auto-repeat state
- Modifier flags

Samples are retained in a rolling 1.2-second buffer. The detector also tracks which non-modifier keys are currently held and when each hold began.

### Timekeeping

`CGEvent.timestamp` is expressed in mach absolute time units, not nanoseconds. On Apple Silicon one unit is 125/3 ns, so dividing the raw value by a billion yields a clock roughly 41 times slow and unrelated to `ProcessInfo.systemUptime`. `MonotonicClock` converts through `mach_timebase_info` so event stamps and timer evaluations share one clock, and falls back to the current time if a stamp is missing or implausible. Every window in `DetectionRules` is in real seconds.

## Geometry

Every key macOS can report has an approximate physical position in key units, including the function row, the navigation cluster, the numeric keypad, and the arrows. Virtual key codes are physical rather than logical, so one table serves QWERTY, AZERTY, and Dvorak alike; only the enclosure type (ANSI, ISO, JIS) changes the arrangement, and that is detected at launch.

Compactness is a density measure, not a bounding box. Keys one unit apart score 1.0; the loose limit grows with the square root of the key count, because a paw covering more keys necessarily covers more area. Held keys are grouped into physically contiguous clusters by single linkage, so a cat lying across the keyboard with its chest on one area and a paw on another is recognised as two clusters rather than dismissed as scattered.

## Signals

The score combines evidence that is unusual for human typing:

| Signal | Meaning |
| --- | --- |
| Simultaneous keys | Several non-modifier keys physically overlap |
| Physical cluster | Held keys occupy a compact area, weighted by how tightly packed they are |
| Rapid cluster | Three or more nearby keys land within 120 ms |
| Impact synchrony | Several keys land within 30 ms, closer than fingers roll |
| Multi-cluster | Two separate compact groups are held at once |
| Multi-key hold | Several keys remain held past 0.7 or 1.5 seconds |
| Improbable combination | Function-row or structural keys held together with letters |
| Fast burst | Many unique keys occur inside 0.45 seconds |
| Non-human rate | Sustained unique-key rate above what fingers reach |
| Excessive repeat | Repeats occur while multiple keys remain held |

Every term is a smooth ramp rather than a step, so one extra key shifts the score by a few points instead of tens. All weights live in `DetectionWeights`, and the final score is normalised to 0-100 so a threshold means the same thing across presets.

Speed and rhythm are gated on real overlap. Sequential speed alone is how humans type fast, so a burst on its own stays well below the threshold. Key rate is measured over the full rolling window as a sustained rate, not as an instantaneous burst.

## Two-stage protection

Crossing the threshold does not lock the keyboard outright. Borderline evidence opens a grace window of 180 ms during which input is withheld and buffered rather than delivered. When the window closes the detector is re-evaluated:

- Still cat-like: the buffered events are discarded and protection engages.
- No longer cat-like: the buffered events are replayed in order and monitoring resumes.

Being wrong therefore costs a barely perceptible delay instead of a locked keyboard, which is what allows the thresholds to sit where they do. Evidence beyond anything a human produces (a score of 95 or more) skips the window entirely. The window can be turned off in Settings.

## Held-key ground truth

Every quarter second the engine reads which keys are physically down from `CGEventSource.keyState` and reconciles the inferred set against it. This catches a paw already resting on the keyboard before PawGuard started, and drops keys whose key-up was lost while the tap was disabled. Holds older than 30 seconds with no corroboration expire on their own.

## Releasing what applications already saw

Keys delivered before protection engages would otherwise stay stuck down for the whole lock, because their key-ups are withheld along with everything else. On locking, PawGuard synthesises a key-up for every key an application saw go down, and for any modifier physically held at that moment. Conversely, a key-up whose key-down was withheld is withheld too, so no application sees a release it never saw pressed. Injected events carry a marker so PawGuard's own tap ignores them.

## Human-pattern protections

The detector reduces or caps confidence for:

- Purely sequential typing with no overlapping keys
- Command, Control, or Option shortcut chords
- Common two-to-four-key WASD/QE/Space gaming holds
- Arrow-key navigation holds
- Chords the user has repeatedly excused
- Modifier-only events
- Key-up events, which can update state but can never initiate protection
- Released rapid typing, which cannot activate during periodic hold evaluation

A paw landing squarely on WASD is genuinely ambiguous, and PawGuard resolves that ambiguity in favour of the human. One more key under the paw removes the exemption.

The engine enters a three-second cooldown after protection is released. During cooldown, samples are cleared and cannot immediately retrigger the overlay.

## Standing down

PawGuard suppresses protection entirely while a full-screen app is frontmost (optional) or while the frontmost app is on the user's exclusion list. During macOS secure input no event tap receives key events at all, so the menu bar says so rather than claiming to be watching.

## Learning from the user

Dismissing a lock within six seconds is treated as a labelled false positive: the threshold offset rises, and a chord that has been wrong three times is added to a personal allowlist. A lock that runs its course counts as confirmation and decays the offset back towards the user's own setting. Passive observation of how often this user genuinely overlaps three or more keys raises the bar for heavy rollers. Records contain key codes, scores, and signal names — never characters — and never leave the Mac. All of it can be reset in Settings.

## Sensitivity presets

| Preset | Threshold | Intended use |
| --- | ---: | --- |
| Relaxed | 85 | Very fast typists, frequent shortcuts, or gaming |
| Balanced | 70 | Recommended everyday default |
| Sensitive | 55 | Earlier intervention for frequent cat activity |
| Custom | 30–100 | Manual calibration |

Adaptive calibration adjusts the active threshold by up to ±20 from the chosen preset. The Detection settings pane shows both numbers.

## Regression coverage

Detection changes are measured, not argued about. `TraceReplayTests` replays whole event streams — including the quarter-second timer evaluations — and reports which side each one lands on.

- `Tests/Fixtures/*.jsonl` holds committed traces. Files named `cat-*` are expected to trigger; everything else must not. Recorded sessions can be dropped in beside the generated ones and are picked up automatically.
- Generated human typing sweeps 30–170 WPM across many seeds, tens of thousands of keystrokes, and must produce zero detections — including at the Sensitive preset.
- Generated paw impacts sweep anchors and contact sizes and must all be caught, within 300 ms for a compact four-key impact.

The unit suite additionally covers the clock conversion, the geometry model, each extracted feature, the grace window in both directions, stuck-key release, undo counting, physical-state reconciliation, context gates, and calibration.

When changing score weights, add a positive cat-like case and a negative human-like case. A detector change is incomplete if it improves one side without protecting the other — the replay tests will say so either way.
