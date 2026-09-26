# Architecture

PawGuard is a native macOS 14+ menu-bar app built with SwiftUI, AppKit, ApplicationServices, CoreGraphics, and ServiceManagement. `project.yml` is the XcodeGen source of truth; the checked-in `.xcodeproj` is generated output.

## Runtime flow

```text
CGEventTap  (dedicated thread, own run loop)
   ↓ metadata only
KeyboardEventMonitor
   ↓ KeyboardEventSample
KeyboardEngine
   ├─ CatDetector → DetectionFeatures → DetectionResult
   ├─ ProtectionManager → monitoring / grace / locked / cooldown
   └─ KeyboardEventInjector → replayed input, key-up release, undo
          ↓ callbacks (hopped to the main actor)
       ProtectionCoordinator
          ├─ CatOverlayController
          ├─ CalibrationStore
          ├─ DetectionContextProbe
          └─ StatisticsStore
       AccessibilityWatcher
          └─ monitor lifecycle
          ↓
       AppState  (presentation glue for menu bar, settings, onboarding)
```

## Responsibilities

### AppState

`AppState` composes the stores and the two objects that do the work, and exposes them to SwiftUI. It holds no protection logic of its own.

### ProtectionCoordinator

Owns the engine, the monitor, the overlay, and the tenth-of-a-second tick, which runs in the common run-loop modes under a process activity that keeps App Nap away. Each tick re-evaluates a possibly still paw, advances protection state, and drives the overlay countdown. Every lock, however it ends, is wrapped up in one place that records statistics and feeds the calibration store its label. It also owns the user's temporary pause.

### AccessibilityWatcher

Owns Accessibility trust and the monitor's lifecycle. macOS has no direct observer for a permission change, but it posts a distributed notification, and permission is nearly always granted while the user is away in System Settings, so the watcher reacts to that notification and to app activation with a slow two-second fallback poll rather than checking four times a second.

### AccessibilityManager

The permission service reads current process trust from macOS, requests the system prompt, opens the Accessibility settings page, and can invoke `tccutil reset Accessibility com.pawguard.app`. The app never treats a cached preference as permission; current operating-system trust is the source of truth.

### KeyboardEventMonitor

The monitor installs a session event tap for key-down, key-up, and modifier-state events on **its own thread with its own run loop**. On the main run loop every keystroke on the system would be dispatched behind SwiftUI rendering, so a slow frame would delay input machine-wide and a slow enough one would make macOS disable the tap. Timestamps are converted through `MonotonicClock`, and events PawGuard injected itself are recognised by their marker and passed straight through. A tap that cannot be re-enabled after a timeout is rebuilt rather than left silently dead.

### CatDetector and DetectionFeatures

`DetectionFeatures.extract` turns the rolling buffer and held-key set into named measurements — overlap, cluster shape, impact synchrony, hold durations, rhythm, hand alternation, sustained key rate. `CatDetector` scores those features with smooth ramps and the weights in `DetectionWeights`, producing a 0-100 score. Separating the two keeps the score readable and lets features be tested and logged on their own.

### KeyboardEngine and ProtectionManager

`KeyboardEngine` is the decision boundary between detection and suppression, and the single point of serialization: `process` runs on the tap thread while the tick runs on the main actor, so the detector, the protection state, and all event bookkeeping sit behind one recursive lock.

Borderline evidence opens a grace window instead of locking: input is withheld and buffered, and when the window closes the engine either commits to a lock or replays the buffered events. Overwhelming evidence skips the window. On locking, the engine synthesises key-ups for everything applications already saw, so nothing is left stuck down. The tick also re-evaluates held keys, allowing a quiet paw rest to mature without relying on autorepeat. A lock's deadline is also checked on the tap thread with every event, so a late tick can never hold the keyboard past it. The engine records how each lock ended — expired, emergency shortcut, or unlocked — so the coordinator labels it correctly whichever of its two paths notices first.

`ProtectionManager` owns the thread-safe state machine — monitoring, grace, locked, cooldown — and controls lock expiry, manual unlock, and optional activity extension. Its wall clock is injectable, which is how the grace window is tested without waiting.

If macOS disables the event tap because of a timeout or user-input interruption, `KeyboardEventMonitor` clears detector state before re-enabling the tap. This prevents keys whose key-up events were missed during the interruption from remaining falsely held.

### CalibrationStore and DetectionContextProbe

`CalibrationStore` turns unlock behaviour into a threshold offset and a personal chord allowlist, all stored locally as key codes and scores. `DetectionContextProbe` reports secure input, the frontmost app, and whether it is full-screen, which the coordinator turns into a suppression decision each tick.

### CatOverlayController

The overlay controller hosts a SwiftUI view inside a floating AppKit panel. It appears near the top of the display containing the pointer, joins all Spaces, and supports full-screen auxiliary presentation. It never becomes key — it appears precisely when a cat is on the keyboard, and taking focus would aim that input at PawGuard — and is not draggable, since a cat on the trackpad would otherwise push it off screen. Mouse and trackpad input remain available, and the panel offers to undo whatever the cat typed before protection engaged.

## Persistence

| Data | Storage |
| --- | --- |
| Settings and onboarding state | `UserDefaults`, decoded leniently so fields added by a newer build take their defaults instead of discarding everything saved |
| Cat profile metadata | `UserDefaults` |
| Aggregate intervention statistics | `UserDefaults` |
| Calibration profile and detection shapes | `UserDefaults`, key codes and scores only |
| Normalized cat photos | Application Support |
| Keyboard samples | Memory only, maximum 1.2-second rolling window |

Photo paths point to app-owned normalized copies. The app does not depend on the original selected file remaining available.

## Signing and Accessibility

Accessibility authorization belongs to the running app's macOS code identity. `scripts/build.sh --signed` therefore builds into a stable location, signs the complete app with the selected Apple Development certificate, and verifies the designated requirement. `scripts/run-signed.sh` launches that development product, while `scripts/install.sh` safely replaces the copy in `/Applications` with the same signed identity.

Unsigned builds remain available for CI-style compilation, tests, and analysis, but should not be used to validate permission persistence.

## Extension points

- Additional active cat profiles can be exposed without changing detector inputs.
- New detector signals should extend `DetectionSignal` and include positive and negative tests.
- A production distribution pipeline can replace development signing without changing the Accessibility manager.
- UI presentation can evolve independently because the detector emits metadata-only `DetectionResult` values.

Camera-based detection, networking, cloud storage, and typed-content capture are intentionally outside the current architecture.
