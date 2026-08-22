# Detection model

PawGuard uses deterministic local heuristics. It does not inspect characters, words, applications, windows, documents, clipboard data, or cat photos.

## Input metadata

Each in-memory sample contains only:

- Virtual key code
- Key down, key up, or modifier-state event
- Monotonic timestamp
- Auto-repeat state
- Modifier flags

Samples are retained in a rolling four-second buffer. The timing signals read the most recent 1.2 seconds of it; the contact and autorepeat signals read the whole thing, because a paw that touches down, lifts, and comes down again a few keys over is one gesture spread over seconds. The detector also tracks which non-modifier keys are currently held and when each hold began.

### Timekeeping

`CGEvent.timestamp` is expressed in mach absolute time units, not nanoseconds. On Apple Silicon one unit is 125/3 ns, so dividing the raw value by a billion yields a clock roughly 41 times slow and unrelated to `ProcessInfo.systemUptime`. `MonotonicClock` converts through `mach_timebase_info` so event stamps and timer evaluations share one clock, and falls back to the current time if a stamp is missing or implausible. Every window in `DetectionRules` is in real seconds.

## Geometry

Every key macOS can report has an approximate physical position in key units, including the function row, the navigation cluster, the numeric keypad, and the arrows. Virtual key codes are physical rather than logical, so one table serves QWERTY, AZERTY, and Dvorak alike; only the enclosure type (ANSI, ISO, JIS) changes the arrangement, and that is detected at launch.

Compactness is a density measure, not a bounding box. Keys one unit apart score 1.0; the loose limit grows with the square root of the key count, because a paw covering more keys necessarily covers more area. Held keys are grouped into physically contiguous clusters by single linkage, so a cat lying across the keyboard with its chest on one area and a paw on another is recognised as two clusters rather than dismissed as scattered.

Two keys count as a cluster when they are physically touching. Every clustering test used to need three, which made the smallest real contact there is — a kitten's pad, which covers two keys and no more — invisible to the geometry entirely. Two keys are much weaker evidence than three, and the ramps say so; refusing to see them at all was a different thing.

## Signals

The score combines evidence that is unusual for human typing:

| Signal | Meaning |
| --- | --- |
| Simultaneous keys | Several non-modifier keys physically overlap |
| Physical cluster | Held keys occupy a compact area, weighted by how tightly they are packed |
| Rapid cluster | Three or more nearby keys land within 120 ms |
| Impact synchrony | Several keys land within 30 ms, closer than fingers roll |
| Multi-cluster | Two separate compact groups are held at once |
| Multi-key hold | Three keys stay down together well past a keystroke |
| Paw contact | Two neighbouring keys held down together — the smallest contact there is |
| Paw touches | Several separate settled touches in a row: a cat crossing the keyboard |
| Improbable combination | Function-row or structural keys held together with letters |
| Repeated impact | Several separate compact impacts inside one window |
| Sustained hold | One key nobody leans on, held or autorepeating far past a keystroke |
| Excessive repeat | Several different such keys each fire a run of autorepeats |
| Sequential locality | Successive presses keep landing under the same paw |
| Fast burst | Many unique keys occur inside 0.45 seconds |
| Non-human rate | Sustained unique-key rate above what fingers reach |

Every term is a smooth ramp rather than a step, so one extra key shifts the score by a few points instead of tens. All weights live in `DetectionWeights`.

### Combining the evidence

Signals combine as a noisy-OR, not as a sum. Each term contributes an independent probability that this is a paw, and the score is the probability that at least one of them is right:

```
score = 100 × (1 − Π(1 − pᵢ))
```

Summing and clamping was the earlier design, and it had a specific failure: the weights sum to well over 100, so an ordinary four-key impact already pinned the scale at its maximum. Every grade of evidence above "modest paw" collapsed into the same number, and `immediateScore` — meant for evidence beyond anything a human produces — became the ordinary case rather than the exception. Measured on the generated impact corpus, 82% of detections reached it and skipped the confirmation window.

Noisy-OR fixes that by construction. The score cannot leave 0-100 whatever the weights are, each additional signal has diminishing returns instead of pushing the total past the ceiling, and reaching 95 genuinely requires most signals to fire at once. On the generated impact corpus no ordinary three-to-five-key impact reaches `immediateScore` any more, so every one of them goes through the confirmation window, while a whole cat settling across the keyboard scores 99 and skips it.

Signals that measure the same physical thing two ways are combined with `max` inside one term rather than added as two, because noisy-OR assumes independence and would otherwise count one held key twice. That is why hold duration and autorepeat volume share a term, and why a two-key contact stops contributing as the cluster signals take over describing the same paw — without that, an ordinary impact sailed past `immediateScore` and lost its confirmation window.

Because the combination rule changed, the weights were retuned against the replay corpus rather than carried over; they are evidence strengths on a 0-100 scale, not points added to a total.

### Contact credibility

Overlap on its own says very little. A paw sits; fingers pass through. The same three keys mean one thing when they overlap for forty milliseconds and another when they overlap for a second, so every overlap and clustering term is scaled by how credible the contact is rather than counted flat.

A contact earns its weight three ways, and the strongest wins:

- **It arrived together.** A paw puts its keys down inside a few dozen milliseconds. A typist who happens to have four keys down took a quarter of a second to get there and is already lifting the first. This is the only measure available at the instant a paw lands flat — which is exactly when the detector most wants to act, because nothing has had time to persist yet.
- **It has lasted.** Measured as how long *every* held key has been down together, not how many are down. A typist reaches five keys at once only in passing, with the fifth landing as the first leaves, so the depth of the overlap stays near zero however high the count climbs.
- **Its keys individually outlasted a keystroke.** A cat stepping onto the keys one at a time leaves each one down. The keys arrive at typing speed and the newest has only just landed, so neither of the other two measures sees it — but two keys down past a quarter of a second is not something typing produces, because reaching the second means the first is already on its way back up.

Impact synchrony is the one shape signal with no credibility gate. Three keys inside thirty milliseconds is arithmetically out of a typist's reach — the fastest human digraph is twice that — so it can carry the fast path for a paw slamming down flat.

This is what made it possible to loosen the model for small contacts without paying for it in false positives. On generated typing at 90-170 wpm with heavy-handed 90-220 ms hold times — a corpus the previous model locked the keyboard on 39 times out of 90 at the Sensitive preset — the current model triggers zero times at every preset.

### Signals a cat produces without overlapping keys

Overlap is not the only shape a cat makes, and several signals exist for the shapes that have none.

**Repeated impact** counts distinct compact impacts rather than measuring one. A cat crossing the keyboard sets a paw down, lifts it, and sets it down again a few keys over. Each touch on its own is weak — three keys held half a second is under every hold threshold — but a run of them is not something fingers do. This is what `cat-walking` is made of, and it is the signal that catches it.

**Paw touches** counts separate settled contacts across the whole four-second window, where a settled contact is either two neighbouring keys held together past the length of rollover, or one key nobody leans on held past three quarters of a second.

A lone key only counts when the touch immediately before or after it in time landed within a paw's reach. On its own, one key at a time held long enough to autorepeat is indistinguishable from slow deliberate typing — a hesitant typist, or one working around a motor impairment, produces exactly that shape, and counting it unconditionally locked the keyboard on every one of them. What separates the two is locality: a paw pads around one patch of keyboard, while the letters a person is hunting for are wherever the words take them.

**Sustained hold** measures the longest hold on a key nobody leans on. A paw resting on one key produces no overlap at all, so every clustering signal is blind to it.

It is measured two ways, and the stronger wins. Duration is the physical truth, and is what carries the signal for someone who has key repeat switched off. Autorepeat volume is what matters in practice: a paw parked on a letter fires a repeat every few dozen milliseconds, and every one of them is a character the user has to delete afterwards. Counting the repeats is both better evidence and a direct measure of the damage being done, and it arrives seconds before duration alone becomes conclusive — a key left down used to take twelve to fourteen seconds to catch, several hundred characters in, and now takes about three.

The two are combined with `max` rather than as two independent terms. With key repeat on, one is roughly the other divided by the repeat interval, so treating them as separate evidence would double-count the same held key and drag the score up simply by looking at it twice.

Two protections keep it quiet while somebody holds a key on purpose. Keys people genuinely lean on carry no resting evidence at all: delete, the arrows, space, page keys, home and end, tab, return, the movement keys, and the punctuation people hold to rule off a line — `-`, `=`, `.`, `,`, `/`, `\`, and the grave key. Naming a key here only blinds this one signal; a paw parked on it is still caught by the contact and cluster signals, which cost nothing in false positives. For everything else, evidence ramps in above the longest stretch anyone types by hand — "noooo", "hmmm" — and is decisive by three dozen repeats, which nobody produces on purpose.

**Sequential locality** is the fraction of successive presses that land within a paw's reach of each other. Human typing wanders across the keyboard between keystrokes; a paw padding across it does not. This one is deliberately weak. Recorded human sessions do produce local runs — short words sit under one hand — so it raises suspicion and eases the sequential exemption below, rather than deciding anything on its own.

Speed and rhythm are gated on real overlap. Sequential speed alone is how humans type fast, so a burst on its own stays well below the threshold. Key rate is measured over the full rolling window as a sustained rate, not as an instantaneous burst.

## Two-stage protection

Crossing the threshold does not lock the keyboard outright. Borderline evidence opens a grace window of 180 ms during which input is withheld and buffered rather than delivered. When the window closes the detector is re-evaluated:

- Still cat-like: the buffered events are discarded and protection engages.
- No longer cat-like: the buffered events are replayed in order and monitoring resumes.

Being wrong therefore costs a barely perceptible delay instead of a locked keyboard, which is what allows the thresholds to sit where they do. Evidence beyond anything a human produces (a score of 95 or more) skips the window entirely — in practice a cat settling its weight across two separate patches of keyboard, not a single paw touching down. The window can be turned off in Settings.

## Held-key tracking

The engine re-evaluates held keys every tenth of a second, so a paw that has settled and stopped producing events is acted on within a tick rather than within a quarter second. When an event tap is interrupted or disabled, the detection state and held keys are safely reset, and uncorroborated stale holds older than 30 seconds expire on their own.

## Releasing what applications already saw

Keys delivered before protection engages would otherwise stay stuck down for the whole lock, because their key-ups are withheld along with everything else. On locking, PawGuard synthesises a key-up for every key an application saw go down, and for any modifier physically held at that moment. Conversely, a key-up whose key-down was withheld is withheld too, so no application sees a release it never saw pressed. Injected events carry a marker so PawGuard's own tap ignores them.

## Human-pattern protections

The detector reduces or caps confidence for:

- Contacts inside a chord the user holds on purpose. The gaming and arrow clusters, and anything they have taught PawGuard to ignore, are excluded during feature extraction rather than in the score, because the contact signals look back over several seconds — a released WASD hold would otherwise sail straight past an exemption that only ever inspects the keys held right now
- Sequential typing that also wanders across the keyboard the way typing does. Sequential presses that stay under one paw are damped far less: a cat crossing the keyboard one key at a time is sequential too, so spatial spread, not sequence alone, is what earns the exemption
- A key that has simply been sitting down is not treated as sequential at all, so a resting paw is not forgiven as typing
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

Dismissing a lock within six seconds is treated as a labelled false positive: the threshold offset rises, and a chord that has been wrong twice is added to a personal allowlist. Only chords of four keys or fewer are learnable, because an allowed set exempts every subset of itself — learning a wide one would quietly exempt a whole region of the keyboard, and any paw landing inside it. A lock that runs its course counts as confirmation and decays the offset back towards the user's own setting. Passive observation of how often this user genuinely overlaps three or more keys raises the bar for heavy rollers. Records contain key codes, scores, and signal names — never characters — and never leave the Mac. All of it can be reset in Settings.

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
- Slow deliberate typing — one key at a time, each held long enough to autorepeat — must produce zero detections at the Sensitive preset. This is the hardest human pattern to tell from a cat padding across the keys, and the one that punishes a hesitant typist if the paw-touch signal is allowed to count a lone key on its own.
- Generated paw impacts sweep anchors and contact sizes and must all be caught, within 300 ms for a compact four-key impact. Fewer than half may reach `immediateScore`, so the confirmation window keeps covering the ordinary case.
- Single-key holds are covered from both sides: a letter left down must be caught within four seconds, a letter stretched for effect for up to a second and a half must not, and delete, arrows, space, tab, return, the movement keys and the line-ruling punctuation must stay silent held for ten to thirty.
- Kitten-sized contacts have their own cases, because they are what the three-key floor used to hide: two neighbouring keys held together must be caught within a second and a half at every anchor tried, and a cat crossing the keyboard in small local touches must be caught in the large majority of generated walks.

The unit suite additionally covers the clock conversion, the geometry model, each extracted feature, the grace window in both directions, stuck-key release, undo counting, physical-state reconciliation, context gates, and calibration.

When changing score weights, add a positive cat-like case and a negative human-like case. A detector change is incomplete if it improves one side without protecting the other — the replay tests will say so either way.
