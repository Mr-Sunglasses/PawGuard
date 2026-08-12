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

## Signals

The score combines evidence that is unusual for human typing:

| Signal | Meaning |
| --- | --- |
| Simultaneous keys | Several non-modifier keys physically overlap |
| Physical cluster | Held keys occupy a compact keyboard area |
| Rapid cluster | Three or more nearby keys land within 120 ms |
| Rolling cluster | A fast clustered burst includes real key overlap |
| Multi-key hold | Several keys remain held past 0.7 or 1.5 seconds |
| Fast burst | Many unique keys occur inside 0.45 seconds |
| Excessive repeat | Repeats occur while multiple keys remain held |

A burst alone is deliberately weak. This keeps fast sequential human typing below the protection threshold. Rapid-cluster evidence records a compact impact, but three-key input must remain physically held before it can activate protection. A four-key compact impact can activate immediately. Released sequential typing cannot activate from the timer.

PawGuard re-evaluates physically held keys every quarter second. This catches a paw resting silently on the keyboard when macOS does not produce autorepeat events. If macOS interrupts the event tap, the held-key state is cleared before monitoring resumes so stale key state cannot cause a false detection.

Detector state persists across ordinary monitoring timer ticks. It is cleared only for an actual lifecycle boundary such as event-tap interruption, permission loss, protection activation, or the end of cooldown. This allows the 0.7-second and 1.5-second hold rules to accumulate reliably.

## Immediate protection

PawGuard can protect immediately when:

- Six or more non-modifier keys overlap; or
- Five or more clustered keys overlap and the keys are not a recognized intentional control hold.
- Four nearby keys land within 120 ms and remain overlapped with enough combined evidence.

Other patterns must accumulate enough weighted evidence to reach the selected threshold.

## Human-pattern protections

The detector reduces or caps confidence for:

- Purely sequential typing with no overlapping keys
- Command, Control, or Option shortcut chords
- Common two-to-four-key WASD/QE/Space gaming holds
- Arrow-key navigation holds
- Modifier-only events
- Key-up events, which can update state but can never initiate protection
- Released rapid typing, which cannot activate during periodic hold evaluation

The engine enters a three-second cooldown after protection is released. During cooldown, samples are cleared and cannot immediately retrigger the overlay.

## Sensitivity presets

| Preset | Threshold | Intended use |
| --- | ---: | --- |
| Relaxed | 85 | Very fast typists, frequent shortcuts, or gaming |
| Balanced | 70 | Recommended everyday default |
| Sensitive | 55 | Earlier intervention for frequent cat activity |
| Custom | 30–100 | Manual calibration |

Lower thresholds detect weaker patterns but naturally increase false-positive risk. Start with Balanced, use the overlay preview to understand the response, and move to Relaxed if intentional keyboard use is interrupted.

## Regression coverage

The test suite includes:

- Normal typing and very fast sequential typing
- Three-key rollover during fast typing
- Common modifier shortcuts
- Short and extended WASD holds
- A four-key intentional human chord
- Six-key paw presses
- Long clustered paw rests
- Rolling clustered paw patterns
- Compact four-key paw impacts
- Quiet three-key paw rests without autorepeat
- Repeated monitoring timer ticks before a quiet hold matures
- Paw impacts that also happen to press Command, Control, or Option
- Event-tap interruption and stale-held-key recovery
- Key-up events that must not activate protection
- Emergency unlock, cooldown, and activity-based extension

When changing score weights, add a positive cat-like case and a negative human-like case. A detector change is incomplete if it improves one side without protecting the other.
