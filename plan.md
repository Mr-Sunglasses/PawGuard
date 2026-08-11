# PawGuard — Native macOS Cat Keyboard Protection

## 1. Product concept

**PawGuard** is a native macOS menu-bar app that detects keyboard input patterns likely caused by a cat walking, sitting, or pressing paws on a MacBook keyboard.

The app is generic: during onboarding, the user creates a profile for their own cat by providing:

- Cat name
- One or more cat photos
- Optional preferred accent/theme
- Optional lock duration and sensitivity

PawGuard then personalizes the app around that cat.

Examples:

- “Migi is typing 🐾”
- “Luna has taken over the keyboard.”
- “Tiny paws detected — Milo mode activated.”
- “Oscar is helping with your code.”

The detection engine itself must **not depend on the cat photos**. Photos and names are used for personalization, UI, notifications, and future camera-based detection.

---

# 2. Primary goal

Build a native macOS utility that:

1. Monitors global keyboard events.
2. Detects physical typing patterns that are unlikely to be normal human typing.
3. Temporarily suppresses keyboard input when cat-like activity is detected.
4. Displays a polished animated overlay personalized with the user's cat.
5. Keeps mouse/trackpad input available.
6. Provides an emergency keyboard shortcut and mouse unlock.
7. Stores no typed content.
8. Runs entirely locally.
9. Supports multiple cat profiles in the architecture, even if V1 exposes only one active cat at a time.

---

# 3. Technology stack

Use:

```text
Language: Swift
UI: SwiftUI
macOS integration: AppKit
Keyboard interception: CoreGraphics CGEventTap
Permissions: macOS Accessibility
Storage: UserDefaults / AppStorage for settings
Local image storage: Application Support directory
Architecture: service-oriented / lightweight MVVM
Minimum target: macOS 14+
```

Do not use:

```text
Electron
Python
Node
Web servers
Cloud APIs
Machine learning libraries in V1
```

The result should feel like a small, polished native Mac utility.

---

# 4. Branding

Use a generic product name such as:

```text
PawGuard
```

The app should not be hardcoded around one specific cat.

Avoid code or UI names such as:

```text
MigiGuard
MigiDetector
MigiProfile
```

Use generic names:

```text
CatProfile
CatDetector
CatAvatar
ActiveCat
PawOverlay
```

The user's cat name should be injected dynamically.

---

# 5. Cat profile system

Create a model similar to:

```swift
struct CatProfile: Codable, Identifiable {
    let id: UUID
    var name: String
    var photoPaths: [String]
    var selectedAvatarIndex: Int
    var createdAt: Date
}
```

For V1:

- Support one active cat profile in the UI.
- Keep the model capable of supporting multiple cats later.
- Cat name must be editable.
- Photos must be replaceable or removable.
- At least one photo is recommended but not mandatory.
- If no photo is uploaded, use a tasteful generic cat/paw illustration.

Do not embed user-provided photos directly into source code or `Assets.xcassets`.

---

# 6. Cat photo onboarding

During onboarding ask:

```text
What's your cat's name?
```

Then:

```text
Add a photo of <CatName>
```

Allow:

- Drag and drop
- macOS file picker
- JPG
- JPEG
- PNG
- HEIC

Allow the user to upload multiple photos, for example 1–5.

Suggested onboarding sequence:

```text
Welcome
   ↓
Cat name
   ↓
Cat photos
   ↓
Choose profile photo
   ↓
Accessibility permission
   ↓
Sensitivity
   ↓
Ready
```

Example:

```text
Meet your keyboard guardian

Cat name:
[ Migi                      ]

[ Continue ]
```

Then:

```text
Add some photos of Migi

These photos are used only to personalize PawGuard.
They stay on this Mac.

[ Choose Photos ]

You can skip this and add photos later.
```

---

# 7. Local photo storage

User cat photos must remain local.

Store them under the app's Application Support directory, for example conceptually:

```text
~/Library/Application Support/PawGuard/Cats/<UUID>/
```

Do not depend on the original user-selected file continuing to exist.

When a user imports an image:

1. Load it locally.
2. Normalize orientation.
3. Create an optimized local copy.
4. Generate a thumbnail/avatar version.
5. Store only the app-owned copies.

Recommended generated variants:

```text
avatar_256
preview_1024
```

Avoid retaining unnecessarily huge originals unless needed.

No photo uploads to a server.

---

# 8. Cat avatar preparation

After photos are selected, show a simple avatar picker.

Example:

```text
Choose <CatName>'s profile photo

[ Photo 1 ] [ Photo 2 ] [ Photo 3 ]

                    ✓
```

The app may automatically center-crop the selected image into a square preview, but the original local photo should not be destructively modified.

If practical, allow simple pan/zoom crop adjustment.

V1 does not need automatic background removal.

---

# 9. Dynamic personalization

Never hardcode notification strings with a specific cat name.

Use a message formatter:

```swift
enum CatMessage {
    static func detected(catName: String) -> String
    static func released(catName: String) -> String
}
```

Possible messages:

```text
<CatName> is typing! 🐾

Tiny paws detected.

<CatName> has taken over the keyboard.

Keyboard occupied by <CatName>.

<CatName> would like to contribute.

A tiny programmer has appeared.

<CatName> is reviewing your code.
```

Use the cat's name in most messages, but not necessarily every one.

Keep copy short and calm.

---

# 10. Personalization theme

Derive the product experience from the user's cat without making the app visually noisy.

Use:

- User-selected cat avatar
- Cat name
- Subtle paw animations
- Soft native macOS materials
- Optional accent selection

For V1, provide these optional accent themes:

```text
Automatic
Pink
Mint
Blue
Lavender
Orange
Monochrome
```

Do not attempt automatic color extraction from photos unless trivial to implement cleanly.

This can be added later.

---

# 11. Privacy requirement

PawGuard must **not become a keylogger**.

Never store:

```text
typed characters
words
sentences
clipboard contents
passwords
text-field contents
application contents
```

The detection system should use only ephemeral metadata such as:

```swift
timestamp
virtualKeyCode
eventType
isAutoRepeat
modifierFlags
keysCurrentlyHeld
```

Virtual key codes may exist temporarily in memory for physical-layout analysis, but must never be persisted to disk.

Do not convert keyboard events into Unicode characters.

Persistent statistics may include only aggregate information such as:

```text
Cat detections
Blocked key events
Total protection time
Last detection timestamp
False-positive feedback
```

---

# 12. Suggested project structure

```text
PawGuard/
│
├── App/
│   ├── PawGuardApp.swift
│   └── AppState.swift
│
├── Cats/
│   ├── CatProfile.swift
│   ├── CatProfileStore.swift
│   ├── CatPhotoManager.swift
│   └── CatMessageFormatter.swift
│
├── Keyboard/
│   ├── KeyboardEventMonitor.swift
│   ├── KeyboardEvent.swift
│   ├── KeyboardGeometry.swift
│   ├── KeyboardState.swift
│   └── KeyboardBlocker.swift
│
├── Detection/
│   ├── CatDetector.swift
│   ├── DetectionScore.swift
│   ├── DetectionRules.swift
│   └── RollingEventBuffer.swift
│
├── Protection/
│   ├── ProtectionManager.swift
│   └── ProtectionTimer.swift
│
├── Permissions/
│   └── AccessibilityManager.swift
│
├── UI/
│   ├── MenuBar/
│   │   └── MenuBarView.swift
│   │
│   ├── Overlay/
│   │   ├── CatOverlayController.swift
│   │   ├── CatDetectedView.swift
│   │   ├── CountdownRing.swift
│   │   └── PawAnimation.swift
│   │
│   ├── Onboarding/
│   │   ├── WelcomeView.swift
│   │   ├── CatNameView.swift
│   │   ├── CatPhotoImportView.swift
│   │   ├── AvatarPickerView.swift
│   │   ├── PermissionView.swift
│   │   └── SensitivitySetupView.swift
│   │
│   ├── Settings/
│   │   ├── SettingsView.swift
│   │   ├── CatProfileSettingsView.swift
│   │   ├── DetectionSettingsView.swift
│   │   ├── AppearanceSettingsView.swift
│   │   └── StatisticsView.swift
│   │
│   └── Shared/
│       └── CatAvatarView.swift
│
├── Models/
│   ├── Settings.swift
│   └── Statistics.swift
│
└── Tests/
    ├── CatDetectorTests.swift
    ├── KeyboardPatternTests.swift
    └── CatProfileStoreTests.swift
```

Do not over-engineer this exact folder structure if a cleaner implementation is obvious.

---

# 13. Keyboard event interception

Implement a global active keyboard event tap using CoreGraphics.

Observe:

```text
keyDown
keyUp
flagsChanged
```

Mouse and trackpad events must never be blocked.

Track:

```swift
Set<CGKeyCode> currentlyPressedKeys
```

and maintain a short rolling event buffer.

Example:

```swift
struct KeyboardEventSample {
    let keyCode: CGKeyCode
    let timestamp: TimeInterval
    let type: EventType
    let isRepeat: Bool
    let modifiers: CGEventFlags
}
```

Keep approximately the last:

```text
1.5 seconds
```

of relevant event metadata.

Keep the event-tap callback extremely lightweight.

Do not animate UI, perform disk writes, or do expensive work inside the event callback.

---

# 14. Detection philosophy

Do not determine whether the typed sequence is meaningful language.

Do not analyze:

```text
words
spelling
source code
sentences
```

Instead detect **physical keyboard behavior**.

Human typing is generally sequential.

A cat paw is more likely to:

```text
press many keys at nearly the same time
hold several neighboring keys
create overlapping key-down events
generate dense bursts
rest across clusters of keys
```

Create a confidence score from `0...100+`.

---

# 15. Detection windows

Use configurable constants:

```text
SIMULTANEOUS_WINDOW = 120 ms
FAST_BURST_WINDOW    = 450 ms
GENERAL_WINDOW       = 1200 ms
HOLD_THRESHOLD       = 700 ms
```

Avoid magic numbers spread throughout the implementation.

---

# 16. Rule A — simultaneous non-modifier keys

Count unique non-modifier keys pressed within roughly 120 ms.

Suggested scoring:

```text
2 keys = +4
3 keys = +18
4 keys = +35
5 keys = +60
6+ keys = immediate high-confidence detection
```

Normal modifier combinations should not be treated the same way.

Examples that must not trigger merely because multiple keys are down:

```text
Command + C
Command + Shift + P
Shift + A
Control + Option + Escape
```

---

# 17. Rule B — keys held simultaneously

Track currently held non-modifier keys.

Suggested scoring:

```text
2 held = +5
3 held = +20
4 held = +40
5+ held = +65
```

This catches a paw resting across multiple keys.

---

# 18. Rule C — extremely fast burst

Inside approximately 450 ms, count distinct non-modifier key-down events.

Suggested:

```text
5 keys = +10
7 keys = +25
9 keys = +40
12+ keys = +60
```

Never rely on this signal alone because some users type very quickly.

---

# 19. Rule D — physical clustering

Create an approximate physical map of a MacBook ANSI keyboard.

Conceptually:

```text
ESC  1 2 3 4 5 6 7 8 9 0 - =
     Q W E R T Y U I O P [ ]
      A S D F G H J K L ; '
       Z X C V B N M , . /
```

Represent relevant keys as approximate coordinates:

```swift
struct KeyPosition {
    let row: Int
    let x: Double
}
```

Determine whether several pressed keys occupy a compact physical area.

Suggested score:

```text
3-key tight cluster = +10
4-key tight cluster = +25
5+ tight cluster    = +40
```

Keep keyboard geometry isolated so alternative keyboard layouts can be supported later.

---

# 20. Rule E — multi-key hold

Suggested scoring:

```text
2+ keys > 700 ms  = +10
3+ keys > 700 ms  = +25
3+ keys > 1500 ms = +40
```

A single long-held key must not trigger protection.

Users may intentionally hold keys such as:

```text
W
Space
Delete
Arrow keys
```

---

# 21. Autorepeat

Autorepeat is weak evidence by itself.

A single repeating key should contribute little or nothing.

Multiple repeating held keys combined with overlapping presses can increase confidence.

Never lock solely because one key repeats.

---

# 22. Human-typing negative signal

Reduce the score when activity looks clearly human.

For example, if:

```text
maximum simultaneous non-modifier keys <= 1
keypresses are mostly sequential
no physical clusters exist
```

apply approximately:

```text
-15
```

This helps protect fast typists from false detections.

---

# 23. Detection threshold

Default:

```text
CAT_DETECTION_THRESHOLD = 70
```

Example cat-like input:

```text
4 simultaneous keys        +35
4-key physical cluster      +25
high burst density          +20
                            ---
                             80

=> DETECT
```

Example fast human typing:

```text
fast burst                  +20
no simultaneous cluster       0
human typing adjustment     -15
                            ---
                              5

=> DO NOTHING
```

---

# 24. Immediate high-confidence detection

Examples:

```text
6+ non-modifier keys pressed nearly simultaneously
```

or:

```text
5 simultaneous keys
+
tight physical cluster
```

may immediately trigger protection.

---

# 25. Detector result model

Use something similar to:

```swift
struct DetectionResult {
    let score: Int
    let signals: Set<DetectionSignal>
    let confidence: DetectionConfidence
}
```

Possible signals:

```swift
enum DetectionSignal {
    case simultaneousKeys
    case fastBurst
    case physicalCluster
    case multiKeyHold
    case excessiveRepeat
}
```

Do not expose actual pressed keys in UI or persistent logs.

---

# 26. Protection state machine

Use a single authoritative state model:

```swift
enum ProtectionState {
    case monitoring
    case suspicious(score: Int)
    case locked(until: Date)
    case cooldown(until: Date)
}
```

Avoid multiple independent booleans that can become inconsistent.

---

# 27. Trigger behavior

When score reaches the detection threshold:

1. Suppress the triggering event if possible.
2. Enter protected state.
3. Suppress subsequent keyboard events.
4. Keep mouse and trackpad usable.
5. Show personalized cat overlay.
6. Start protection timer.
7. Update aggregate statistics.

State flow:

```text
MONITORING
    ↓
SUSPICIOUS
    ↓
CAT DETECTED
    ↓
PROTECTED
    ↓
COOLDOWN
    ↓
MONITORING
```

---

# 28. Keyboard blocking

While protected:

```swift
ProtectionState == .locked(...)
```

keyboard events should be consumed rather than forwarded.

Continue observing blocked keyboard metadata internally so activity can extend the protection timer.

Do not block mouse or trackpad events.

---

# 29. Lock duration

Default:

```text
20 seconds
```

Available options:

```text
10 seconds
20 seconds
30 seconds
45 seconds
60 seconds
```

---

# 30. Extend-on-activity

This should be enabled by default.

If keyboard activity continues while locked, extend or reset the lock.

Recommended behavior:

```text
If a blocked key event occurs:
remainingTime = max(remainingTime, 8 seconds)
```

For clearly suspicious bursts while already locked, resetting to the full configured lock duration is acceptable.

Goal:

```text
Cat remains on keyboard
        ↓
keyboard remains protected
        ↓
cat stops pressing keys
        ↓
countdown completes
        ↓
keyboard unlocks
```

---

# 31. Emergency unlock

Always support:

```text
Control + Option + Command + Escape
```

When detected during protection:

1. Unlock keyboard immediately.
2. Dismiss overlay.
3. Clear event buffer.
4. Enter approximately 3 seconds of cooldown.

Also provide a large clickable:

```text
Unlock Now
```

button.

Trackpad and mouse must remain usable during protection.

---

# 32. Cooldown

After unlocking:

```text
3 seconds
```

During cooldown:

- Keyboard works normally.
- Detection buffer is cleared.
- Detector does not immediately retrigger.

---

# 33. Accessibility onboarding

PawGuard requires macOS Accessibility permission.

Onboarding should explain:

```text
PawGuard needs Accessibility permission so it can detect
and temporarily block accidental keyboard input.

Your typing is never recorded.
Your cat's photos stay on this Mac.
```

Button:

```text
Enable Accessibility
```

Once available:

```text
✓ Accessibility Enabled
```

Never display “Protected” when the required permission is unavailable.

---

# 34. Menu-bar experience

PawGuard should primarily live in the macOS menu bar.

Example:

```text
┌────────────────────────────────┐
│  [Cat Avatar]  PawGuard        │
│                                │
│  ● Protected                   │
│  Watching for <CatName>'s paws │
│                                │
│  Interventions             12  │
│  Keys blocked             184  │
│                                │
│  Sensitivity        Balanced   │
│                                │
│  [ Test Cat Mode ]             │
│                                │
│  Cat Profile                   │
│  Settings                      │
│  Quit PawGuard                 │
└────────────────────────────────┘
```

If no cat profile exists:

```text
Watching for tiny paws
```

---

# 35. Personalized detection overlay

Display a floating panel near the top-center of the active display.

Suggested size:

```text
380 × 180
```

Style:

```text
rounded corners
macOS material / glass effect
soft shadow
subtle border
cat avatar
paw animation
```

Example:

```text
╭──────────────────────────────────────╮
│                                      │
│       🐾      [ Cat Avatar ]         │
│                                      │
│           Migi is typing!            │
│                                      │
│      Keyboard protected   18s        │
│                                      │
│            [ Unlock Now ]            │
│                                      │
╰──────────────────────────────────────╯
```

With another user's profile it automatically becomes:

```text
Luna is typing!
```

or:

```text
Milo has taken over the keyboard.
```

No code change should be required.

---

# 36. Overlay fallback without photo

If the user skips photo upload, use a polished generic avatar:

```text
cat head
paw
or simple cat silhouette
```

The rest of the UI should still use the provided cat name.

Example:

```text
Oscar is typing 🐾
```

---

# 37. Overlay animations

Entrance sequence around 500 ms:

```text
0 ms
panel scale 0.92 → 1.0

0–250 ms
opacity 0 → 1

100–400 ms
small paw moves into view

250 ms
paw taps a keyboard key

250–450 ms
key compresses and rebounds

400 ms
2–3 subtle paw prints appear

500 ms
animation settles
```

After that, only subtle animation should remain.

The cat avatar may have a very gentle breathing/pulse effect.

Do not continuously animate the whole interface.

---

# 38. Countdown UI

Display remaining time with a circular progress ring.

Example:

```text
   17
  sec
```

Animate smoothly.

Under 5 seconds, add slightly stronger but calm emphasis.

Do not use alarming danger colors.

This is not an error condition.

---

# 39. Unlock animation

When protection ends:

```text
<CatName> has left the keyboard ✨
```

Possible animation:

```text
paw slides away
lock icon morphs to checkmark
overlay fades upward
```

Duration:

```text
600–800 ms
```

---

# 40. Reduce Motion

Respect the user's macOS Reduce Motion preference.

When enabled:

- Remove bounce and slide effects.
- Use simple fades.
- Keep all functionality identical.

---

# 41. Settings

Provide:

```text
General
Cat Profile
Detection
Appearance
Statistics
About
```

## General

```text
Start PawGuard at login
Show protection overlay
Play protection sound
Lock duration
Extend lock on continued activity
```

## Cat Profile

```text
Cat name
Profile photo
Manage photos
Replace photo
Remove photo
```

Future-ready:

```text
Add another cat
```

This control may be disabled or omitted in V1 if multi-cat UI is not implemented.

## Detection

Presets:

```text
Relaxed
Balanced
Sensitive
Custom
```

Default:

```text
Balanced
```

Suggested thresholds:

```text
Relaxed    85
Balanced   70
Sensitive  55
```

## Appearance

```text
Theme
Overlay style
Show cat photo
Animation intensity
```

---

# 42. Test Cat Mode

Add:

```text
Test Cat Mode
```

When activated:

1. Do not disable the keyboard.
2. Show the real overlay.
3. Use the current cat's name and avatar.
4. Play entrance animation.
5. Demonstrate countdown.
6. Demonstrate unlock animation.

This allows the user to preview personalization safely.

---

# 43. Developer detector debug view

Development builds should provide metadata such as:

```text
Current score          34
Keys currently held     2
450 ms burst count      4
Physical cluster       no
Multi-key hold         yes
Threshold               70
```

Never show typed characters.

---

# 44. Optional calibration mode

Add later or as a development feature:

```text
Calibrate My Typing
```

For approximately 30 seconds, collect only anonymous timing characteristics:

```text
average key interval
95th percentile typing rate
maximum simultaneous keys
average hold duration
```

Do not store key identities or typed content.

Calibration can later adjust thresholds for a specific user.

It should not block V1.

---

# 45. Statistics

Store aggregate statistics:

```swift
struct PawGuardStats {
    var detectionCount: Int
    var blockedEventCount: Int
    var totalProtectionDuration: TimeInterval
    var lastDetectionDate: Date?
}
```

Example:

```text
This week

🐾 Cat interventions          17
⌨️ Accidental keys blocked   284
🛡 Protection time          6m 42s
```

If a cat profile exists:

```text
Migi interventions: 17
```

Cute optional line:

```text
284 mysterious characters prevented.
```

---

# 46. False-positive feedback

After a very quick manual unlock, optionally ask:

```text
Was that actually <CatName>?

[ Yes 🐾 ]    [ Nope ]
```

Only aggregate yes/no feedback should be stored.

Do not add machine learning in V1.

---

# 47. Event callback behavior

Conceptually:

```swift
func handle(event) -> CGEvent? {

    if eventTapWasDisabled {
        reenableEventTap()
        return event
    }

    if emergencyUnlockChord(event) {
        protectionManager.unlock()
        return nil
    }

    if protectionManager.isLocked {

        if eventIsKeyboardInput {
            protectionManager.registerBlockedActivity()
            return nil
        }

        return event
    }

    let detection = detector.process(event)

    if detection.confidence == .cat {
        protectionManager.lock()

        DispatchQueue.main.async {
            overlay.show(
                cat: catProfileStore.activeCat
            )
        }

        return nil
    }

    return event
}
```

This is conceptual and should be adapted for correct CoreGraphics threading and lifetime behavior.

---

# 48. Tests

Detector tests are mandatory.

## Normal typing

```text
h → e → l → l → o
60–180 ms intervals
```

Expected:

```text
NO DETECTION
```

## Fast typing

```text
10 sequential keys
35–60 ms intervals
```

Expected:

```text
NO DETECTION
```

## Shortcut

```text
Command + Shift + P
```

Expected:

```text
NO DETECTION
```

## Gaming-style hold

```text
W + Shift
```

Expected:

```text
NO DETECTION
```

## Cat paw

```text
F G H V B N
```

within approximately 80 ms.

Expected:

```text
DETECTION
```

## Cat resting on keyboard

```text
4–7 neighboring keys
held 1–2 seconds
with overlapping repeats
```

Expected:

```text
DETECTION
```

## Walking paw pattern

```text
J K U I M
```

with overlapping key-down events over roughly 300 ms.

Expected:

```text
DETECTION
```

---

# 49. Cat profile tests

Test:

```text
Create cat profile
Rename cat
Import JPG
Import PNG
Import HEIC
Select avatar
Remove photo
Restart app and restore profile
Profile with no photo
Profile with multiple photos
Corrupt/missing local photo fallback
```

Verify that UI strings always use the active cat's current name.

---

# 50. Performance

PawGuard should use negligible resources while idle.

Requirements:

- No high-frequency polling loop.
- Event-driven keyboard monitoring.
- No camera in V1.
- No background image processing after import finishes.
- Animations run only while visible.
- Photo thumbnails should be cached locally.

---

# 51. Failure handling

If keyboard interception cannot be created:

```text
⚠ Protection unavailable
```

Show:

```text
PawGuard cannot monitor the keyboard.
Check Accessibility permission.
```

Never claim the user is protected when interception is unavailable.

If a cat photo becomes unavailable or corrupted:

- Fall back to generic avatar.
- Keep the cat name and profile.
- Do not break protection.

---

# 52. V1 implementation order

## Phase 1 — Core app

```text
macOS project
menu-bar app
Accessibility onboarding
CGEventTap
keyboard event observation
```

## Phase 2 — Cat profile

```text
cat name onboarding
photo picker
local image copying
avatar selection
profile persistence
fallback avatar
```

## Phase 3 — Detection

```text
rolling event buffer
currently held keys
physical keyboard map
detection score
unit tests
```

## Phase 4 — Protection

```text
event suppression
20-second lock
extend-on-activity
emergency unlock
cooldown
```

## Phase 5 — Personalized UI

```text
dynamic cat name
cat avatar
floating overlay
paw animations
countdown
unlock animation
menu-bar UI
```

## Phase 6 — Settings and polish

```text
sensitivity presets
cat profile editing
appearance themes
statistics
debug view
launch at login
```

---

# 53. Definition of done

V1 is complete when:

```text
✓ Native macOS menu-bar app runs correctly

✓ User can enter their cat's name

✓ User can upload one or more cat photos

✓ Photos remain local to the Mac

✓ User can choose a cat avatar

✓ App gracefully works with no uploaded photo

✓ Cat name/photo can be changed later

✓ Accessibility onboarding is clear

✓ Normal typing does not trigger protection

✓ Common shortcuts do not trigger protection

✓ 4–6 simultaneous neighboring keys reliably trigger protection

✓ Trigger blocks subsequent keyboard input

✓ Mouse and trackpad remain usable

✓ Overlay uses the user's cat name and photo

✓ Lock automatically expires

✓ Continued paw activity extends protection

✓ Emergency keyboard unlock works

✓ Mouse unlock works

✓ No typed text is stored

✓ Event-tap failure is handled correctly

✓ App uses little CPU while idle

✓ UI feels like a polished native macOS utility
```

---

# 54. UI quality bar

Do not accept a generic developer-tool appearance.

Polish:

```text
spacing
typography
materials
transitions
shadows
animation timing
iconography
hover states
countdown movement
window positioning
image cropping
empty states
permission states
```

Prefer native macOS controls and SF Symbols when appropriate.

The desired feel is:

```text
high-quality indie Mac utility
+
native Apple-style interaction
+
personal connection to the user's cat
```

Cute, but not childish.

---

# 55. Future V2 — camera verification

Do **not** implement this in V1.

The cat profile and uploaded photos should make future camera functionality possible.

Future architecture:

```text
Suspicious keyboard activity
        ↓
Camera checks keyboard region
        ↓
Cat detected
        ↓
Optional identity comparison against active cat profile
        ↓
High confidence
        ↓
Keyboard protection
```

Possible future modes:

```text
Any cat mode
Only my cat mode
Keyboard region detection
Multiple cat profiles
```

Important: uploaded photos in V1 are for personalization only. Do not pretend they perform identity recognition.

---

# 56. Future V2 — multiple cats

The data model should support:

```text
Migi
Luna
Milo
```

with one active profile or multiple recognized cats.

Potential UI:

```text
Cats

✓ Migi
✓ Luna

[ Add Cat ]
```

Messages can dynamically use the detected/selected profile.

Do not implement multi-cat recognition in V1.

---

# 57. Product personality

PawGuard should be:

```text
Friendly
Cute
Short
Calm
Personal
Privacy-focused
```

Good:

```text
🐾 Migi is typing
Keyboard protected for 18 seconds.
```

Good:

```text
🐾 Luna has taken over the keyboard.
```

Bad:

```text
🚨 CAT ATTACK DETECTED!!! 🚨
```

The cat is not an error condition.

The app should feel like a delightful little guardian for people who share their desk with a cat.
