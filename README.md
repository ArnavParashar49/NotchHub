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
  the canvas that paints it (unused by the island since the fox became NEO;
  kept with its goldens)
- **NotchHubCore** — pure, testable domain (no GUI):
  - `NotchGeometry` — notch detection + island frame math
  - `NeoState` · `NeoStateHold` · `NeoPresenceModel` · `NeoPanelModel` —
    NEO's state, the dwell that keeps the fox from strobing, whether NEO is
    here and busy, and whether its chat is open
  - `NeoConfirmModel` · `NeoConfirmLayout` · `NeoConfirmAnswer` — NEO needs
    an OK: whether the island shows Allow / Cancel under the notch, where
    the two buttons are (drawn and hit-tested from the same numbers), and
    the command an answer sends
  - `IslandHitRegion` — where the island catches the mouse: its final frame
    from the moment a surface is presented, so the first click on it lands
  - `NeoListeningIndicator` · `NeoListeningLayout` — the glow that pulses
    once behind the fox each time NEO starts to listen: the pulse's window,
    its curve, and where it shows (it takes no room)
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
  - `NeoListener` — a client of NEO's core websocket, relaying its state,
    transcript and pending confirmation as `NeoFact`s, and sending the
    answer to one
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

[NEO](../Neo%202.0/NEO), the voice assistant, lives in the notch — as the
pet. The pixel fox beside the notch **is NEO**: its name is Neo, it is on
screen whenever NEO's core is connected (whatever Show Pet says), and while
NEO is busy its pose is what NEO is doing. With NEO ready the fox lives its
own life — the idle island is exactly the pre-NEO one, mischief and all —
and with NEO active the fox simply animates, in whatever shape the island is
in (idle, the hover wings, the compact bar, the expanded island). One thing
is added, each time NEO starts **listening** (its microphone is live): a
soft glow pulses once behind the fox.

**The listening glow** (`NeoListeningIndicator`, `NeoListeningGlowView`):
when NEO's state becomes listening a halo swells in behind the fox, peaks
and fades fully out — ONE pulse, as if the fox pricked up and lit for a
moment — and then nothing is drawn for the rest of that stretch of
listening, however long it lasts. A new stretch (the state left listening
and came back) pulses again. It is a blurred radial glow the fox's size +
6 pt (22 pt around the 16-pt fox of the notch strip, 38 pt around the
expanded island's), in a cool cyan-teal (`DesignTokens.listeningGlow`: the
complement of the fox's orange, and neither the now-playing visualizer's
green nor the system's mic and camera dots). The pulse lasts 1.4 s
(`NeoListeningLayout.pulse`, 0 → 1 → 0): an eased rise to its peak at
0.45 s — opacity 0.8, scale 1.06 — then a slower eased fall to nothing at
1.4 s (opacity 0 → 0.8 → 0, scale 0.88 → 1.06 → 0.88; each half a
half-cosine). If listening ends mid-pulse, what is lit fades on a quick
ease-out (0.3 s). It takes **no room**, and there is no word beside it: the
island never changes width for listening — idle, wings, compact and
expanded have exactly the frames they have without NEO — and the glow is
clipped to the island's black shape. It shows wherever the fox rides,
including a panel's notch strip (the dashboard, an app panel, a call's
controls), and nowhere the fox steps aside. On the idle dock the pulse
waits for the fox to stand at its spot (a game comes home first), and then
runs whole. NEO's core reports THAT it is listening, not how loud the room
is, so the pulse has its own shape and claims no level; with Reduce Motion
it is a single soft fade in and out (to opacity 0.6) at a fixed scale. It
never takes a click, is hidden from capture with the rest of the island in
Ghost Mode, and reads "Neo is listening" to assistive technology while the
pulse shows. It is the design system's one gradient: it is light, not a
surface.

The poses, from the fox's own frames (`PetBrain.neoAnimation`):

- **connecting** → waking: a stretch, then standing alert
- **listening** → attentive: ears up, eyes on you, a slow breath — lit
  once by the listening glow as it starts
- **thinking** → the thought bubble, scratching its head
- **working** → pacing toward the notch and back
- **searching** → the magnifier, then a sniff along the ground
- **speaking** → talking to a cadence, with a small bob
- **needs your OK** → the "!", insisting gently — whenever a confirmation
  waits, whatever state the core reports — with Allow and Cancel under the
  notch (below)
- **ready** → settles back into its own life (and 1.2 s after a turn ends,
  a click on the island still opens the chat)

Each state shows for at least 350 ms so the fox never strobes; a pose
outranks the cursor, sleep and every activity's mood, but not the fox's own
panel or a call's controls. NEO starting wakes a fox that was put to sleep
and ends a game on the dock (the game comes home first — the fox is never
cut mid-leap).

NotchHub is a second client of NEO's core (`ws://127.0.0.1:8765`, the token in
`~/.neo/ws-token` — the only thing it reads under `~/.neo`). It sends
`camera_view visible:false`, so the core never streams camera frames to it,
and reconnects every 1.5 s while NEO is off. The toggle is **NEO** in
Settings. `--neo-demo` runs a scripted turn through the fox without a core
(the chat stays closed; at the OK, Allow and Cancel pop out under the notch
for 6 s); `--neo-confirm-snapshot DIR` renders those buttons offscreen —
before, as seen, with their hit targets, hovered, and with the fox on the
left — to `DIR/notch-confirm.png`;
`--neo-snapshots DIR` renders each pose offscreen in each island shape
(`--neo-snapshots DIR listening` only the listening rows: 0.45 s — the
pulse at its peak — 1.0 s — fading — and 3 s — nothing — into listening, in
every shape); `--neo-glow-zoom DIR` renders the fox and its glow enlarged:
NEO idle, the pulse at its peak, and the pulse fading.
`NOTCHHUB_NEO_DIST=<folder>` serves that build of NEO's page (a `ui/dist`)
instead of the installed one, for a debug run or the built-page tests.
`NOTCHHUB_NEO_SNAPSHOTS=<dir>` makes `kill -USR1 <pid>` write NEO's page as it
is in the open panel to that folder (the web view's own snapshot, which needs
no screen-recording permission).
`--neo-capturable` is a debug flag that leaves the window visible to screen
capture in every shape (Ghost Mode and the always-private panel included), so
`screencapture` of the notch strip shows what the user sees; in memory only.

### NEO needs an OK: Allow and Cancel under the notch

When NEO stages a confirmation — its core's `confirm` event, or the one
still pending in the `hello` when NotchHub connects — the island drops just
far enough under the notch for **two buttons, Allow and Cancel**, and
nothing else: no title, no words about the action, no chat
(`NeoConfirmModel`, `NeoConfirmLayout`, `NeoConfirmView`;
`shots/notch-confirm.png`). The surface is the notch's width plus the fox's
dock on each side (253×72 on a 14-inch MacBook Pro: one 40-pt row under the
32-pt strip), so the fox keeps its exact place beside the notch, in its
"!" pose. What the action is, NEO says — once, in one short line — and
VoiceOver is told ("Neo needs your OK: move report.pdf to the Trash"); the
buttons are labelled Allow and Cancel, with the action as their hint.

- **Why it keys off the event, not NEO's state.** The chat panel used to
  open when NEO's *state* became `confirming`. The core sets that state only
  when its agent session owns the question; a tool Gemini Live's model calls
  itself (forget, close, type, a click…) stages the card and the state goes
  speaking → listening, so nothing showed — and the page that would have
  asked to be seen sits in a web view that is off screen. The `confirm`
  event is sent on every path.
- **It outranks everything** the island shows: the idle island, any
  activity, the dashboard, an app panel, a call's controls and NotchHub's own
  panels — the camera preview among them (its session is left running
  untouched and the picture is back the moment the question is answered).
  The one exception is **NEO's own chat panel**: there the page shows its
  confirm card, and the buttons are never drawn twice. If the panel closes
  with the card still pending, the buttons come up then.
- **It stays** until answered here, or until the core's `confirm_done`
  (answered by voice or in NEO's page, superseded, or expired after NEO's
  two minutes), or the core goes away. A newer confirmation replaces the one
  showing. The buttons are drawn *over* the island's state, never in its
  place (`currentIslandState` over `underlyingIslandState`), so the island
  then springs back to exactly what was there.
- **The chat does not open for it.** `confirming` no longer opens NEO's
  panel, and the page's own request to be seen is declined while a card
  waits (a panel the page got opened a moment *before* the card reached the
  island — two sockets, either order — folds again). A panel you opened
  yourself stays, with the page's card in it.
- **Clicks.** The buttons are drawn and hit-tested from the same layout, and
  they own every click on the surface: a click on one answers; a click
  beside them gives the surface the keyboard and does nothing else — it
  never opens the chat or the dashboard by accident.
- **Keys.** Return (or Enter) = Allow, Esc = Cancel — while the island has
  the keyboard: after a click on the surface, or when one of NotchHub's own
  panels already had it. The surface does **not** take the keyboard as it
  appears and captures no key globally: a Return meant for the app you are
  typing in must never become an Allow. A key still auto-repeating from
  before is nobody's answer.
- **No accidental Allow.** Allow — clicked or keyed — counts only once the
  buttons have been up **0.6 s** (`NeoConfirmModel.allowGuard`); Cancel
  always counts.
- **The answer** is the command NEO's own page sends from its card,
  `{"cmd":"confirm","yes":true|false,"action_id":"…"}`, over the listener's
  host connection; the buttons go at once and the core's `confirm_done`
  follows. Nothing is sent while the core is away.
- **Noticing it.** One cue: the island's own spring "pop" as the buttons
  come out (`DesignTokens.confirmPop`: quicker and bouncier than an ordinary
  expand; a plain 0.2 s ease under Reduce Motion) and the fox's "!". No
  sound — NotchHub plays none anywhere, and this does not invent one.
- **Ghost Mode** hides the buttons with the rest of the island. They are not
  an always-private surface: they show nothing of NEO's but that it asks.

### The first click

A button in NEO's panel used to need two or three clicks, and so would any
surface that comes up on its own. Three things, all fixed:

- The window lets clicks through unless the cursor is on the island, and
  that was decided from the last *hover* it had heard of. A surface that
  came up under a cursor that was not moving was "not hovered": the window
  still ignored the mouse and the click went to the app underneath, until
  the mouse moved. It is now decided from the island's frame and the
  cursor's real position (`IslandHitRegion`, `NotchWindow.syncMouseCapture`)
  — the hit region is the surface's **final** frame from the moment it is
  presented, while the spring is still settling.
- The island's window is not key when NEO's panel opens by itself, and
  NotchHub is not the active app, so AppKit spent the first click on
  activating — a plain `WKWebView` does not accept first mouse. NEO's page
  now lives in a `NeoWebView` that does, as do the island's own views
  (`IslandContainerView`, `IslandHostingView`).
- NEO's Allow / Cancel are drawn controls routed by position, so they need
  no key window at all.

`--selftest` checks all three on the real window and views. To see it:
have NEO ask for an OK, keep the mouse still where Allow will appear, and
click once after the buttons have been up a moment; or open NEO's panel by
a click on the island and click Send or a card's button once.

### NEO's panel

With NEO's page installed — NEO's `scripts/install-app.sh` puts its built UI
in `~/Library/Application Support/NEO/ui/` — the notch is NEO's **only** UI.
The island expands **down** from the notch into NEO's panel: NEO's own chat
page, unchanged, in a `WKWebView` served from NotchHub's `neo://app/` scheme
(`NeoSchemeHandler`, files under that folder only) with the host's values
injected before its scripts run (`neo://app` is the one origin NEO's core
admits besides its own; the page opens its own socket with the token). The
transcript, the confirm buttons, the in-chat browser card, the camera card
and the song card all work as in NEO's window; the page fills the panel on
the island's black with no card of its own, in the notch's own dress: a
slim header (a small orb, NEO, its state), quiet bubbles and tool pills,
the cards as compact rows, the input bar at the bottom.

The panel is **compact** — 340×300 under the notch strip
(`NeoPanelLayout.standard`), what a click opens — and
grows only when the page asks because its content needs it: the camera or
song card a little taller, the browser card up to 60% of the screen's width
and 70% of its height (at most 1000×800), never more. The island decides
the frame; the page lays itself out for whatever it is given.

- NEO thinking, working, searching or speaking **never opens it**: a voice
  answer is the fox's alone, posing in the notch. Nor does "Needs your
  OK": that is Allow and Cancel under the notch (above). It opens only for
  a card opening (the browser, the camera, a song), NEO's page asking to
  be seen (a login page, a question) — or when
  you ask: a click anywhere on the island (the fox included) while NEO is
  active, or NEO summoned by hand (⌘⇧Space, its menu-bar item: the core's
  `woke` event, which the wake word never sends). The panel draws no fox:
  the chat's own orb is the only NEO on screen there.
- Once open it folds back **5 s after NEO is quiet** (idle or
  merely listening) — unless the mouse is in it, a card is open, it is
  pinned, or it was opened by hand and NEO has not answered since; it never
  folds mid-reply. Esc or the page's collapse button close it at once; closed while NEO was busy it stays closed for the rest
  of that turn.
- The core going away (a restart) does not yank an open panel: the page
  shows a quiet "Reconnecting to NEO…" line and the panel waits 15 s
  (`NeoPanelModel.reconnectGrace`) for the core to come back before it
  folds. A closed panel stays closed.
- Clicks on the panel reach the page without the island being key, the
  very first one included (see "The first click"); the first click into it
  (or the click on the island that opened it) also makes the window key and
  tells the page (`neo://show`) so typing lands in NEO's input — NEO
  starting to talk never steals what you are typing.
- It is never shown to screen capture, as NEO's own window is not
  (`GhostMode.alwaysPrivate`), and Ghost Mode hides the fox with the rest.
- Whenever it connects, NotchHub tells the core `ui_host: notch`, so NEO.app
  keeps its own window hidden (its menu-bar item and hotkeys stay; the
  hotkeys still wake NEO), and `ui_host: window` as it quits, so NEO's own
  orb returns. Without the installed page nothing is sent and the fox is all
  there is.
- **Settings → NEO → Listen for “Neo”** switches NEO's wake word while it
  runs. On, NEO keeps its microphone open to hear “Neo” (macOS shows the
  orange microphone dot all the time). Off, the microphone is closed while
  NEO is idle and opens only while NEO is summoned with its keys (⌥⌘) —
  the line under the switch says which, with the keys NEO.app reports. The
  tap sends the core `{"cmd":"set","name":"wake_word","value":…}` (a host's
  command, like the menu's); the switch moves when the core announces the
  change (`settings`, or the `hello`'s `wake_word`), so it always shows what
  the microphone is doing. It is dim while NEO is not running.

`NeoPresenceModel` (NEO's held state and whether its core is there) and
`NeoPanelModel` (whether the panel is open) are both pure and clock-driven;
the pet and the panel both take NEO's state from the presence's hold, so
they can never disagree.

None of this touches the island while NEO is absent: with the core off, or on
and idle, there is no panel and every shape is exactly its pre-NEO frame
(`NeoAbsentTests`, and `--surface-snapshots` / `--app-snapshots` /
`--pet-panel-snapshots` render pixel-identical to the build before NEO). If
the page is not installed, or fails to load, NotchHub behaves as if the NEO
feature were off — the fox alone, NEO's own window handed back, one log
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
fox named Neo — NEO itself, see above — that lives in the notch, reacts to what you're doing and gets up to mischief
when nothing is (hiding behind the notch, peeking out, dashing to the other
side) — click it to stroke it, ask for tricks, start a 25-minute focus session
together, or dress it up (colour looks, seasonal hats). It also knows the major
holidays (Christmas, Diwali, Lunar New Year, Eid, Thanksgiving, Hanukkah…),
dressing up and wishing you a happy one. A settings panel gates every listener.

Known limits: recent macOS releases may withhold MediaRemote now-playing data
from third-party apps, so music detection leans on Music/Spotify notifications
and browser tabs; a paused browser tab still reads as playing; Webex in a
browser is not detected as a call.
