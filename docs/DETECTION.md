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
| Rolling cluster | A fast clustered burst includes real key overlap |
| Multi-key hold | Several keys remain held past 0.7 or 1.5 seconds |
| Fast burst | Many unique keys occur inside 0.45 seconds |
| Excessive repeat | Repeats occur while multiple keys remain held |

A burst alone is deliberately weak. This keeps fast sequential human typing below the protection threshold. Rolling-cluster evidence requires at least two overlapping keys, so a fast typist releasing each key normally is not treated as a paw.

## Immediate protection

PawGuard can protect immediately when:

- Six or more non-modifier keys overlap; or
- Five or more clustered keys overlap and the keys are not a recognized intentional control hold.

Other patterns must accumulate enough weighted evidence to reach the selected threshold.

## Human-pattern protections

The detector reduces or caps confidence for:

- Purely sequential typing with no overlapping keys
- Command, Control, or Option shortcut chords
- Common two-to-four-key WASD/QE/Space gaming holds
- Arrow-key navigation holds
- Modifier-only events
- Key-up events, which can update state but can never initiate protection

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
- Key-up events that must not activate protection
- Emergency unlock, cooldown, and activity-based extension

When changing score weights, add a positive cat-like case and a negative human-like case. A detector change is incomplete if it improves one side without protecting the other.
