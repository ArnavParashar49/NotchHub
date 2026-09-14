# AGENTS.md — NotchHub

## Build & test commands

```sh
swift build            # debug build (SwiftPM; Command Line Tools only — no xcodebuild)
./scripts/test.sh      # unit tests (NotchHubCoreTests + NotchHubSystemTests)
./scripts/build_app.sh # assemble dist/NotchHub.app from the release build
```

## Conventions

- **Stack:** Swift 6.3.3, SwiftPM, AppKit + SwiftUI. Native APIs only — no
  Electron/web wrappers. No third-party dependencies.
- **Three layers, strictly separated:**
  - `NotchHubCore` — pure, testable domain. No GUI, no system access. All
    geometry, activity, queue, and spring logic lives here and is unit-tested.
  - `NotchHubSystem` — native system listeners. Emit neutral `SystemEvent`s;
    hold NO activity state and NO UI. `ActivityBridge` is the only place events
    become activities.
  - `NotchHub` — the app. Window chrome + SwiftUI island. Reads the activity
    queue only; never polls the system.
- **Data flow is one-way:** listener → `SystemEventBus` → `ActivityBridge` →
  `ActivityQueue` → `IslandView`. `NotchHubApp` is the single coordinator where
  the layers meet. Do not reach across layers.
- **The bridge decides HOW an event reaches the queue**, not just what it
  becomes: `ActivityBridge.instructions(for:)` returns `IslandInstruction`s —
  `.present` (persistent: a song, a call, low battery), `.presentTransient`
  (takes the island over music for its `autoDismiss`, then hands it back:
  volume, battery, Wi-Fi, notifications…), `.upsert` (update in place, keeping
  the id: timer ticks, download progress, a call), `.remove`, `.refresh` (state
  the app keeps for wings/panels). `NotchHubApp.handle` only applies them and
  records wing/panel state in `record(_:)` — never special-case an event there.
  Anything transient MUST have `autoDismiss > 0`; `ActivityBridgeTests` asserts it.
- **A normal launch shows nothing.** Never seed a sample activity on launch, and
  menu previews (`runDemo`) get a finite lifetime.
- **Logging:** use `NotchLog.debug` (silent without `--verbose`). Never write to
  stderr unconditionally — several listeners poll every second or two.
- **Design tokens** live in `NotchHubCore/DesignTokens.swift` — the single
  source of truth for the visual system.
- **Animation:** every island transition is spring-driven. The rules that keep
  it liquid (see the Motion section of `DesignTokens`):
  - `NotchHubApp.renderIsland` is the ONLY `withAnimation` for the island.
    Never wrap a render in another `withAnimation` — nested transactions
    override each other (that is how every collapse rode the morph spring).
  - The spring is picked from the frame change by `IslandMotion`
    (peek / expand / collapse / retract / morph), not by the caller.
  - Shrinking springs are critically damped (`dampingFraction 1`); all springs
    carry a `blendDuration` so interrupted motions bend instead of kinking.
  - Content is masked to `NotchShape` and uses `.islandContent` (blur + fade +
    slight top-anchored scale): out fast (`contentOut`), in after the surface
    starts moving (`contentIn`). Never put `.animation(_:value: state)` on the
    content layer — it desynchronises content from the surface.
  - The surface stays opaque while it retracts; `surfaceVisible` fades it only
    after `retractFadeDelay`, once it is notch-sized.
  - The corner radius is one animatable value; the view is pinned by its
    top-left (`offset`), never centred with `position`.
  - The state machine collapses in ONE step to the resting shape (compact, or
    idle when the activity is gone/expired) — no per-tick staircase — and a
    hover exit collapses on a scheduled task exactly at `hoverCollapseDelay`.
- **Idle state:** the island is invisible when idle — no chrome, no glow, no
  permanent text (the one exception: the pixel pet's small dock, when shown). The idle surface is drawn at `opacity 0` (not merely black),
  so nothing is painted at the notch at all. Anything that would keep the island
  out of idle (e.g. a persistent weather activity) must be held as *wing status*
  instead of pushed onto the activity queue.
- **Everything grows SIDEWAYS at notch height — never downward.** Both the
  hover peek (`.wings`) and the activity bar (`.compact`) are exactly
  `notchFrame.height` tall and stretch left and right of the cutout. A transient
  activity (volume, battery, a download) therefore appears *alongside* the notch
  rather than as a pill hanging underneath it. Only the deliberate detail panels
  (`.expanded`/`.interactive`, reached by a click) grow downward.
  - `.wings` (hover from idle): left = the frontmost app's REAL icon
    (`AppSkin.iconData`, a PNG resolved from `NSWorkspace`); right = live status
    (charging, music, Wi-Fi, weather) — plus a LIVE `MusicVisualizer` when
    `WingStatus.musicPlaying` is true. Wing status is read from persistent state
    held by the coordinator (`batteryPercent`/`isCharging`, `wifiConnected`,
    `musicTitle`, `weatherActivity`) — NOT from the activity queue, whose entries
    auto-dismiss after a couple of seconds and would leave the wings empty. The
    wings step straight back to idle on hover-exit; they never step down into
    compact.
  - `.compact` (an activity is present): the activity's glyph on the LEFT and
    its title + value on the RIGHT, both laid out around the cutout.
  - **The WINGS are SYMMETRIC; the COMPACT bar is ASYMMETRIC.**
    — The wings must expand EVENLY about the notch: the same width each side and
    the frame is `screenMidX - width/2`, so the notch is the exact centre. A
    lopsided hover is the bug to avoid.
    — The compact bar is deliberately uneven: the left holds only a glyph and the
    right holds the title, so the frame origin is `screenMidX - lead - notchWidth/2`,
    NOT `screenMidX - width/2`. Get this wrong and content lands under the physical
    notch. `NotchGeometryTests` asserts both — keep it.
  - **The island is AUTO-SIZED, never a fixed width.** Both the wings and the
    compact bar measure their real content and grow to fit it, then collapse when
    there is less — a hardcoded width silently clips once enough icons are live
    (the icons spill onto the menu bar). The chain is:
    `IslandMetrics` measures the glyphs/text (real font metrics + insets) →
    `IslandContentSize` carries the widths → `NotchGeometry.frame(for:content:)`
    sizes the frame → the window's `localFrame`/`swiftUIFrame` and the model's
    `contentSize` thread it to `IslandView`, which lays out at those widths.
    Widths are clamped by `maxContentOverhang` (300) so the island can never
    outgrow the window envelope. When you add a status glyph or a wing surface,
    add its width to `IslandMetrics` — do not add a constant.
  - **Content is inset from the island edge**, never flush: `compactInset` 14 for
    the compact bar, `wingInset` 16 for the wings, `contentInset` 18 for the
    expanded panel.
- **The silhouette scales.** `NotchShape` (and `WingShape`) take a `bottomRadius`
  multiplied by a `heightScale` so the edge language stays identical at every
  size — a compact bar and a tall expanded panel share it. The TOP corners are
  **square** — the shape runs full-width into the screen's top edge and meets
  the bezel at sharp 90° right angles, exactly like the physical notch. The
  BOTTOM corners are **convex** (rounded outward). `heightScale` is
  `min(2, height / notchHeight)` so a very tall panel never gets an absurd
  radius. Token: `radiusIslandBottom` 12 / `radiusWingBottom` 10. There is NO
  top radius and NO shadow/glow — the island is a crisp flat matte-black shape.
- **Self-test:** `NotchHub --selftest` exercises the queue + spring math
  headlessly and must exit 0. Keep it green.
- **Activity model:** add new kinds to `ActivityKind` (with `basePriority`,
  `defaultAutoDismiss`, `defaultSymbol`) and a factory in `Activity`; the island
  layout lives in `IslandView` / `ActivityViews`. Add a new system source as a
  `SystemListener` + a `SystemEvent.Payload` case + a bridge mapping.

## Settings panel (interactive island surface)

- **Feature gating:** `FeatureSettings` (Core) is the single source of truth
  that decides which listeners exist. `IslandSettings` (app view model) is
  bridged to it via `init(featureSettings:)` / `toFeatureSettings()`.
  `SystemMonitor` describes listeners as `ListenerSpec`s whose id includes their
  configuration (e.g. `appDetails+agents`), and `update(settings:)` starts or
  stops ONLY the listeners whose spec changed — never rebuild the whole monitor
  for a toggle. Rebuilding every listener synchronously on the main thread (the
  calendar store, the process table, browser scripting, app icons) froze each
  tap. The settings binding redraws the panel FIRST, then `applySettings` saves
  and schedules the monitor update 0.35 s after the last tap; the weather CITY
  is applied after 1 s of no typing and restarts only the weather listener via
  `SystemMonitor.restart(where:)`. Settings controls use `PressStyle` so a press
  responds immediately.
- **Why settings is interactive while the rest of the island is not:** the
  island window is borderless, `.statusBar`-level, and non-key by default so it
  never steals focus. SwiftUI controls (Toggles) inside it do NOT receive clicks
  unless: (1) `NotchWindow.needsInteraction` is set, which flips `canBecomeKey`,
  activates the app, lowers the level to `.floating`, and makes the container
  first responder; and (2) `IslandContainerView.hitTest` returns
  `super.hitTest(point)` (the hosting view) instead of `self` when
  `needsInteraction`, so the click reaches SwiftUI instead of being swallowed as
  an island click. Esc dismisses via `cancelOperation` → `onCancel`.
- **Layout pitfall:** a `VStack` inside a `ScrollView` sizes to its content, so
  toggle rows don't fill the panel and switches float mid-air. Pin the stack
  with `.frame(maxWidth: .infinity)` and put a `Spacer(minLength: 0)` inside
  each `Toggle` label so the switch lands at the trailing edge.
- **Launch flags:** `--settings` / `--tray` open a panel for on-screen inspection;
  `--wings` opens the sideways hover peek; `--activity <kind>` presents ONE named
  activity held open (600 s) so a single surface can be inspected in isolation —
  kinds: `music volume brightness battery lowbattery timer download notification
  airpods bluetooth recording microphone camera calendar focus dnd wifi clipboard`.
  `--verbose` logs the window frame, `panel=`, `islandState=`, `key=`, `needsInt=`,
  the monitor listener list, and `hotkeys: N/4 registered` — use these to verify
  interaction and gating without clicking.
- **A transient readout does NOT expand.** `Activity.canExpand` decides whether
  a hover/click may grow the compact pill: only kinds with controls or a real
  detailed layout (`.music .meeting .dictation`) expand; a readout that is
  complete in the bar (`.volume .brightness .battery .lowBattery .timer
  .download .wifi .bluetooth .airpods .recording .microphone .camera .calendar
  .focus .dnd .clipboard .notification`) stays a pill. The state machine gates
  compact→expanded on it for `hoverEntered` and `priorityChanged`; a CLICK on a
  readout opens the dashboard instead of growing the pill.
  Add a new kind to the `canExpand` switch — don't hardcode a check in the view.
- **A readout's compact line is its VALUE, not its word.** `Activity.compactText`
  returns `"62%"` for volume/brightness/battery/download and the elapsed string
  for a timer; the glyph already names the kind. Printing the word too overflowed
  the measured width and truncated ("Volu…"). If you add a compact line, update
  `IslandMetrics.compact` to match the view EXACTLY — including any inter-item
  gap — and keep `textWidth` **ceiled** (SwiftUI lays out on whole pixels).
- **Now-playing artwork comes from the private MediaRemote framework.** The
  distributed notifications the media apps post carry title/artist only; the art
  comes from `MRMediaRemoteGetNowPlayingInfo` (`kMRMediaRemoteNowPlayingInfoArtworkData`).
  Parsing lives in `NotchHubCore/NowPlayingInfo` (pure, tested); the untestable
  dlopen call lives in `NotchHubSystem/MediaRemoteNowPlaying`. Artwork falls back
  to the glyph when absent. Transport commands go through `MRMediaRemoteSendCommand`.
- **The island NEVER takes key focus for its media buttons.** `window.needsInteraction
  = true` calls `NSApp.activate(ignoringOtherApps:)` — that steals focus from the
  user's app, and the island auto-expands on hover, so it is never acceptable
  there. Instead the window hit-tests clicks against `MediaControlLayout` and
  routes a button press to `onMediaCommand`, falling through to the normal island
  click on a miss. `MediaControlLayout` is the single source of truth shared by
  the view and the hit-test — never duplicate those numbers.
- **Verifying a feature on screen — trust pixel traces, not the LLM.** `analyze_ui`
  over a full-desktop screenshot misreads repeatedly (it once reported a stock
  macOS sun icon *outside* NotchHub as an app spill). The reliable evidence is:
  `screencapture -x -R x,y,w,h` (POINTS in, 2× PX out), then
  `/tmp/nhtools/rawnhd a.png b.png` which counts differing pixels >0.05 — `nhdiff`
  is threshold-fragile and gives false zeroes; `rawnhd` is the one to use. A
  changing count across two frames proves an animation (timer tick, visualizer,
  download bar); a nonzero count vs the app-off baseline proves content painted.
- **Hover needs STEPWISE mouse movement.** A direct jump to the notch misses the
  tracking area and the island never expands: step it
  (`movemouse 400 700` → `600 300` → `755 16`, ~0.8 s apart). The notch sits at
  screen `755,16` (top-left origin).

## Feature-audit fixes (production pass)

These were found and fixed by driving each surface in isolation:

- **Compact bar showed no live value for the timer.** `Activity.timer` sets
  `subtitle: nil` on purpose (the expanded trailing control renders the readout),
  but the compact bar renders *title + subtitle*, so it showed a bare "Timer".
  Fix: `Activity.compactValue` (the elapsed string for a timer, the subtitle
  otherwise), used by BOTH `IslandView` compact layout AND `IslandMetrics.compact`
  so the measured width matches what is drawn. Add `compactValue` — never a
  constant — when a kind needs a live compact readout.
- **Download progress is real or absent — never invented.** `DownloadListener`
  tracks partial files (`.download .crdownload .part .tmp`). Safari's `.download`
  bundle records bytes and total in its `Info.plist`, giving a real fraction;
  Chrome/Firefox partials have no total, so `downloadProgress(progress: nil,
  bytes:)` shows the bytes received instead of a percentage. A directory watcher
  does not fire when a file inside grows, so a 1 s rescan runs while anything is
  in flight (and while a rename is pending its one-scan grace). Do not re-add a
  fixed progress value or a fake ramp in `tick()`.
- **BrightnessListener crashed the app (SIGBUS).** `DisplayServicesRegisterForBrightnessChangeNotifications`
  takes a callback whose real signature does not match the naive
  `@convention(block)` binding — the framework's own `__getDSClient_block_invoke`
  faults. Fix: POLL `DisplayServicesGetBrightness` on a 1.5 s timer (verified
  crash-free, detects 1.0→0.8→0.6 live). **Never call the register/unregister
  symbols** — the read-only `GetBrightness`/`SetBrightness` are safe.
- **`--settings` looked broken** only because the test harness killed the app
  mid-capture; the panel opens and holds (`panel=settings`) fine. Confirmed 12
  feature toggles render.


- **The Tray is interactive too.** Its rows are real buttons (select → copy,
  context menu → pin/delete), so `toggleTray()` sets `needsInteraction` exactly
  like settings does. Any new panel that holds controls must do the same.
- **Verifying clipboard via the shell:** `pbcopy` from a non-GUI shell does NOT
  reach the app's pasteboard. Use `osascript -e 'set the clipboard to "…"'` to
  trigger `ClipboardTrayListener`.

## Behaviour rules from the second production pass

- **Nothing "currently true" may hold the island.** A running coding agent, an
  active Focus, the weather — wing status only. Their start/finish moments are
  transients (`Activity.codingAgentFinished`, focus 2.4 s, calendar 8 s,
  `downloadFinished` 3 s). Low battery is persistent but is removed by the next
  charging / above-threshold battery reading.
- **A call is a call, not an open app.** `MeetingDetector` (Core, tested)
  requires Zoom's in-meeting helper (`CptHost` / `aomhost`) or the call app
  itself capturing microphone input (CoreAudio process objects, macOS 14.2+;
  device-wide mic flag before that). The listener ends a call after two misses
  and re-emits only when the app changes, so it never overwrites mute state.
- **A call shows as a compact bar;** its control panel (`.meeting`) appears only
  when the island is expanded. The island never takes key focus, so the panel's
  buttons are hit-tested by the window against `MeetingControlLayout` (shared
  with `MeetingView`, like `MediaControlLayout`).
- **Call controls send VIRTUAL key codes** from `MeetingApp.shortcut(for:)` —
  never a character's ASCII value ("a" is 97, which is F6). Posting keystrokes
  needs Accessibility; without it the control prompts and changes no state.
- **The Tray never records private copies.** `ClipboardPrivacy` skips the
  nspasteboard.org concealed/transient markers and password-manager apps.
  `tray.json` and `TrayImages/` live in Application Support with owner-only
  permissions; images are NOT in the temp dir (macOS purges it), and
  `TrayPersistence.save` deletes image files no clip references.
- **Now-playing:** all AppleScript runs on one serial queue (`NSAppleScript` is
  not thread-safe) with at most one poll in flight; browser scripts fetch
  `URL of every tab of every window` in one Apple event. MediaRemote's playback
  rate decides `isPlaying`. Every `nowPlaying` event carries `source` (the
  player's bundle id), which is what a click opens — never guess from which
  apps are running.
- **Testing without Xcode: run `./scripts/test.sh`, not `swift test`.** With
  only the Command Line Tools, swift-testing is not on SwiftPM's search paths.
  Do NOT move the framework paths into `Package.swift` as `unsafeFlags`: the
  tests then compile, but SwiftPM does not detect swift-testing and `swift test`
  exits 0 having run nothing — a false green. A passing run prints
  `Test run with N tests … passed`; no such line means nothing ran.
- **A click opens the dashboard** (`.interactive` presentation → `DashboardView`,
  served as `panelContent` by `NotchHubApp+Dashboard`). Hover still expands a
  song/call; a click on the idle notch, the wings, a readout, or an expanded
  song opens the dashboard; a click that misses its controls, `dismissed`, or
  the cursor leaving closes it to the resting shape (compact / wings / idle).
  An activity expiring behind it does NOT close it. Its controls ("···"
  settings, Join, now-playing → player, timer, dictation, tray) are hit-tested
  by the window against `DashboardLayout` — keep the view's fixed row heights
  and chip widths in step with it. The right column is chosen by
  `DashboardFocus.choose` (an event within the hour beats a playing song).
  Calendar events carry `joinURL` from `MeetingLink.find` (event URL, location,
  notes).
- **Polled readings must be filtered for deliberate change.** Brightness is
  polled, and auto-brightness / True Tone drift the backlight constantly;
  exact-float comparison announced the brightness over and over.
  `BrightnessChangeFilter` (Core, tested) seeds the first reading silently and
  reports only a step of ≥ 2% between consecutive 0.5 s polls. A repeated
  transient of the same kind keeps its id in `ActivityQueue.focusTemporarily`
  (lifetime restarts), so holding a key updates the readout in place.
- **Listeners report their starting state; that is not news.** Volume records
  its level silently on attach (launch, settings change, output switch);
  battery events carry `chargingChanged`, and only plugging in/out is announced
  (a falling percentage is wing/dashboard status); `.network` path changes are
  status only (Wi-Fi joins come from `DeviceListener`). As a backstop, the app
  drops `.presentTransient` for `monitorSettlePeriod` (2.5 s) after the monitor
  (re)starts — state is still recorded.
- **Frontmost-app details (`appDetails` feature).** `AppContextListener` emits
  `.appContext(AppContextSnapshot?)` every 2 s and on app switch, tagged with the
  bundle id so a stale reading never shows for another app. Sources, in order:
  browsers via AppleScript (`BrowserScripting`: page, host, tabs — Chromium,
  Safari and Arc dictionaries), coding-agent sessions when an agent host
  (terminals, editors, Claude, Codex, Foxora — `AppSkinRegistry.agentHosts`) is
  in front, else the focused window title via Accessibility (`WindowTitle`).
  - **Sessions:** Claude Code from `~/.claude/projects/*/*.jsonl`
    (`ClaudeSessionParser`: usage deduped per message id, turns = entries with
    `promptSource`, working = awaiting the model AND active < 2 min); Codex from
    `$CODEX_HOME/sessions/YYYY/MM/DD/rollout-*.jsonl` (`CodexSessionParser`,
    incl. 5-hour/weekly plan limits from `token_count.rate_limits`); Foxora
    Studio from its WebKit IndexedDB `events` store, read-only
    (`FoxoraSessionReader` + `WebKitValueDecoder` for WebKit's structured-clone
    format; run-signal state, step-finish usage counted as each run's PEAK (every step
    re-reports the full prompt), om_status memory window —
    credits are not stored locally). Dedicated apps show their own agent;
    terminals/editors show the most recently active. Readers follow files
    incrementally. `NotchHub --agent-sessions` prints what each reader finds.
  - **Hover strip:** `WingStatus.strip` (`AppStrip`) — left wing app icon +
    label (site / model / window title); right wing browser back·forward·new tab
    (`WingControlLayout`, hit-tested), an agent's token count, or the usual
    status glyphs. `IslandMetrics.wings` measures all three.
  - **App panel:** a click on a browser or agent host opens `.appPanel`
    (`BrowserPanelView` / `AgentPanelView`, 440 wide, height content-driven via
    `IslandContentSize.panelHeight` for plan-limit rows) instead of the
    dashboard; its notch-strip clock switches to the dashboard
    (`showsDashboardOverApp`), "···" opens settings. All controls go through
    `AppPanelLayout`. Browser navigation posts the browser's own shortcuts
    (needs Accessibility); tab cards switch tabs via scripting.
- **Calls:** `Activity.expandsOnHover` is false for a meeting, so its compact bar
  (glyph + live timer, mute + leave via `MeetingControlLayout.compactButtons`)
  stays put under the cursor; a click opens the call panel.
- **Every privacy-gated API needs its Info.plist string, or macOS kills the app.**
  Requesting speech, microphone or calendar access without the matching
  `NS…UsageDescription` in `scripts/build_app.sh` is a TCC privacy violation
  (SIGABRT in `__TCC_CRASHING_DUE_TO_PRIVACY_VIOLATION__`) — that is what
  crashed the dashboard's mic button. `DictationController` and
  `CalendarListener` check `Bundle.main` for the strings before asking (a bare
  `.build/debug` binary has none), and dictation requests the microphone
  explicitly before starting the audio engine. Add the key AND a guard whenever
  a new permission is used.
- **Signing keeps privacy grants.** `scripts/build_app.sh` signs ad hoc with
  `designated => identifier "com.notchhub.app"`. The default ad-hoc requirement
  is the code hash, so every rebuild lost Accessibility/Automation grants (the
  toggle stayed on in System Settings, for an older build, while
  `AXIsProcessTrusted()` returned false). Don't drop the `--requirements` flag.
- **Browser navigation prefers scripting.** Back / forward / reload / new tab go
  through `BrowserScripting.perform` (Automation only; Chromium `go back`,
  `reload`, `make new tab`; Safari reload/new tab, JS history for back/forward)
  and fall back to the keyboard shortcut (Accessibility) only if that fails.
- **Google Meet is a call.** `MeetingListener` reads browser tabs (off main, via
  `BrowserScripting.allTabs`) only while a browser is capturing the microphone
  (`MeetingDetector.browserCapturingAudio`: the browser's helper processes, or
  WebKit's GPU process for Safari) and treats a `meet.google.com/abc-defg-hij`
  tab (`MeetingLink.googleMeetCall`) as the call. `Meeting.browserBundleID` /
  `callURL` locate its tab: mute ⌘D and camera ⌘E focus the tab first; leave
  closes the tab.
- **Call controls act on the call's REAL UI.** `MeetingAccessibility` scans the
  call app through Accessibility (window buttons + menu bar for Zoom / Teams /
  Webex; for Meet only the browser window whose title matches the call tab,
  with Chromium's `AXManualAccessibility` switched on) and
  `MeetingControlLabels` (Core, tested) reads state from button labels, which
  name the NEXT action ("Turn on microphone" = muted, "Unmute" = muted).
  `MeetingControlDriver` presses the element (no focus change; a background Meet
  tab is brought forward once and retried); keystrokes are only the fallback.
  The optimistic toggle is corrected by the listener's next read. Never flip
  mute state blind — the call may have started muted.
- **Leaving ends the surface immediately.** `endMeetingLocally` removes the call
  and `SystemMonitor.meetingLeft` makes `MeetingListener` ignore that call until
  a poll no longer sees it. For Meet, a visible call page without its Leave
  button is NOT a call (the post-call page keeps the URL and may keep the mic).
  Incoming meeting events only overwrite mute/camera listed in `knownStates`.

## Pixel pet

A 16×16 pixel fox named Notchy (`PetIdentity.name`; its panel says
`PetIdentity.hello` unless a holiday greets instead) lives in the notch. It is
an ADDITION: with **Show Pet** off
the island must behave exactly as without it (`petVisible` gates every change).

- **Art:** `art/pet/*.pet` text grids (spec: `art/pet/SPEC.md`, palette:
  `art/pet/palette.txt`). Edit art there, then
  `python3 scripts/pet_art.py generate` → `PetArt.generated.swift` (never edit
  the generated file). `validate` and `sheet OUT.png --scale 12` check work.
  `PetFrameTests` asserts every frame an animation names exists and is 16×16.
  Extras: `looks.txt` (colour looks: palette overrides of the fox's keys),
  `hats.pet` (frames `hat_*`, centred on the pixel boundary x = 8, row 15 on the
  head), `anchors/<file>.txt` (per-frame hat anchor or `none`) and `touch.pet`;
  `extras` checks them, `sheet --look NAME --hat NAME|test --anchor X,Y
  --frames a,b` previews them, and `generate` emits `PetArt.looks` and
  `PetArt.hatAnchors`.
- **Architecture:** island state → `NotchHubApp.petContext()` → `PetBrain`
  (Core, pure, seeded RNG, tested) → `PetPresentation` → `PetView`. System
  events become `PetEvent`s in `petObserve`, which runs BEFORE `record` so it
  compares against the previous state, and is skipped during the monitor settle
  period. The brain never runs timers: `nextWakeup` → one scheduled Task.
- **Rendering:** `PetView` draws `PetFrame.runs` in a `Canvas` with
  `FillStyle(antialiased: false)` at whole-point scales (1× bars/strips, 2×
  expanded, 3× pet panel). A still pose draws once; `TimelineView(.periodic)`
  only while the animation has frames.
- **Placement:** `PetLayout.placement(for:islandSize:notchHeight:dock:)` from
  the island's RIGHT edge (the LEFT edge for the idle dock on the left of the
  notch — `Placement.anchor`), in `IslandView.petLayer` (its own layer, aligned
  to that edge, positioned with `.offset`, masked, no hit testing) so it rides
  the island's springs. Space is RESERVED, never shared:
  `IslandMetrics` `petSlot` (wings, compact), `WingView.trailingReserve`,
  compact trailing padding, expanded music `expandedReserve` and
  `MediaControlLayout.placement(trailingReserve:)`, hit-test insets in
  wings/meeting compact. Panels put the 1× pet in the notch strip (left of
  "···"); Tray/settings/dictation/file drop hide it.
- **Idle dock:** with the pet shown ON A NOTCHED DISPLAY (`petDocked`), idle is
  shaped by `PetDock` (side + reach, `IslandContentSize.petDock`, from
  `PetBrain.dock`): `compactBar(lead: dock.lead, trail: dock.trail)` — a small
  black dock beside the notch, `PetDock.home` = right, `PetLayout.idleDock` —
  or exactly `notchFrame` at reach 0 (the pet hiding inside the notch). The
  surface stays opaque. Without a notch idle stays fully transparent and the
  idle pet is hidden. Hiding the pet while idle schedules the fade. The dock
  CONTINUES the physical notch (`NotchShape.surface`): both sides take the
  hardware notch's top flare (`DesignTokens.radiusNotchTopFlare`, 6) and bottom
  corner (`radiusPhysicalNotchBottom`, 12) — matching it out on the dock and
  coinciding with it behind — so both sides of every expansion and collapse
  morph from the same shape. Every other shape flares
  both top corners like the notch (the flare is drawn just outside the frame, so
  layout and hit testing ignore it). Idle→idle frame
  changes animate (`IslandMotion`: grow → peek, shrink → collapse, same area →
  morph). The idle HOT ZONE is the notch only: `IslandContainerView.idleNotchFrame`
  opens the island; `idlePetFrame` (the pet's own visible rect, from `petRect`)
  takes hovers and clicks WITHOUT opening it; the rest of the dock passes the
  mouse through.
- **Mischief** (setting, needs Idle Animations): on the resting dock
  (`PetContext.canRoam`) an idle or charging pet plays `PetMischief` routines —
  hide-and-seek (sneak into the notch, maybe wag the tail out of it, peek out
  from either side, pop out, blep), crossing under the notch to the left (a
  mirrored stay of `awayStay`, then home), zoomies — plus hop/blep/snicker/
  pounce flourishes. A routine is `PetMischiefStep`s (animation + dock +
  duration) timed by `nextWakeup`; `NotchHubApp.petTick` re-renders the island
  whenever `dock` moves so the black dock and the pet move together. HARD RULES,
  enforced by `PetMischiefTests`: the dock swaps sides only while closed with
  the pet hidden; no beat jumps more than 5 px; every lit pixel stays under the
  notch or inside the (springing) dock; every plan ends on a full dock. Leaving
  the resting dock drops the game at once (`dock = .home`, the island's spring
  carries the pet); a reaction brings it straight home; anything else that needs
  the pet (sleep, an activity, the setting) finishes the beat and goes home the
  quick way (`homeSteps`; from the left that is always the crossing, never a
  new game). NEVER CUT A MOVING PET: a pose may only change where `canCut` holds
  (standing still on a full RIGHT dock — never on the left, where cutting home
  would swap the dock's side in view — or wholly hidden in a closed notch); a
  reaction that arrives mid-dash or mid-leap waits in `pendingReaction` while
  the game winds up, and a flourish from another mood ends once it has landed.
  Hovering the notch mid-game reacts `.caught` (never over a celebration);
  pointing at the pet (`petRect(live:)`, where the sprite is drawn this instant)
  plays the `.caught` routine — a moving beat lands first, a peek finishes
  sliding out before it pops, a wagging tail ducks back (`duckTail`) and the pet
  comes out the front; a pet inside the notch can't be caught. When the island
  itself changes shape, `renderIsland` publishes the pet INSIDE its transaction
  (`updatePet` then `publishPet` in `apply`), and `PetView` keeps one
  `TimelineView(PetFrameSchedule)` for every pose so its identity survives and
  the in-cel offset springs with the island. `PetMischiefTests` samples the
  drawn sprite every 10 ms through play and through interruptions at every beat. Moving animations are
  `PetAnimation.path` cels (frame + whole-pixel offset) authored for the RIGHT
  side (negative `dx` = toward the notch; `PetLayout.hiddenOffset`,
  `peekOffset`, `peekReach`); on the left `PetPresentation.mirrored` flips frames
  (`name~`) and negates `dx`. `--pet-storyboard DIR [SEED]` renders each routine
  frame by frame with the hardware notch in translucent red — look at it after
  changing any of this.
- **CPU:** long-lived poses (`sleep`, `codeType`, `download`) are STILL; motion
  comes from bounded `.once` bursts the brain schedules as flourishes. Only
  `music`/`timer` loop, and only while that activity runs. One-shots use a
  `TimelineView(.explicit)` of their frame dates, so they stop when done.
- **Interaction:** `petControlHit` is FIRST in `onControlHit`; a click on the
  pet opens `Panel.pet` (`IslandState.skin` → `NotchGeometry.petPanelFrame`
  anchored at the island's right edge via `panelAnchorRight`, `PetPanelView`,
  `PetPanelLayout`); opening does NOT touch the state machine, so closing
  returns the island to its previous shape. The panel hangs from the island edge
  beside the pet (`PetPanelAnchor`, either side) and lays its content out from
  that edge. A miss closes it; hover exit closes it. `refreshPet` re-publishes
  `panelContent` while the panel is open so its pet stays live, and publishes
  nothing (no wakeups) while the pet is off screen. Sleep holds until a wake
  trigger STARTS (see `PetContext.wakeTriggers`): only events the pet actually
  reacts to count as engagement or wake it, and `petSleepHoverSession` keeps the
  hover Sleep was chosen in alive until that hover really ends (the collapse
  after leaving). Sleep counts from the first update that finds an engagement
  over (`wasEngaged`). Opening the panel from the resting pet adopts the hover
  (`NotchWindow.adoptHover`) so leaving closes it; with Interaction off a click
  on the idle pet is taken and does nothing. `NotchWindow.syncMouseCapture`
  re-derives capture from the live cursor after every render and pet move, and
  `clearStalePetHover` drops a hover the moving pet no longer has.
- **Panel extras** (`PetPanelLayout.layout` / `hit`: the big pet, six chips —
  Pet, Feed, Play, Tricks, Focus, Sleep — and, in the title row, the look
  swatches and the hat button; the panel is `panelWidth` wide):
  - **Tricks** (`PetInteraction.trick`): with a dock beside a notch AND an
    island that will come back to rest (`PetContext.isDocked`: no lasting
    activity holds it up, even one waiting behind a transient) the panel closes and `requestedMischief` starts a
    game as soon as the island rests (within `requestWindow`), even with
    Mischief off — a `requested` routine (and the visit on the left it may end
    in, `awayRequested`) only winds up when something needs the pet, and is
    caught on its own side when pointed at. Otherwise it plays an in-place trick
    in the open panel (never the one playing or queued).
  - **Focus**: `TimerService.startCountdown` (25 min, `focusDuration`) emits
    `.focusTick(remaining:)` / `.focusFinished(completed:)`; `ActivityBridge`
    shows a "Focus" timer counting down; `PetContext.isFocusing` is the `.focus`
    mood at the laptop (not the stopwatch's clock); a completed session
    celebrates. The chip reads Stop while one runs, and is dimmed and inert
    while the Timers feature is off. The stopwatch and a focus session replace
    each other: `isStopwatchRunning` (not `isRunning`, which is true for both)
    drives `toggleTimer` and the dashboard chip; a countdown exists before the
    stopwatch reports it gave way, and that report is not a pet "timer done".
  - **Looks and hats**: `PetLook` recolours the fox at draw time (`PetArt.looks`,
    never props or hats); `PetHatChoice` (seasonal by `PetHat.seasonal(on:)`,
    none, or a hat) is drawn by `PetCanvas` on `PetFrame.hatAnchor` (mirrored
    with the frame, moving with its offsets, 8 rows of headroom). Both live in
    `PetSettings` and ride through `IslandSettings` so saving settings keeps
    them; `PetRenderModel` carries them to every view of the pet.
  - **Touch**: while the cursor is over the big pet (`panelPetMouseMoved`,
    which alone owns that hover — `clearStalePetHover` leaves it alone) it
    leans toward it (`leanLeft` / `leanRight`); `PetStrokeDetector` (legs with
    `turnBack` hysteresis, so jitter never turns and fine moves add up; two
    turns after real legs within `window`) sends `.bigPetStroked`, which keeps a
    `.stroke` loop going without restarting it (and pushes the next flourish);
    a click sends `.bigPetClicked`, an in-place trick that never repeats back
    to back.
  - **The big pet stays beside the notch**: `PetPanelLayout.contentMinX(notch:)`
    moves the content left of the notch when laying it out from the panel's
    right edge would put the pet under it, and `NotchGeometry.petPanelFrame`
    widens the panel to fit (left panels reach `horizontalInset + petSize` past
    the notch). `PetPanelView.contentLeading` draws it exactly there. Hats and
    hops above the big pet would otherwise be cut by the hardware. At 1×, jumps
    peak low enough (3 px) that an 8-row hat stays on screen on a 32 pt notch
    (`PetTouchTests.hatsStayOnScreen`).
  - Looks and hats chosen in the panel are written through to the Settings
    panel's snapshot (`settingsModel.petSettings`), so saving any setting keeps
    them.
- **Holidays** (`PetHolidays`, setting `PetSettings.holidays`): each holiday is
  computed from its own calendar — Gregorian dates, Easter's computus, nth
  weekdays (Thanksgiving: Canada in region CA, the US date elsewhere), and
  Foundation's `.chinese`, `.islamicUmmAlQura` and `.hebrew` calendars
  (month 1 = Tishri, 3 = Kislev) — except Diwali and Holi, whose Hindu lunisolar
  dates come from `diwaliDates` / `holiDates` tables of published dates: EXTEND
  THEM before they run out. `all(on:)` lists overlaps most important first.
  Festive days carry a hat (`PetHat` holiday hats in `art/pet/holiday_hats.pet`),
  which a SEASONAL hat choice wears before the season's own; religious
  observances only greet. The app works today's holiday out once a day
  (`todaysHoliday`), titles the panel with its greeting, and once a day shows it
  in the island while the pet celebrates (`greetHolidayIfDue`, remembered in
  UserDefaults) — woken by one task that sleeps until the next midnight, never a
  poll.
  `NotchWindow.onMouseMove` → `petMouseMoved` only acts on a change of
  hovered/side.

