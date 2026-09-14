# NotchHub

A native macOS **Dynamic Island** for the MacBook camera notch — as if Apple had
designed the notch to work this way from day one.

The notch becomes a quiet, premium information surface. When nothing is
happening it is essentially invisible — a black notch that blends into the menu
bar. When an event occurs, it smoothly springs open into a pill/island with
useful information, then contracts back to the minimal notch state.

## Design language

Apple Dynamic Island philosophy: minimal, black, extremely smooth, high
contrast, generous spacing, subtle translucency, soft shadows, extreme corner
radii, SF typography. No borders, no gradients, no clutter, no cheap
glassmorphism. Every transition is spring-driven so the island feels like one
continuous physical object that stretches and reshapes — never a rectangle
popping in.

## Architecture

SwiftPM package, native Swift + SwiftUI/AppKit only (no Electron, no web
wrapper). Three layers, strictly separated:

- **NotchHubCore** — pure, testable domain (no GUI):
  - `NotchGeometry` — notch detection + island frame math
  - `Activity` / `ActivityKind` — the activity model
  - `ActivityQueue` — primary + stack, priority ordering, transients, auto-dismiss
  - `IslandStateMachine` — idle / wings / compact / expanded / interactive
  - `MeetingDetector` · `MeetingControlLayout` — call detection and the
    call-control hit layout
  - `ClipboardPrivacy` — which copies never enter the Tray
  - `Spring` / `SpringAnimator` — damped spring physics + presets
  - `DesignTokens` — the design system
- **NotchHubSystem** — native system listeners (no UI, no activity state):
  - `SystemEvent` — neutral facts about the system
  - `SystemListener` protocol + `SystemEventBus` + `SystemMonitor`
  - Listeners for battery, volume, brightness, now-playing, downloads,
    clipboard, meetings, privacy, Bluetooth, calendar, weather, focus,
    notifications, coding agents, Wi-Fi and the frontmost app
  - `ActivityBridge` — the **only** place events become island instructions
    (present, transient, update in place, remove, refresh)
- **NotchHub** — the app (reads activity state only):
  - `NotchWindow` — borderless transparent window anchored at the notch
  - `IslandView` — the morphing island (SwiftUI)
  - `NotchHubApp` (+ `LaunchModes`, `Panels`, `Meeting`, `Interaction`) — the
    single coordinator where the layers meet

The separation is the point: **system listeners never touch UI/activity state,
and the UI never polls the system.** Events flow one way — listener → bus →
bridge → queue → island.

## Build & test

Requires only the **Command Line Tools** (no full Xcode):

```sh
swift build            # debug build
./scripts/test.sh      # run the unit tests (Core + System)
./scripts/build_app.sh # assemble dist/NotchHub.app (release)
```

Use `scripts/test.sh` rather than a bare `swift test`: with only the Command
Line Tools installed, SwiftPM does not find swift-testing on its own, and the
script passes the framework paths it needs.

## Permissions

- **Automation** — reading the track from Spotify, and the page and tabs of
  the frontmost browser.
- **Accessibility** — the call controls and browser back / forward / new tab
  send the app's own keyboard shortcuts, and window titles are read through
  it; macOS prompts the first time a control is used.

## Run

```sh
# Headless logic self-test (no window):
./dist/NotchHub.app/Contents/MacOS/NotchHub --selftest

# On-screen island preview (scripted activity sequence):
./dist/NotchHub.app/Contents/MacOS/NotchHub --demo

# Normal launch — real system listeners drive the island:
./dist/NotchHub.app/Contents/MacOS/NotchHub
```

The app is an accessory (`LSUIElement`) — no dock icon and no menu-bar item.
Everything lives in the notch: ⌥⌘, opens Settings (which has **Quit NotchHub**),
⌥⌘V the Tray, ⌥⌘M dictation and ⌥⌘T the timer.

## Status

Implemented: notch detection and the floating window; the spring-driven
idle / wings / compact / expanded / interactive states; the activity model and
multi-activity queue; and the system-listener layer feeding the island from
native sources. On top of that: the clipboard Tray (with OCR and pinning),
on-device dictation, live-call controls, file drop to AirDrop, weather, focus,
a click dashboard (time, weather, next event with Join, quick actions), details
about the frontmost app (a browser's page and tabs with navigation, the focused
window's title, and Claude Code / Codex / Foxora Studio session tracking —
model, working state, tokens, turns, context and Codex plan limits), a pixel-art
fox named Notchy that lives in the notch, reacts to what you're doing and gets up to mischief
when nothing is (hiding behind the notch, peeking out, dashing to the other
side) — click it to stroke it, ask for tricks, start a 25-minute focus session
together, or dress it up (colour looks, seasonal hats). It also knows the major
holidays (Christmas, Diwali, Lunar New Year, Eid, Thanksgiving, Hanukkah…),
dressing up and wishing you a happy one. A settings panel gates every listener.

Known limits: recent macOS releases may withhold MediaRemote now-playing data
from third-party apps, so music detection leans on Music/Spotify notifications
and browser tabs; a paused browser tab still reads as playing; Webex in a
browser is not detected as a call.
