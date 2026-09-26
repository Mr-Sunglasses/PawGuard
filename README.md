# PawGuard

PawGuard is a private, native macOS menu-bar utility that recognizes keyboard patterns consistent with a cat walking, sitting, or resting on the keys. When confidence is high, it temporarily pauses keyboard input while leaving the mouse and trackpad available.

Everything runs locally. PawGuard observes only event timing, virtual key codes, overlap, repeat state, modifiers, and approximate physical key positions. It never converts key codes into characters or stores typed content.

## Highlights

- Native SwiftUI and AppKit interface for macOS 14+
- Global keyboard monitoring with a Core Graphics event tap on its own thread
- Scored detection for overlapping keys, cluster density, impact synchrony, rhythm, and long holds
- A confirmation window that withholds borderline input and replays it if it turns out to be you
- Undo for whatever the cat typed before protection engaged
- Learns from your unlocks: nothing leaves the Mac
- Stands down for full-screen games, apps you exclude, and secure input
- Protections against fast human typing, shortcuts, key rollover, and common gaming holds
- Personalized cat profile, local photos, theme, sensitivity, and lock duration
- Multi-display protection overlay with mouse unlock, countdown, and an "It Was Me" button that teaches PawGuard
- Unlock and pause (15 minutes, an hour, or until resumed) from the menu bar
- Emergency unlock with `Control-Option-Command-Escape`
- Explicit Accessibility repair and reset flow
- No network services, analytics, typed-content storage, or machine-learning dependency

## Requirements

- macOS 14 or later
- Xcode
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- An Apple Development signing certificate for persistent Accessibility permission

Install XcodeGen with Homebrew if needed:

```sh
brew install xcodegen
```

## Run PawGuard

Use the signed development runner for normal use:

```sh
make run
```

The helper finds the first available Apple Development identity, regenerates the Xcode project, builds PawGuard, signs the finished app, verifies the signature, and launches it from:

```text
.build/signed/Build/Products/Debug/PawGuard.app
```

If more than one development certificate is installed, select one explicitly:

```sh
security find-identity -v -p codesigning
PAWGUARD_SIGNING_IDENTITY='Apple Development: Your Name (IDENTIFIER)' ./scripts/run-signed.sh
```

Always use the same signing certificate and the unchanged `com.pawguard.app` bundle identifier. macOS associates Accessibility approval with the app's code identity; unsigned or differently signed rebuilds can appear to be a different app.

## First launch

1. Open PawGuard from the signed helper.
2. Create a cat profile and optionally import up to five local photos.
3. Choose **Enable Accessibility**.
4. In System Settings, enable PawGuard under **Privacy & Security → Accessibility**.
5. Return to PawGuard. Onboarding refreshes automatically and enables **Continue** when both permission and keyboard monitoring are ready.
6. Use **Preview Protection Overlay** in Detection settings to check the complete alert without blocking the keyboard.

## Repair Accessibility

If PawGuard is enabled in System Settings but protection remains unavailable:

1. Confirm you launched `.build/signed/Build/Products/Debug/PawGuard.app`, not an unsigned build from another directory.
2. Open **PawGuard Settings → General → Accessibility**.
3. Choose **Reset Accessibility Permission**.
4. Re-enable PawGuard in the System Settings page that opens.
5. Relaunch with `make run` or reinstall with `make install`.

The reset is scoped to PawGuard's bundle identifier and does not modify another app's permission.

## Development

Prepare a checkout, diagnose the environment, and see every command:

```sh
make setup
make doctor
make help
```

The main development loop is:

```sh
make run       # stable signed Debug build + launch
make test      # all tests
make check     # format check + tests + analysis + script validation
```

Install a signed Release build into `/Applications`:

```sh
make install
```

The installer keeps the app at a stable path and uses the same signing identity as `make run`, which prevents developer rebuilds from needlessly changing the identity macOS uses for Accessibility approval.

Useful maintenance commands:

```sh
make permissions
make reset-onboarding
make reset-permission
make logs-follow
make clean
```

See [Development workflow](docs/DEVELOPMENT.md) for every script, environment override, install/reset safety rule, targeted-test syntax, and troubleshooting flow. Unsigned builds remain appropriate for tests and static analysis, but not for validating persistent Accessibility approval.

## Detection and architecture

- [Detection model](docs/DETECTION.md) explains signals, false-positive protections, sensitivity presets, and regression cases.
- [Architecture](docs/ARCHITECTURE.md) describes the app layers, event flow, persisted data, and important implementation boundaries.
- [Development workflow](docs/DEVELOPMENT.md) documents setup, Make targets, signing, installation, packaging, resets, and diagnostics.

The detector does not use the cat's name or photos. Those are presentation-only data and cannot affect whether keyboard input is blocked.

## Privacy and local data

Persisted data is limited to app settings, cat profiles, app-owned photo copies, and aggregate protection statistics. Imported images are normalized and stored under:

```text
~/Library/Application Support/PawGuard/Cats/<profile-id>/
```

PawGuard has no networking layer. Keyboard-event samples remain in a short in-memory rolling window and are discarded as detection advances.

## Project layout

```text
PawGuard/
  App/           Application state and scene setup
  Assets.xcassets/AppIcon.appiconset/
  Cats/          Cat profiles, photos, and message formatting
  Detection/     Scoring rules and rolling event buffer
  Keyboard/      Event tap, event model, geometry, and engine
  Permissions/   Accessibility checks, prompt, and reset
  Protection/    Lock, cooldown, and extension state
  UI/            Menu bar, onboarding, overlay, and settings
Tests/           Detector, engine, profile, and copy regressions
docs/            Architecture, detector, and development documentation
scripts/         Setup, build, install, diagnostics, validation, and maintenance
Makefile         Short developer command surface
project.yml      XcodeGen source of truth
```

## Safety controls

- Click **Unlock Now** in the overlay or **Unlock Keyboard** in the menu bar at any time.
- Choose **It Was Me** when PawGuard locked on your own typing; it learns from that.
- **Pause Protection** from the menu bar when you expect to trip it on purpose.
- Press `Control-Option-Command-Escape` for emergency keyboard unlock.
- Mouse and trackpad input remain active during protection.
- A short cooldown follows every unlock to prevent immediate retriggering.
