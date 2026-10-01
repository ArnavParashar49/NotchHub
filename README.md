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

- **NotchHubOrbs** — NEO's thinking orbs: `OrbEngine`, a port of the
  `thinking-orbs` geometry engine (MIT, see `THIRD_PARTY.md`), and `OrbView`,
  the canvas that paints it
- **NotchHubCore** — pure, testable domain (no GUI):
  - `NotchGeometry` — notch detection + island frame math
  - `NeoState` · `NeoStateHold` · `NeoLaneModel` · `NeoLaneLayout` — NEO's
    state, the dwell that keeps its orb from strobing, what its lane shows and
    when it tucks in, and how wide it is
  - `Activity` / `ActivityKind` — the activity model
  - `ActivityQueue` — primary + stack, priority ordering, transients, auto-dismiss
  - `IslandStateMachine` — idle / wings / compact / expanded / interactive
  - `MeetingDetector` · `MeetingControlLayout` — call detection and the
    call-control hit layout
  - `TeleprompterState` · `TeleprompterLayout` — clock-derived scrolling and
    the reading controls
  - `CameraState` · `CameraLayout` — the preview's state machine and controls
  - `GhostMode` — which surfaces are hidden from screen capture, and why
  - `BrowserMedia` — normalising a media tab's title, and telling "no media
    tab" apart from "could not ask"
  - `TrayClip` / `TrayStore` — the clipboard history (text only)
  - `ClipboardPrivacy` — which copies never enter the Tray
  - `Spring` / `SpringAnimator` — damped spring physics + presets
  - `DesignTokens` — the design system
- **NotchHubSystem** — native system listeners (no UI, no activity state):
  - `SystemEvent` — neutral facts about the system
  - `SystemListener` protocol + `SystemEventBus` + `SystemMonitor`
  - Listeners for battery, volume, brightness, now-playing, downloads,
    clipboard, meetings, privacy, Bluetooth, calendar, weather, focus,
    notifications, coding agents, Wi-Fi and the frontmost app
  - `NeoListener` — a client of NEO's core websocket, relaying its state and
    transcript as `NeoFact`s
  - `CameraController` — the camera. `@MainActor`, and its own `phase` is the
    only truth about whether the hardware is on, so nothing can infer it from
    a panel being open
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

## The Tray

Clipboard storage and nothing else. It keeps the last 60 things you copied **as
text** — plain text, links and colours — with search, pinning and delete. ⌥⌘V,
or the dashboard's tray chip.

It does not capture images, screenshots or files. Nothing is written to disk but
the strings themselves (`~/Library/Application Support/NotchHub/tray.json`, mode
`0600`), so the Tray can never leave an orphaned file behind or show an entry
whose payload has gone. Copies marked concealed by a password manager are never
recorded at all.

## Ghost Mode

**⌥⌘G**, the right-click menu, or the Settings tile. It sets the island's window
to `NSWindow.sharingType = .none`, which takes it out of **every** capture path
macOS has — screen sharing in a call, QuickTime and Screenshot recordings,
⇧⌘3/4/5, and anything built on ScreenCaptureKit — while leaving it on the
physical display. The OS does the hiding, so there is no frame in which the
island can leak into a recording. Note that this also applies to screenshots
*you* take.

It is off by default: a feature that makes the app invisible has to be asked
for. While it is on, the hover strip shows a small "Hidden" glyph — itself
hidden from capture, so it reminds you without appearing in the share.

**The teleprompter and the camera preview are hidden whether or not Ghost Mode
is on.** A script the room can read is not a teleprompter, and a picture of your
own face inside the screen you are sharing is never what you meant — neither
should depend on having remembered to arm anything before the call started.
Every other surface follows the setting.

## NEO in the notch

[NEO](../Neo%202.0/NEO), the voice assistant, lives in the notch. While it is
ready nothing shows — the island is exactly as it was. The moment its core
reports anything else (listening, thinking, working, searching, speaking,
connecting, needs your OK) a lane springs out of the notch's **left** edge:
NEO's own animated orb, the full notch height less 4 pt (the 64-pt design
drawn small, its ink lifted to white so it reads on black), and one short line
beside it — what NEO hears while listening, what it says while speaking,
"Thinking…" and so on; a transcript is cut from its start, so the latest words
are the ones that fit, and the lane never grows past the orb plus 140 pt. Each state
shows for at least 350 ms so the orb never strobes; 1.2 s after NEO is ready
again the lane tucks back in, with the last reply readable until it goes.

The lane is never an activity: it sits beside the notch in every shape (idle,
the hover wings, the compact bar, the expanded island and the panels), the
notch-height bars grow their left side for it, and it never takes the mouse
while idle, so clicks pass through as before. A pet visiting the left of the
notch steps into the notch while the lane is out.

NotchHub is a second client of NEO's core (`ws://127.0.0.1:8765`, the token in
`~/.neo/ws-token` — the only thing it reads under `~/.neo`). It sends
`camera_view visible:false`, so the core never streams camera frames to it,
and reconnects every 1.5 s while NEO is off. The toggle is **NEO** in
Settings. `--neo-demo` runs a scripted turn through the lane without a core;
`--neo-snapshots DIR` renders the lane offscreen in every shape.

### NEO's panel

With NEO's page installed — NEO's `scripts/install-app.sh` puts its built UI
in `~/Library/Application Support/NEO/ui/` — the notch is NEO's **only** UI.
The island expands **down** from the notch into NEO's panel: NEO's own chat
page, unchanged, in a `WKWebView` served from NotchHub's `neo://app/` scheme
(`NeoSchemeHandler`, files under that folder only) with the host's values
injected before its scripts run (`neo://app` is the one origin NEO's core
admits besides its own; the page opens its own socket with the token). The
transcript, the confirm buttons, the in-chat browser card, the camera card
and the song card all work as in NEO's window; the page fills the panel
(420×520 under the notch strip, growing for a browser card up to 60% of the
screen) on the island's black with no card of its own.

- It opens when NEO starts answering (thinking, working, searching, speaking,
  needs your OK), when a card opens, when NEO's page asks (a login page, a
  question) and when the lane is clicked. The lane keeps showing beside the
  notch.
- It folds back to the lane **5 s after NEO is quiet** (idle or merely
  listening) — unless the mouse is in it, a card is open, it is pinned, or
  it was opened by hand and NEO has not answered since. Esc, the page's
  collapse button, or a click on the lane close it at once; closed while NEO
  was busy it stays closed for the rest of that turn.
- Clicks on the panel reach the page without the island being key; the first
  click into it (or on the lane) makes the window key so typing lands in
  NEO's input — NEO starting to talk never steals what you are typing.
- It is never shown to screen capture, as NEO's own window is not
  (`GhostMode.alwaysPrivate`), and Ghost Mode hides the lane with the rest.
- Whenever it connects, NotchHub tells the core `ui_host: notch`, so NEO.app
  keeps its own window hidden (its menu-bar item and hotkeys stay; the
  hotkeys still wake NEO), and `ui_host: window` as it quits, so NEO's own
  orb returns. Without the installed page nothing is sent and the lane is all
  there is.

`NeoLaneModel` (what the lane shows) and `NeoPanelModel` (whether the panel
is open) are both pure and clock-driven; the panel takes NEO's state from the
lane's hold, so the two can never disagree.

None of this touches the island while NEO is absent: with the core off, or on
and idle, there is no lane and no panel and every shape is exactly its
pre-NEO frame (`NeoAbsentTests`, and `--surface-snapshots` / `--app-snapshots`
/ `--pet-panel-snapshots` render pixel-identical to the build before NEO). If
the page is not installed, or fails to load, NotchHub behaves as if the NEO
feature were off — the lane alone, NEO's own window handed back, one log
line — and the **NEO** tile in Settings turns the feature off entirely.

## Permissions

- **Automation** — reading the track from Spotify, and the page and tabs of
  the frontmost browser.
- **Accessibility** — the call controls and browser back / forward / new tab
  send the app's own keyboard shortcuts, and window titles are read through it;
  macOS prompts the first time a control is used.
- **Camera** — the preview only. The session carries a preview layer and no
  frame output, so there is nothing in the path that could record, and closing
  the preview tears the session down rather than pausing it.

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
⌥⌘V the Tray, ⌥⌘T the timer, ⌥⌘P the teleprompter, ⌥⌘C the camera and ⌥⌘G
Ghost Mode. The teleprompter and the camera are also in the right-click menu and on
the dashboard's quick-action bar.

Inspection modes that hold one surface open on screen: `--wings`, `--tray`,
`--settings`, `--timer`, `--teleprompter [--script PATH] [--play]`, `--camera`.
`--camera-cycle` walks the camera through open → close so macOS's own in-use
indicator can be watched going out; `--ghost-cycle` and `--teleprompter-ghost`
do the same for Ghost Mode, with a screen capture taken either side.

## Status

Implemented: notch detection and the floating window; the spring-driven
idle / wings / compact / expanded / interactive states; the activity model and
multi-activity queue; and the system-listener layer feeding the island from
native sources. On top of that: the clipboard Tray,
live-call controls, file drop to AirDrop, weather, focus,
a click dashboard (time, weather, next event with Join, quick actions), a
teleprompter that scrolls a pasted or opened script past the notch at an
adjustable pace, a mini camera preview for the moment before a call (hidden from screen
sharing), Ghost Mode, details
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
