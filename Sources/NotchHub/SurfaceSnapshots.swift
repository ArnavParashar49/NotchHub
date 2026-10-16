import AppKit
import ImageIO
import NotchHubCore
import SwiftUI
import UniformTypeIdentifiers

/// `--surface-snapshots DIR`: every state of the newer island surfaces — the
/// teleprompter, the camera and the dashboard — drawn by the REAL `IslandView`
/// at the real geometry, with their hit targets outlined in green on top.
///
/// The same trick the pet and browser snapshots use: rendering through the
/// island rather than through a preview means what lands in the PNG is what
/// lands on screen, and drawing the hit rects over it catches a control that
/// draws in one place and is clickable in another.
@MainActor
enum SurfaceSnapshots {

    /// `filter` keeps only the rows whose name contains it ("camera",
    /// "teleprompter", "dashboard", "settings"), so one surface can be looked at
    /// on its own instead of in one very tall sheet.
    static func render(directory: String, filter: String? = nil) -> Int32 {
        let geometry = NotchGeometry.detectMain()
        let notch = geometry.notchFrame
        let regionMinX = notch.minX - 380
        let regionWidth = notch.width + 760
        let regionTop = notch.maxY
        let scale: CGFloat = 2

        var rows: [Row] = []
        rows.append(contentsOf: teleprompterRows(geometry: geometry))
        rows.append(contentsOf: cameraRows(geometry: geometry))
        rows.append(contentsOf: dashboardRows(geometry: geometry))
        rows.append(contentsOf: settingsRows(geometry: geometry))
        rows.append(contentsOf: lidRows(geometry: geometry))
        if let filter, !filter.isEmpty {
            rows = rows.filter { $0.name.localizedCaseInsensitiveContains(filter) }
        }

        let rowHeights = rows.map { Int(($0.frame.height + 20) * scale) + 6 }
        let width = Int(regionWidth * scale)
        let total = rowHeights.reduce(0, +)
        guard total > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: total, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 1 }
        context.setFillColor(CGColor(srgbRed: 0.1, green: 0.1, blue: 0.11, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: total))

        var rowTop = total
        for (index, row) in rows.enumerated() {
            let height = row.frame.height + 20
            let local = CGRect(x: row.frame.minX - regionMinX, y: regionTop - row.frame.maxY,
                               width: row.frame.width, height: row.frame.height)
            let view = IslandView(
                current: nil, stackCount: 0, state: row.state, localFrame: local, cornerRadius: 10,
                notchInset: notch.height, isIdle: false, notchWidth: notch.width, contentSize: .default,
                panelContent: row.content, surfaceVisible: true, pet: nil, hasNotch: true
            )
            .frame(width: regionWidth, height: height)
            .background(Color(.sRGB, red: 0.42, green: 0.42, blue: 0.45))
            let renderer = ImageRenderer(content: view)
            renderer.scale = scale
            guard let image = renderer.cgImage else {
                print("\(row.name): render failed")
                continue
            }
            let rowBottom = CGFloat(rowTop - rowHeights[index])
            context.draw(image, in: CGRect(x: 0, y: rowBottom, width: CGFloat(image.width), height: CGFloat(image.height)))

            // The hardware notch, translucent, so anything hidden behind the
            // cutout is obvious.
            let hardware = CGRect(x: (notch.minX - regionMinX) * scale,
                                  y: rowBottom + CGFloat(image.height) - notch.height * scale,
                                  width: notch.width * scale, height: notch.height * scale)
            context.setFillColor(CGColor(srgbRed: 0.6, green: 0.05, blue: 0.05, alpha: 0.4))
            context.fill(hardware)

            context.setStrokeColor(CGColor(srgbRed: 0.2, green: 1, blue: 0.4, alpha: 0.9))
            context.setLineWidth(1)
            for rect in row.targets {
                let topInRow = (regionTop - rect.maxY) * scale
                let cg = CGRect(x: (rect.minX - regionMinX) * scale,
                                y: rowBottom + CGFloat(image.height) - topInRow - rect.height * scale,
                                width: rect.width * scale, height: rect.height * scale)
                context.stroke(cg.insetBy(dx: 0.5, dy: 0.5))
            }
            print(String(format: "row %d: %@ (%.0f x %.0f, %d target(s))", index, row.name,
                         row.frame.width, row.frame.height, row.targets.count))
            rowTop -= rowHeights[index]
        }

        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let name = filter.map { "surface-\($0)" } ?? "surface-snapshots"
        let file = url.appendingPathComponent("\(name).png")
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) else { return 1 }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        print(file.path)
        return 0
    }

    struct Row {
        var name: String
        var state: IslandState
        var frame: CGRect
        var content: AnyView
        var targets: [CGRect] = []
    }

    // MARK: - Teleprompter

    static let sampleScript = """
    Good morning everyone, and thanks for making the time.

    I want to walk through three things today: where the release stands, what \
    changed since last week, and what we still need a decision on.

    First, the release. We closed the last two blocking bugs on Tuesday, and \
    the build has been green since. Second, the changes. Third, the decision.
    """

    static func teleprompterRows(geometry: NotchGeometry) -> [Row] {
        let notchInset = geometry.notchFrame.height
        let readFrame = geometry.frame(for: .teleprompter, content: .default)
        let targets = TeleprompterLayout.actions(in: readFrame).map(\.rect)
            + [TeleprompterLayout.readingFrame(in: readFrame, notchInset: notchInset)]

        var atTop = TeleprompterState()
        atTop.load(sampleScript)
        atTop.scrollDistance = 400

        var midway = atTop
        let start = Date().addingTimeInterval(-6)
        midway.play(now: start)
        midway.setSpeedIndex(4, now: start)

        var paused = atTop
        paused.play(now: start)
        paused.pause(now: Date())

        var compose = TeleprompterState()
        compose.load(sampleScript)
        var blank = TeleprompterState()
        blank.mode = .compose

        var rows: [Row] = []
        for (name, state) in [("at the top, paused", atTop), ("reading at 1.5×", midway), ("paused midway", paused)] {
            rows.append(Row(
                name: "teleprompter — \(name)",
                state: .teleprompter,
                frame: readFrame,
                content: AnyView(TeleprompterView(state: state, notchInset: notchInset,
                                                  size: readFrame.size, onMeasure: { _ in })),
                targets: targets
            ))
        }
        let composeFrame = geometry.frame(for: .teleprompterCompose, content: .default)
        for (name, state) in [("empty", blank), ("with a script", compose)] {
            rows.append(Row(
                name: "teleprompter compose — \(name)",
                state: .teleprompterCompose,
                frame: composeFrame,
                content: AnyView(TeleprompterComposeView(
                    script: .constant(state.script), onStart: {}, onOpenFile: {}, onPaste: {}, onClose: {}
                ))
            ))
        }
        return rows
    }

    // MARK: - Dashboard

    /// The dashboard's quick-action bar, which gained the teleprompter and
    /// camera chips — the one place the new features had to fit into an
    /// existing row without crowding it — and then the lid chip, with the
    /// timer's chip down to its glyph. Its looks: the lid switch off, on and
    /// keeping the Mac awake (lit), on but paused (the dot); the stopwatch
    /// running (lit); and the status crowded — a focus mode and a live
    /// camera or mic — at this screen's width, at a 1280-pt screen's panel
    /// (the battery gives way, the focus stays) and at the narrowest (a
    /// 1024-pt screen), where only the live glyph stays; the chips stay on
    /// their targets throughout. Each lid look goes through
    /// `DashboardLidChip`, as in the app.
    static func dashboardRows(geometry: NotchGeometry) -> [Row] {
        let frame = geometry.frame(for: .interactive, content: .default)
        let notchInset = geometry.notchFrame.height
        let event = UpcomingEvent(title: "Design review", startsAt: Date().addingTimeInterval(900),
                                  joinURL: URL(string: "https://meet.google.com/abc-defg-hij"))
        let focus = DashboardFocus.event(joinable: true)
        func panel(screenWidth: CGFloat) -> CGRect {
            let width = (screenWidth * NotchGeometry.interactiveWidthFraction).rounded(.down)
            return CGRect(x: frame.midX - width / 2, y: frame.minY, width: width, height: frame.height)
        }
        let lidOn = LidAwakeSettings(enabled: true)
        let lidOff = LidSettingsModel(status: .normal, helperInstalled: true)
        let lidAwake = LidSettingsModel(settings: lidOn, status: .awake, helperInstalled: true)
        let lidPaused = LidSettingsModel(settings: lidOn, status: .held(.onBattery), helperInstalled: true)
        func row(_ name: String, frame: CGRect = frame, lid: LidSettingsModel = lidOff, timerRunning: Bool = false,
                 focusMode: String? = nil, mic: Bool = false, camera: Bool = false, charging: Bool = false) -> Row {
            Row(
                name: "dashboard — \(name)",
                state: .interactive,
                frame: frame,
                content: AnyView(DashboardView(
                    notchInset: notchInset, focus: focus, nextEvent: event,
                    nowPlayingTitle: nil, nowPlayingArtist: nil,
                    weatherSymbol: "cloud.sun.fill", weatherLabel: "18°",
                    batteryPercent: 76, isCharging: charging, focusMode: focusMode,
                    isMicActive: mic, isCameraActive: camera,
                    lid: lid, isTimerRunning: timerRunning, timerEnabled: true,
                    isTeleprompting: false, teleprompterEnabled: true,
                    isCameraPreviewing: false, cameraEnabled: true,
                    trayCount: 12
                )),
                targets: DashboardLayout.actions(in: frame, notchInset: notchInset, focus: focus).map(\.rect)
            )
        }
        return [
            row("quick actions, the lid switch off"),
            row("the lid on, keeping the Mac awake", lid: lidAwake),
            row("the lid on, paused", lid: lidPaused),
            row("the timer running", timerRunning: true),
            row("a focus mode and a live camera", lid: lidPaused, focusMode: "Do Not Disturb", camera: true),
            row("a 1280-pt screen's panel, charging, a focus mode and a live mic", frame: panel(screenWidth: 1280),
                lid: lidAwake, focusMode: "Personal", mic: true, charging: true),
            row("the narrowest panel, a focus mode and a live mic", frame: panel(screenWidth: 1024), lid: lidAwake,
                timerRunning: true, focusMode: "Do Not Disturb", mic: true),
        ]
    }

    // MARK: - Settings

    /// The settings panel's NEO section — NEO.app's menu, carried here while
    /// the notch hosts NEO — in each state NEO can be in: running with
    /// everything allowed, missing a permission, a core with no NEO.app, not
    /// running, and switched off — and with "Listen for “Neo”" off (the
    /// microphone only while summoned) and with "Show NEO's timers" off, and
    /// with NEO's Brain row: a brain set up, none yet, one that can't answer.
    /// Plus the features page, for the NEO tile that opens the section. (No scroll
    /// view: an image renderer cannot draw one.)
    static func settingsRows(geometry: NotchGeometry) -> [Row] {
        let frame = geometry.frame(for: .settings, content: .default)
        let ready = NeoShellStatus(app: true, accessibility: true, screenRecording: true, openAtLogin: true, version: "2.1.0", hotkey: "⌥⌘")
        var missing = ready
        missing.screenRecording = false
        missing.openAtLogin = false
        let listens = NeoCoreSettings(wakeWord: true)
        let cases: [(String, SettingsView.Page, NeoSettingsModel)] = [
            ("features, with NEO's tile", .features, NeoSettingsModel(featureOn: true, connected: true, shell: ready, core: listens)),
            ("NEO — running", .neo, NeoSettingsModel(featureOn: true, connected: true, shell: ready, core: listens)),
            ("NEO — the wake word off", .neo, NeoSettingsModel(featureOn: true, connected: true, shell: ready, core: NeoCoreSettings(wakeWord: false))),
            ("NEO — a permission missing", .neo, NeoSettingsModel(featureOn: true, connected: true, shell: missing, core: listens)),
            ("NEO — a core without NEO.app", .neo, NeoSettingsModel(featureOn: true, connected: true, shell: NeoShellStatus())),
            ("NEO — not running", .neo, NeoSettingsModel(featureOn: true, connected: false, shell: ready)),
            ("NEO — off", .neo, NeoSettingsModel(featureOn: false, connected: false, shell: nil)),
        ]
        // The pet's page comes LAST, after every row that was here before it.
        var customised = IslandSettings()
        customised.pet.usesCustomFur = true
        customised.pet.accessory = .scarf
        customised.pet.size = .large
        customised.pet.home = .left
        customised.pet.sleepsAtNight = true
        customised.pet.name = "Biscuit"
        let petRows = [("Pet — as it opens", IslandSettings()), ("Pet — customised", customised)].map { name, settings in
            Row(
                name: "settings — \(name)",
                state: .settings,
                frame: frame,
                content: AnyView(SettingsView(settings: .constant(settings), onChange: {}, page: .pet, scrolls: false))
            )
        }
        func neoRow(_ name: String, _ page: SettingsView.Page, _ model: NeoSettingsModel) -> Row {
            var settings = IslandSettings()
            settings.neo = model.featureOn
            return Row(
                name: "settings — \(name)",
                state: .settings,
                frame: frame,
                content: AnyView(SettingsView(
                    settings: .constant(settings), onChange: {}, neo: model, page: page, scrolls: false
                ))
            )
        }
        // NotchHub's own "Show NEO's timers" switched off — after the pet's
        // page, so every row before keeps its place.
        let timersOff = NeoSettingsModel(featureOn: true, connected: true, shell: ready, core: listens, showsTimers: false)
        // NEO's brains, as its core reports them (Brains & Keys) — last, so
        // every row before keeps its place: a brain set up; none yet ("Set
        // up…" opens NEO.app's window); and a chosen brain that cannot answer
        // (its key refused) under the longest name the core sends.
        let brainReady = NeoBrainStatus(ready: true, brain: "Claude Opus 5.5", quick: "Claude Haiku 5.5", brainOK: true, voice: "live")
        let noBrain = NeoBrainStatus(ready: false, brain: "Gemini 3.8 Flash", quick: "Gemini 3.8 Flash", brainOK: false, voice: "local")
        let longName = "Research Lab · " + String(repeating: "m", count: 40) + "-preview-0917"
        let brainRefused = NeoBrainStatus(ready: true, brain: String(longName.prefix(NeoBrainStatus.labelLimit)), brainOK: false)
        let brainRows = [
            ("NEO — a brain set up", brainReady),
            ("NEO — no brain yet", noBrain),
            ("NEO — its brain can't answer, a long name", brainRefused),
        ].map { name, status in
            neoRow(name, .neo, NeoSettingsModel(featureOn: true, connected: true, shell: ready, core: listens, brain: status))
        }
        return cases.map { neoRow($0.0, $0.1, $0.2) } + petRows + [neoRow("NEO — its timers off the island", .neo, timersOff)] + brainRows
    }

    // MARK: - Lid

    /// Settings → Lid ("Keep working with the lid closed") in its states,
    /// and the features page with its Lid card — after every other settings
    /// row, so those keep their places. The page is drawn whole (taller than
    /// the panel, which scrolls), at a fixed clock.
    static func lidRows(geometry: NotchGeometry) -> [Row] {
        let panel = geometry.frame(for: .settings, content: .default)
        let tall = CGRect(x: panel.minX, y: panel.maxY - 800, width: panel.width, height: 800)
        let now = Date(timeIntervalSince1970: 1_760_350_000)
        let icon = NSWorkspace.shared.icon(for: .application)
        let agent = LidAppRow(bundleID: "com.example.agent", name: "Agent Studio", icon: icon, isOpen: true)
        let chat = LidAppRow(bundleID: "com.example.chat", name: "Chat", icon: icon, isOpen: false)
        let candidates = LidAppChoices(chosen: [], candidates: [agent, chat])
        let both = LidAppChoices(chosen: [agent, chat], candidates: [])

        var awake = LidAwakeSettings(enabled: true, onlyWhileApps: true, apps: [agent.bundleID, chat.bundleID],
                                     autoOffHours: 2, clockStart: now.addingTimeInterval(-1800))
        awake.keepAfterQuit = false
        let floor = LidAwakeSettings(enabled: true, onlyOnPower: false, batteryFloor: 25)
        let cases: [(String, LidSettingsModel, LidAppChoices)] = [
            ("as it opens: off, the helper not set up", LidSettingsModel(status: .normal), candidates),
            ("keeping the Mac awake: two apps, a 2 h clock", LidSettingsModel(
                settings: awake, status: .awake, helperInstalled: true, openApps: [agent.bundleID]), both),
            ("paused on battery", LidSettingsModel(
                settings: LidAwakeSettings(enabled: true), status: .held(.onBattery), helperInstalled: true), candidates),
            ("the battery floor at 25 % (adapter guard off)", LidSettingsModel(
                settings: floor, status: .held(.batteryLow(floor: 25)), helperInstalled: true), candidates),
            ("needs your password to resume", LidSettingsModel(
                settings: LidAwakeSettings(enabled: true), status: .needsYou, helperInstalled: true, helperRefused: true), candidates),
            ("sleep turned off outside NotchHub", LidSettingsModel(status: .outside), candidates),
        ]
        func row(_ name: String, _ page: SettingsView.Page, _ model: LidSettingsModel, _ apps: LidAppChoices, frame: CGRect) -> Row {
            Row(
                name: "settings — \(name)",
                state: .settings,
                frame: frame,
                content: AnyView(SettingsView(
                    settings: .constant(IslandSettings()), onChange: {}, lid: model, lidApps: apps, lidNow: now,
                    page: page, scrolls: false
                ))
            )
        }
        let features = row("Lid card on the features page, keeping awake", .features,
                           LidSettingsModel(settings: awake, status: .awake, helperInstalled: true), both, frame: tall)
        return [features] + cases.map { row("Lid — \($0.0)", .lid, $0.1, $0.2, frame: tall) }
    }

    // MARK: - Camera

    static func cameraRows(geometry: NotchGeometry) -> [Row] {
        let notchInset = geometry.notchFrame.height
        let devices = [
            CameraDevice(id: "built-in", name: "FaceTime HD Camera"),
            CameraDevice(id: "iphone", name: "iPhone"),
        ]
        let cases: [(String, CameraState)] = [
            ("starting", CameraState(phase: .starting)),
            ("live, small (no picture headless)", CameraState(phase: .live, devices: devices, deviceID: "built-in")),
            ("live, expanded", CameraState(phase: .live, devices: devices, deviceID: "built-in", isExpanded: true)),
            ("denied", CameraState(phase: .failed(.permissionDenied))),
            ("no device", CameraState(phase: .failed(.noDevice))),
        ]
        return cases.map { name, state in
            let frame = geometry.cameraFrame(expanded: state.isExpanded)
            return Row(
                name: "camera — \(name)",
                state: state.isExpanded ? .cameraExpanded : .camera,
                frame: frame,
                content: AnyView(CameraView(state: state, previewLayer: nil)),
                targets: CameraLayout.actions(in: frame, state: state).map(\.rect)
                    + [CameraLayout.pictureFrame(in: frame, notchInset: notchInset)]
            )
        }
    }
}
