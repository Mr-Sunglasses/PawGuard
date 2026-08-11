# Architecture

PawGuard is a native macOS 14+ menu-bar app built with SwiftUI, AppKit, ApplicationServices, CoreGraphics, and ServiceManagement. `project.yml` is the XcodeGen source of truth; the checked-in `.xcodeproj` is generated output.

## Runtime flow

```text
CGEventTap
   ↓ metadata only
KeyboardEventMonitor
   ↓ KeyboardEventSample
KeyboardEngine
   ├─ CatDetector → DetectionResult
   └─ ProtectionManager → monitoring / locked / cooldown
          ↓ callbacks
       AppState
          ├─ CatOverlayController
          ├─ menu-bar and settings state
          └─ aggregate StatisticsStore
```

## Responsibilities

### AppState

`AppState` is the main-actor coordinator. It owns stores and services, connects engine callbacks to UI state, polls Accessibility trust, updates overlay countdowns, records aggregate statistics, and controls onboarding and settings actions.

### AccessibilityManager

The permission service reads current process trust from macOS, requests the system prompt, opens the Accessibility settings page, and can invoke `tccutil reset Accessibility com.pawguard.app`. The app never treats a cached preference as permission; current operating-system trust is the source of truth.

### KeyboardEventMonitor

The monitor installs a session event tap for key-down, key-up, and modifier-state events. It maps each event to metadata and returns either the original event or `nil`. Returning `nil` only happens while `ProtectionManager` is locked.

### CatDetector

The detector owns a short rolling sample buffer and held-key timestamps. It calculates a confidence score from overlap, physical proximity, burst rate, hold duration, and repeat evidence. Human-pattern exemptions are implemented beside the scoring logic and covered by tests.

### KeyboardEngine and ProtectionManager

`KeyboardEngine` is the decision boundary between detection and suppression. Only a non-modifier key-down with `.cat` confidence can start protection. `ProtectionManager` owns the thread-safe state machine and controls lock expiry, manual unlock, cooldown, and optional activity extension.

### CatOverlayController

The overlay controller hosts a SwiftUI view inside a floating AppKit panel. It appears near the top of the display containing the pointer, joins all Spaces, supports full-screen auxiliary presentation, and can be dragged by its background. Mouse and trackpad input remain available.

## Persistence

| Data | Storage |
| --- | --- |
| Settings and onboarding state | `UserDefaults` |
| Cat profile metadata | `UserDefaults` |
| Aggregate intervention statistics | `UserDefaults` |
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
