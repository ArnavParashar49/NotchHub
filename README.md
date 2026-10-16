# NotchHub

A native macOS **Dynamic Island** for the MacBook camera notch — as if Apple had
designed the notch to work this way from day one.

The notch becomes a quiet, premium information surface. When nothing is
happening it is essentially invisible — a black notch that blends into the menu
bar. When an event occurs, it smoothly springs open into a pill/island with
useful information, then contracts back to the minimal notch state.

## Download & install

**[Download the latest release](https://github.com/ArnavParashar49/NotchHub/releases/latest)**
— `NotchHub.dmg` on the Releases page.

**Requirements**

- **macOS 13 Ventura or later.**
- **An Apple silicon Mac.** The release is built for Apple silicon, which every
  MacBook with a notch is.
- **Made for a MacBook with a camera notch** (14- and 16-inch MacBook Pro from
  2021, MacBook Air from M2). Without a notch, as on an older Mac or with an
  external display as the main one, NotchHub still runs. The island opens
  from a notch-sized spot (200×32 pt) at the top centre of the menu bar. At
  rest that spot shows nothing: there is no black notch to blend into and no
  pet beside it, and a click there goes to the menu bar. NotchHub reads the
  display when it launches, so relaunch it after you change the main display.

**Install**

1. Open `NotchHub.dmg`.
2. Drag **NotchHub** onto **Applications**, then eject the disk image.
3. Open NotchHub from Applications. It has no Dock icon and no menu-bar item.
   Point at the notch to open it, or press ⌥⌘, for Settings, where you can
   also quit it.

**The first launch.** NotchHub is ad-hoc signed and not notarized by Apple, so
macOS blocks it the first time you open it. On macOS 15 Sequoia and later the
warning says Apple "could not verify" that NotchHub is free of malware. To open
it anyway:

1. Open NotchHub once and click **Done** in the warning (not Move to Trash).
2. Open **System Settings → Privacy & Security**, scroll down to **Security**,
   click **Open Anyway** beside the line about NotchHub, and enter your login
   password. The button is there for about an hour after you tried to open the
   app.
3. Open NotchHub again. If macOS asks once more, choose **Open Anyway**.

macOS 15 removed the old shortcut of right-click → Open. On macOS 13 and 14
that shortcut still works (Control-click NotchHub in Applications → **Open** →
**Open**), and so does **Open Anyway** in Privacy & Security.

Or clear the download's quarantine flag in Terminal. Do this only for a copy
you downloaded from the Releases page. It also helps if macOS says NotchHub
"is damaged and can't be opened":

```sh
xattr -dr com.apple.quarantine /Applications/NotchHub.app
```

You only need to do this once. After that, macOS asks for each permission the
first time a feature needs it (see [Permissions](#permissions)). To build the
app yourself instead, see [Build & test](#build--test).

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
  - `LidAwakeEngine` · `LidAwakePolicy` · `LidAwakeHelperRule` — keeping
    the Mac working with the lid closed: the guards, the state machine
    (crash reconcile included), and the exact helper rule and commands
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
  - `LidAwakeController` — the Mac's sleep with the lid closed: watches the
    power source and the apps, runs the two `pmset` commands, puts normal
    sleep back at quit, and keeps a dead-man's switch armed for a crash.
    `@MainActor`, the one truth about it
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

The NEO listener's stub-core tests need a Python with the `websockets` package
(`NOTCHHUB_NEO_PYTHON=/path/to/python ./scripts/test.sh`). Without one they
are skipped.

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

**NEO is optional.** NEO is a separate voice assistant that is not public yet,
and every NEO feature below stays dormant without it. With no NEO on the Mac,
NotchHub only checks for NEO's token file (`~/.neo/ws-token`) every 1.5 s. It
opens no connection until that file is there, and it has no NEO panel unless
NEO's page is installed. The island, the pet and every other feature work as
they do without NEO (see the end of this section). The **NEO** tile in Settings
turns all of it off.

With NEO running, NEO lives in the notch — as the pet. The pixel fox beside
the notch **is NEO**: its name is Neo, it is on screen whenever NEO's core is
connected (whatever Show Pet says), and while NEO is busy its pose is what NEO
is doing. With NEO ready the fox lives its
own life — the idle island is exactly the pre-NEO one, mischief and all —
and with NEO active the fox simply animates, in whatever shape the island is
in (idle, the hover wings, the compact bar, the expanded island). When NEO is
listening, the island's own rim lights — the wake light: a one-pixel line of
cool blue lying on the silhouette with a soft glow a few points into the black
behind it, brightest along the bottom and fading to nothing as the sides climb
to the screen's top edge, with nothing across the top. One broad highlight
drifts slowly to and fro along it and the rim breathes, barely. When NEO wakes,
one bright sweep runs from both top ends down the sides and along the bottom,
meets itself under the middle of the notch and blooms there, and the bloom
becomes the drifting highlight. The island's black never grows for it: the
line sits just outside the black (where the hardware notch can never cover
it), and the glow, which the notch would hide, fades out before reaching it.
It is drawn from the island's in-between shape on every frame, so it stays on
the edge while the island springs between shapes; the wake and the exit run at
the display's own rate (120 Hz on ProMotion), the settled light at 60 Hz (it
has no edge left to step). It fades out in half a second when listening ends and
never takes a click. Its tint follows the user's wake-outline colour. The core
reports that NEO is listening, not room loudness, so the animation is
state-driven and makes no claim about microphone level. It pauses while the
notch's context menu is tracking; Reduce Motion keeps a still rim that only
fades in and out. The mark reads "NEO is listening" to assistive technology
and is hidden from capture with the island in Ghost Mode.

The poses, from the fox's own frames (`PetBrain.neoAnimation`):

- **connecting** → waking: a stretch, then standing alert
- **listening** → attentive: ears up, eyes on you, a slow breath — paired
  with the island's lit rim
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
`~/.neo/ws-token` — the only thing it reads under `~/.neo`), and reconnects
every 1.5 s while NEO is off. When NEO turns its camera on, NotchHub shows it
in its own native camera panel (the detection boxes on the picture, mirrored
together); only NEO's opening of the camera opens that panel. Camera frames
are off by default: every connection starts with `camera_view visible:false`,
and NotchHub asks for frames (`visible:true`) only while that panel is on
screen. Frames stay in memory only — the latest one, at most 24 a second —
and are dropped when the panel closes; the panel is hidden from screen
sharing and recording like the island's other camera preview. Its × (or
another panel taking the island) sends `camera_stop` for that session, so the
camera goes off rather than running unseen. The toggle is **NEO** in
Settings. `--neo-demo` runs a scripted turn through the fox without a core
(the chat stays closed; at the OK, Allow and Cancel pop out under the notch
for 6 s); `--neo-confirm-snapshot DIR` renders those buttons offscreen —
before, as seen, with their hit targets, hovered, and with the fox on the
left — to `DIR/notch-confirm.png`;
`--neo-snapshots DIR` renders each pose offscreen in each island shape
(`--neo-snapshots DIR listening` filters to NEO's listening mark in each
shape); `--neo-glow-zoom DIR` keeps the legacy pet-halo comparison helper.
`--neo-outline-frames DIR [LABEL]` renders the wake light frame by frame at a
fixed clock — a loop, its wake and exit, and a real-time episode — in five
island shapes on a grey menu bar, a white wallpaper and an x-ray of the
notch, with contact sheets and 4× zooms, to `DIR/LABEL` (`--outline-shapes`,
`--outline-variants`, `--outline-tint RRGGBB` narrow it;
`--outline-motion reduced` renders it as Reduce Motion shows it);
`--neo-outline-morph DIR [LABEL]` samples the real island live, from an
invisible window, while it springs between shapes and while the light comes
and goes, and measures the light's frame rate and CPU cost at rest
(`--outline-pacing-only` for just that). `scripts/outline_gif.py FRAMEDIR`
turns any of those frame folders into a real-time 30 fps GIF.
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
  the browser card opening (the camera and a song have NotchHub's own native
  surfaces instead), NEO's page asking to
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

## Making the pet your own

Settings → the pet's group → **Customise** opens the pet's page
(`PetSettingsSection`; the pet's panel has a "···" beside its swatches that
opens the same page). A live preview at the top shows the fox as it is now —
enlarged, and at its true size beside a notch on the side it lives on — and
everything below applies at once, with no relaunch. Every option's default is
the pet as it always was: with nothing changed, every island frame, the pet's
placement and every snapshot are what they were.

- **Look — fur.** Ten presets (`art/pet/looks.txt`: Fox, Arctic, Silver, Sand,
  Red, Midnight, Snow, Cocoa, Sakura, Cyber) — palette swaps, so every frame
  works in every look — or **a colour of your own**: hue, saturation and
  lightness sliders. The fox's ramp (fur, shade, highlight, outline) is
  derived from the pick (`PetPalette.custom`) with its luminance held between
  0.16 and 0.60, so no pick can make the fox unreadable: black is lifted until
  it is 4:1 against the island's black and 3:1 against the eyes and outline,
  white is held down until the cream muzzle, chest and tail tip stand clear of
  it. Palettes are built when the setting changes, never while drawing.
- **Look — wake outline.** The lit rim uses the design system's cool blue
  (Blue, the default), Teal, Sky, Violet, Rose, Amber, White, or **Match fur**
  (the fur's highlight colour, lifted if the fur is dark).
- **Wear.** A hat (seasonal, none, or one of ten) and ONE accessory — glasses,
  sunglasses, a scarf, a bow tie, headphones — which combine. Accessories are
  pixel art like the hats (`art/pet/wear.pet`), drawn once for the front view
  and once for the side view and placed on every frame's wear anchor
  (`art/pet/wear.txt`): they follow the head through every pose, NEO's and
  the mischief included, mirror with the fox, and are clipped to its 16×16
  frame, so nothing is ever drawn outside the pet. A prop held in front of
  the chest hides what is worn at the neck on those frames.
- **Size.** Small (14 pt), Normal (16) or Large (20) in the notch strip; the
  expanded island's fox is twice that. Normal is one point per art pixel. The
  others are nearest-neighbour: each art pixel's edges are snapped to device
  pixels and every position and offset is a whole number of points
  (`PetMetrics`), so the art stays crisp and never shimmers as it moves. The
  idle dock (30 / 34 / 42 pt), the room the bars keep, the transport's
  reserve and the mischief (hiding, peeking) follow the size; the listening
  signal colour follows the pet's chosen glow colour.
  the size. NEO's Allow / Cancel surface does not change — a large fox still
  fits beside the notch in it. The pet's panel always shows the fox at 48 pt.
- **Home.** Right of the notch (the default), left of it, or Auto — no fixed
  home: the fox stays on whichever side its games leave it. Mischief starts
  from home and a visit to the other side ends with the trip back; a home on
  the left is the same life mirrored. In the bars (wings, compact, expanded,
  a panel's strip) the fox rides the trailing edge whatever its home.
- **Energy.** Calm, Normal or Playful: how often it fidgets and plays, and
  how soon it dozes (`PetEnergy`). Calm mostly sits and breathes — quiet
  flourishes 2.2× further apart, mischief 3.5× rarer, asleep after 90 s.
  Playful fidgets nearly twice as often, plays 2.5× as often and stays up
  6 minutes. Normal is exactly the old schedule.
- **Sleeps at night.** Between two hours (22:00 – 07:00 by default; the night
  may run past midnight) the fox curls up whatever the Mac is doing — music,
  a timer, an agent — unless NEO is doing something, a call is on, or you are
  with it (the cursor on the island, its panel open, a click): then it is up,
  and curls up again 20 s after it is left alone. The night's start and end
  are on the brain's own schedule; nothing polls.
- **Name.** 1–16 characters, trimmed ("Neo" if left empty): the panel's
  hello, the accessibility labels and Settings use it. NEO the assistant is
  still NEO — "Neo is listening", "Neo needs your OK" — only the pet's name
  changes.

Everything is stored in `PetSettings` (one JSON value in the defaults).
Settings saved by an older build decode with every new option at its default,
and a value this build does not know (a look or an accessory a newer build
saved) falls back to its default on its own.

`--pet-custom-snapshots DIR` renders all of it offscreen to
`DIR/pet-custom.png` (`shots/pet-custom.png`): every preset, custom colours
with the pick beside the fox drawn from it, each accessory alone and with a
hat in front, side and peeking poses, the three sizes on both sides in the
real island (idle, the wake outline, Allow / Cancel, the bars, mischief),
and the Settings page. `python3 scripts/pet_art.py sheet OUT.png --wear NAME
[--hat NAME] [--look NAME]` shows an accessory on every frame of the art.

## Keep working with the lid closed

Settings → **Lid Closed** (the Power card, under the pet's group): long AI
jobs — an agent app, a chat app writing code, an agent in a terminal — keep
running when you close the lid.

**How macOS works.** Closing a MacBook's lid sleeps it whatever power
assertions are held: `caffeinate` and every IOPMAssertion only stop *idle*
sleep, and clamshell mode needs an external display and power. The one
supported switch that keeps a closed Mac running is the system setting
`pmset -a disablesleep 1` (`SleepDisabled 1` in `pmset -g`); `pmset -a
disablesleep 0` puts normal sleep back. Closed, the screen goes off and
everything keeps running. It needs root, so NotchHub makes only those two
changes, and reads the state back from `pmset -g` (no root) every time.

**The page.**

- **Keep working with the lid closed** — the switch, with what closing the
  lid does right now under it, and a warning: a closed Mac that doesn't
  sleep can overheat in a bag and drain its battery.
- **Only on the power adapter** (on by default) — on battery the Mac sleeps
  as usual, and it picks up again when you plug in. Off, a **battery floor**
  applies instead: at or below it (20 % by default, 10–50 %) the Mac is let
  sleep, and not kept awake again until it is 3 % above the floor or on the
  adapter. A battery whose charge can't be read counts as below the floor.
- **Turn off after** — Never (the default), 1, 2, 4 or 8 hours: the switch
  turns itself off, counted from when it was turned on (or the hours were
  changed).
- **Keep after NotchHub quits** (off by default) — off, quitting NotchHub
  (or NotchHub crashing) puts normal sleep back, because nothing would be
  left to watch the guards.
- **Only while these apps are open** — pick apps from the ones running, or
  any app in Applications; they are stored by bundle identifier, never by
  name. When none of them is open, the Mac sleeps as usual; when one opens,
  it keeps working again. An agent running in a terminal counts through the
  terminal app. Menu-bar and agent apps count too (they are heard through
  the running-apps list, not only the launch / quit notifications).
- **Password-free switching** — the helper (below): Set Up… / Remove….

The status reads "Your Mac will keep working with the lid closed", "Normal
sleep", "Paused: on battery", "Paused: battery at 20 % or below", "Paused:
none of your apps is open", "Paused: needs your password to resume" (with
Resume…), or "Sleep is turned off outside NotchHub" (a `SleepDisabled 1`
something else set — left alone, with Restore normal sleep…). The compact
island never changes for any of it. Outside the page there is a small bolt
on the features page's card while the Mac is being kept awake, and a laptop
chip on the dashboard's quick-action bar (leftmost) that is the same switch:
a click turns it on or off exactly as the page's switch does (the first time,
the same one dialog) and the dashboard stays open. The chip is plain while
the switch is off, lit while the Mac is being kept awake, and plain with a
small dot while it is on but paused — or while the switch is off but sleep
is still turned off (a cancelled dialog, or `SleepDisabled 1` set outside
NotchHub), so it never looks idle when a closed lid won't sleep the Mac.

**The helper.** The guards must be able to put sleep back with nobody at the
Mac — unplugged in a bag, the clock run out, the apps quit — and a password
prompt waiting behind a closed lid would keep it awake until someone opened
it. A privileged helper daemon (SMJobBless / SMAppService) needs a real
Developer ID signature, which an ad-hoc-signed NotchHub does not have. So the
first time the switch goes on, one macOS admin dialog (AppleScript's `do
shell script … with administrator privileges`, run by `osascript`: macOS asks
for the password, NotchHub never sees it) installs a one-line sudoers
drop-in, and sleep is then turned off *through* it:

```
/private/etc/sudoers.d/notchhub-lid   (root:wheel, 0440)
<you> ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
```

It grants exactly those two command lines and nothing else (no shell, no
other `pmset` setting, no wildcard). The file is written under a dotted temp
name (sudo ignores names with a dot), checked with `visudo -cf`, owned
root:wheel, mode 0440, moved into place, and the whole policy is re-checked
with `visudo -c` (it is removed again if that fails); a user name that would
need sudoers escaping, or that sudoers reads specially (`ALL`, an all-capitals
alias), is refused. From then on every switch is `sudo -n /usr/bin/pmset -a
disablesleep 0|1` (`-n`: it never prompts).

The Mac is only ever kept awake while that silent way back works. Sleep is
turned off through the rule and never through the dialog — the command
working proves the same rule will put sleep back with nobody there — and the
rule is checked again right after it is installed, at launch, and at most
every ten minutes on a wake or when Settings opens (by re-asserting the value
already set: `disablesleep 0` while sleep is normal, `1` while NotchHub holds
it). If it stops working while NotchHub holds the setting, normal sleep goes
back. Putting sleep back may fall back on the admin dialog: any time for a
tap on the page; for the guards on their own at most once per hold, and never
while the lid is closed — otherwise the rule is retried, silently, on every
later change and every minute until it lands. Keeping the Mac awake never
prompts on its own, and nor does any row but the main switch — the page says
"needs your password" and Resume… asks. **Remove…** deletes the rule and puts
normal sleep back in one dialog, and turns the switch off. By hand: `sudo
pmset -a disablesleep 0; sudo rm /etc/sudoers.d/notchhub-lid`.

**Crash-safe.** NotchHub records in its own settings that *it* turned sleep
off — written before the change is made, cleared only once normal sleep is
confirmed back. On launch it compares that with `pmset -g`: its own
`SleepDisabled 1` with the switch off or a guard holding is put back; a
stale record is cleared; a `SleepDisabled 1` it did not set is left alone. On
quit (`applicationWillTerminate`) a command still running is stopped (a
password dialog closed, a helper command waited for), `pmset -g` is read
afresh, and sleep goes back synchronously through the helper — never a
dialog at quit; if that fails, the record stays for the next launch — unless
"Keep after NotchHub quits" is on and the guards still want the Mac awake.
While it holds the setting, SIGTERM quits through that path instead of
killing the process. For a crash, Force Quit or `kill -9`, a dead-man's
switch is armed whenever NotchHub going away should put sleep back: a small
`/bin/sh` outside NotchHub that waits for its process to be gone, then runs
the helper's `sudo -n pmset -a disablesleep 0` (it steps aside if NotchHub is
already running again, and is stopped on a clean quit). When a guard puts
sleep back while the lid is closed with no external display, NotchHub checks
20 s later and, if the Mac is still up, asks it to sleep (`pmset sleepnow`,
no root). While it keeps the Mac awake it holds a process activity so App Nap
cannot slow its timers.

Power changes come from IOKit (`IOPSNotificationCreateRunLoopSource`, in the
run loop's common modes so an open menu doesn't hold them up), app launches
and quits (the notifications and the running-apps list's KVO) and wakes from
NSWorkspace, all in `LidAwakeController`; the decisions are
`LidAwakeEngine`'s, pure and tested with fakes for the privileged runner, the
power source, the workspace and the dead-man's switch — the tests never run
`pmset -a`, `sudo` or the dialog (the dead-man's switch is run for real with
`touch` standing in for the restore). A normal launch is the only one that
starts it; inspection launches (`--settings`, `--demo`, the snapshots) show
the page but never touch the Mac's sleep. `--surface-snapshots DIR Lid`
renders the page in each state.

## Permissions

- **Automation** — reading the track from Spotify, and the page and tabs of
  the frontmost browser.
- **Accessibility** — the call controls and browser back / forward / new tab
  send the app's own keyboard shortcuts, and window titles are read through it;
  macOS prompts the first time a control is used.
- **Administrator** — once, for Settings → Lid Closed's helper (macOS's own
  password dialog; see "Keep working with the lid closed"), and again only if
  the helper is removed or stops working.
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
together, or dress it up (colour looks, seasonal hats) — and make it your own:
its fur (ten presets or any colour), what it wears, its size and side of the
notch, its energy, its night and its name (see "Making the pet your own"). It also knows the major
holidays (Christmas, Diwali, Lunar New Year, Eid, Thanksgiving, Hanukkah…),
dressing up and wishing you a happy one. A settings panel gates every listener.

Known limits: recent macOS releases may withhold MediaRemote now-playing data
from third-party apps, so music detection leans on Music/Spotify notifications
and browser tabs; a paused browser tab still reads as playing; Webex in a
browser is not detected as a call.

## License

NotchHub is released under the [MIT License](LICENSE). It includes a port of
[thinking-orbs](https://github.com/Jakubantalik/Libraries.dev) (MIT, Jakub
Antalik). The third-party notices are in [THIRD_PARTY.md](THIRD_PARTY.md). Both
files ship inside the app, in `NotchHub.app/Contents/Resources`.
