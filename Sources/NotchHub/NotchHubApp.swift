import AppKit
import NotchHubCore
import NotchHubSystem
import SwiftUI

/// The NotchHub application object.
///
/// Owns the notch window and the activity queue. There is no menu-bar item:
/// settings (with Quit) open from the hotkey, a panel's "···" or a right-click.
/// The island is a single window whose SwiftUI content morphs between shapes;
/// this object is the coordinator between the queue and the view.
///
/// Layering: **system listeners → events → bridge → activity queue → island**.
/// This object is the only place those layers meet. It never inspects the
/// system itself; it subscribes to the monitor's bus, applies the bridge's
/// instructions to the queue, and keeps the non-activity state (wing status,
/// panels) the bridge tells it to refresh.
///
/// The coordinator is split across files by concern:
/// - `NotchHubApp.swift` — state, events, rendering, the ticker
/// - `NotchHubApp+LaunchModes.swift` — launch flags, demos, inspection hooks
/// - `NotchHubApp+Panels.swift` — Tray, settings, dictation, file drop, hotkeys
/// - `NotchHubApp+Meeting.swift` — live-call controls
/// - `NotchHubApp+Interaction.swift` — hover, click, media, context menu
@MainActor
final class NotchHubApp: NSObject, NSApplicationDelegate {

    var window: NotchWindow!
    var hostingView: NSHostingView<IslandRootView>!
    let queue = ActivityQueue()

    /// The island's observable state. The hosted view is created once around
    /// this model and left stable, so every transition springs smoothly instead
    /// of re-installing the view tree.
    let islandModel = IslandModel()

    // The system layer. Feature settings gate which listeners get created at
    // all; the monitor is rebuilt when they change, so toggling a feature off
    // actually stops its listener rather than just hiding the UI.
    var featureSettings = FeatureSettings.load()
    var monitor: SystemMonitor?
    /// When the monitor last (re)started. Listeners report their current state
    /// as they start; for a moment afterwards nothing is announced as news.
    var monitorStartedAt: Date?
    static let monitorSettlePeriod: TimeInterval = 2.5
    /// A pending weather-city change, applied once typing pauses.
    var pendingCityApply: Task<Void, Never>?
    /// A pending listener update, applied once toggling settles.
    var pendingMonitorUpdate: Task<Void, Never>?
    static let weatherCityKey = "NotchHub.weatherCity"

    /// The island's own stopwatch. Its ticks drive the timer activity.
    lazy var timerService = TimerService { [weak self] event in
        self?.handle(event)
    }

    // The Tray: the clipboard history, restored from disk on launch.
    var trayStore = TrayPersistence.load()
    var traySearch = ""
    var trayFilter: TrayFilter = .all

    // Dictation, on-device.
    lazy var dictation = DictationController { [weak self] event in
        self?.handle(event)
    }
    var dictationSession = DictationSession()

    // Live surfaces carrying richer state than an Activity can hold.
    var meeting: Meeting?
    var skin: AppSkin?
    /// Details about the frontmost app (page, agent session, window title).
    var appContext: AppContextSnapshot?
    /// The user switched an app panel to the dashboard (its clock). Reset once
    /// the panel closes.
    var showsDashboardOverApp = false

    // The pixel pet.
    var petBrain = PetBrain()
    var petSettings = PetSettings.load()
    var petHovered = false
    var petCursorSide: PetContext.Side?
    var petWakeTask: Task<Void, Never>?
    var petWakeAt: Date?
    /// The island edge beside the pet when it was clicked: the pet panel hangs
    /// from there, under the pet and the cursor.
    var petPanelAnchor: PetPanelAnchor?
    /// Sleep was chosen in the pet panel during this hover; see `petContext`.
    var petSleepHoverSession = false
    /// Strokes on the big pet in its panel.
    var petStroke = PetStrokeDetector()
    /// Today's holiday, worked out once a day.
    var holidayCache: (day: String, holiday: PetHoliday?)?
    /// Waits for the next day's holiday greeting.
    var holidayTask: Task<Void, Never>?
    /// The latest weather reading, held for the wings. It is NOT an activity —
    /// pushing it as one kept the island permanently out of idle.
    var weatherActivity: Activity?

    // Persistent wing status. The wings show what is *currently true* about the
    // machine, so these are held here and updated by events rather than read
    // from the activity queue, whose entries auto-dismiss.
    var batteryPercent: Int?
    var isCharging = false
    var focusMode: String?
    var isMicActive = false
    var isCameraActive = false
    var wifiConnected = false
    var musicTitle: String?
    /// The next calendar event, for the dashboard.
    var nextEvent: UpcomingEvent?
    /// The running stopwatch's elapsed time, for the dashboard's timer chip.
    var timerElapsed: TimeInterval?

    /// The settings panel's view model, seeded from the persisted features and
    /// the separately-stored weather city.
    lazy var settingsModel: IslandSettings = {
        var model = IslandSettings(featureSettings: featureSettings)
        model.weatherCity = UserDefaults.standard.string(forKey: Self.weatherCityKey) ?? ""
        model.petSettings = petSettings
        return model
    }()

    /// A panel that temporarily replaces the queue-driven island.
    enum Panel { case none, tray, dictation, settings, fileDrop, pet }
    var panel: Panel = .none

    /// The live file-sharing session.
    var fileDropURLs: [URL] = []
    var fileDropPhase: FileDropPhase = .idle

    var hotKeys: [HotKey] = []

    // Island presentation state — owned by the state machine.
    let machine = IslandStateMachine()
    var currentActivity: Activity? { machine.activity }

    // A timer that drives auto-dismiss and live readouts.
    var ticker: Timer?

    /// `--wings`: hold the sideways peek open for on-screen inspection.
    var holdWings = false

    // Demo state (elapsed timers) so previews feel alive.
    var demoStart: Date?
    /// Artwork loaded from `--art <path>`.
    var demoArtwork: Data?

    /// Fades the black surface out once it has drained back into the notch.
    var surfaceFadeTask: Task<Void, Never>?
    /// Collapses the island exactly when the hover-exit grace period ends,
    /// instead of on whichever 0.5 s tick happens to come next.
    var hoverCollapseTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let geometry = NotchGeometry.detectMain()

        window = NotchWindow(geometry: geometry)
        window.onHoverEnter = { [weak self] in self?.islandHoverEntered() }
        window.onHoverExit = { [weak self] in self?.islandHoverExited() }
        window.onMouseMove = { [weak self] point in self?.petMouseMoved(point) }
        window.onClick = { [weak self] in self?.islandClicked() }
        window.onControlHit = { [weak self] point in
            guard let self else { return false }
            return self.petControlHit(at: point)
                || self.meetingControlHit(at: point)
                || self.dashboardControlHit(at: point)
                || self.wingsControlHit(at: point)
                || self.appPanelControlHit(at: point)
        }
        window.onTransportHit = { [weak self] point in
            self?.visibleTransport().flatMap { MediaControlLayout.command(at: point, in: $0) }
        }
        window.onMediaCommand = { [weak self] command in self?.mediaCommand(command) }
        window.onCancel = { [weak self] in self?.dismissInteractivePanel() }
        window.onFileDraggedIn = { [weak self] in self?.fileDraggedIn() }
        window.onFileDraggedOut = { [weak self] in self?.fileDraggedOut() }
        window.onFileDropped = { [weak self] urls in self?.fileDropped(urls) }
        window.rightClickMenu = { [weak self] in self?.contextMenu() ?? NSMenu() }
        islandModel.cornerRadius = geometry.cornerRadius
        islandModel.notchInset = geometry.notchFrame.height
        islandModel.notchWidth = geometry.notchFrame.width
        islandModel.hasNotch = geometry.hasNotch
        islandModel.localFrame = window.swiftUIFrame(for: .idle)
        hostingView = NSHostingView(rootView: IslandRootView(model: islandModel))
        window.installContent(hostingView)
        window.apply(state: .idle)
        window.orderFrontRegardless()

        registerHotKeys()

        startTicker()
        startLaunchMode()
    }

    func applicationWillTerminate(_ notification: Notification) {
        ticker?.invalidate()
        monitor?.stop()
    }

    func log(_ message: @autoclosure () -> String) {
        NotchLog.debug(message())
    }

    // MARK: - System monitor

    /// Builds the monitor for the current feature settings, subscribes the
    /// island to its bus, and starts it.
    func startMonitor() {
        scheduleHolidayGreeting()
        monitor?.stop()
        let newMonitor = SystemMonitor.defaultMonitor(settings: featureSettings)
        newMonitor.bus.subscribe { [weak self] event in
            self?.handle(event)
        }
        monitor = newMonitor
        monitorStartedAt = Date()
        newMonitor.start()
        log("monitor: \(newMonitor.listenerNames.count) listeners \(newMonitor.listenerNames)")
    }

    /// Applies the settings panel's model.
    ///
    /// The panel redraws at once; the system work follows. A toggle used to
    /// rebuild EVERY listener synchronously on the main thread — calendar store,
    /// process table, browser scripting, app icons — so each tap froze before
    /// the switch moved. Now the feature set is saved immediately, and shortly
    /// after the last tap the monitor starts or stops only the listeners whose
    /// feature changed. The weather city is applied once typing pauses and
    /// restarts only the weather listener.
    func applySettings(_ model: IslandSettings) {
        applyPetSettings(model.petSettings)
        let features = model.toFeatureSettings()
        if features != featureSettings {
            featureSettings = features
            featureSettings.save()
            if !featureSettings.isEnabled(.calendar) {
                nextEvent = nil
            }
            scheduleMonitorUpdate()
        }

        let city = model.weatherCity.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedCity = UserDefaults.standard.string(forKey: Self.weatherCityKey) ?? ""
        guard city != storedCity else { return }
        pendingCityApply?.cancel()
        pendingCityApply = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled, let self else { return }
            UserDefaults.standard.set(city, forKey: Self.weatherCityKey)
            if city.isEmpty {
                self.weatherActivity = nil
                self.refreshIsland()
            }
            self.monitor?.restart { $0 is WeatherListener }
            self.log("settings: weather city applied")
        }
    }

    /// Brings the running listeners in line with `featureSettings` once the
    /// taps settle, touching only the listeners that changed.
    func scheduleMonitorUpdate() {
        pendingMonitorUpdate?.cancel()
        pendingMonitorUpdate = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, let self, let monitor = self.monitor else { return }
            let changes = monitor.update(settings: self.featureSettings)
            if changes.added > 0 {
                // New listeners report their starting state; that is not news.
                self.monitorStartedAt = Date()
            }
            self.log("settings: +\(changes.added) −\(changes.removed) listeners")
        }
    }

    // MARK: - Events

    /// Routes one system event: records the state the app keeps for the wings
    /// and panels, then applies the bridge's instructions to the queue.
    func handle(_ event: SystemEvent) {
        petObserve(event)
        record(event)

        let instructions = ActivityBridge.instructions(for: event)
        guard !instructions.isEmpty else { return }

        for instruction in instructions {
            switch instruction {
            case let .present(activity): queue.push(activity)
            case let .presentTransient(activity):
                // Right after listeners start (launch, or a settings change
                // rebuilding the monitor) they report the state they found.
                // That is recorded above, but it is not news.
                if let started = monitorStartedAt,
                   Date().timeIntervalSince(started) < Self.monitorSettlePeriod {
                    continue
                }
                queue.focusTemporarily(activity)
            case let .upsert(activity): queue.upsert(activity)
            case let .remove(kind): queue.remove(kind: kind)
            case .refresh: break
            }
        }
        log("event: \(event.source.rawValue) → \(instructions.count) instruction(s)")
        renderQueue()
    }

    /// Records the state that outlives any activity: wing status, the Tray,
    /// panels, and live surfaces.
    func record(_ event: SystemEvent) {
        switch event.payload {
        case let .battery(percent, charging, _):
            batteryPercent = percent
            isCharging = charging
        case let .wifi(_, connected):
            wifiConnected = connected
        case let .network(name):
            wifiConnected = !name.isEmpty
        case let .nowPlaying(title, _, isPlaying, _, _):
            musicTitle = isPlaying ? title : nil
        case .nowPlayingStopped:
            musicTitle = nil
        case let .focus(active, name):
            focusMode = active ? (name ?? "Focus") : nil
        case let .privacy(camera, microphone):
            isMicActive = microphone
            isCameraActive = camera
        case let .clipboardCaptured(clip):
            log("clipboard: captured kind=\(clip.kind)")
            trayStore.add(clip)
            TrayPersistence.save(trayStore)
        case let .dictation(session):
            dictationSession = session
            if session.isActive {
                panel = .dictation
            } else if panel == .dictation {
                panel = .none
            }
        case let .meetingStarted(meeting), let .meetingUpdated(meeting):
            // A state the listener could not read is a guess: keep ours.
            var incoming = meeting
            if let previous = self.meeting, previous.app == incoming.app, previous.callURL == incoming.callURL {
                if !incoming.knownStates.contains(.mute) { incoming.isMuted = previous.isMuted }
                if !incoming.knownStates.contains(.camera) { incoming.isCameraOn = previous.isCameraOn }
            }
            self.meeting = incoming
        case .meetingEnded:
            meeting = nil
        case let .frontmostApp(skin):
            // A skin is NOT an activity: it is the island's resting face.
            self.skin = skin
            if appContext?.bundleID != skin?.bundleID {
                appContext = nil
            }
        case let .appContext(snapshot):
            appContext = snapshot
        case let .weather(temperature, condition, symbol):
            weatherActivity = Activity(
                kind: .custom,
                title: condition,
                subtitle: "\(Int(temperature.rounded()))°",
                symbol: symbol
            )
        case let .calendarNext(event):
            nextEvent = event
        case let .timerTick(elapsed):
            timerElapsed = elapsed
        case .timerFinished:
            timerElapsed = nil
        default:
            break
        }
    }

    // MARK: - Queue → island

    func present(_ activity: Activity) {
        queue.push(activity)
        renderQueue()
    }

    /// A transient event that briefly takes the island, then returns to the
    /// persistent activity (exactly the music → volume → music flow).
    func presentTransient(_ activity: Activity) {
        queue.focusTemporarily(activity)
        renderQueue()
    }

    /// Re-renders the island from the machine's current presentation.
    func refreshIsland() {
        renderIsland()
    }

    /// Mirrors the queue into the state machine, then renders.
    func renderQueue() {
        queue.tick(now: Date())
        let current = queue.current

        machine.setActivity(current)
        if current == nil {
            if !machine.isHovering {
                machine.send(.activityEnded)
            }
        } else {
            machine.send(.activityStarted)
        }
        renderIsland()
    }

    /// Pushes the current surface into the window and view.
    ///
    /// This is the ONLY place an island transition is animated — callers never
    /// wrap it in `withAnimation`. Nested transactions override one another,
    /// which is how every collapse used to ride the generic morph spring. The
    /// motion is derived from the before/after frames (`IslandMotion`), so the
    /// same change always moves the same way.
    ///
    /// A panel (Tray, dictation) or a call's expanded controls take their own
    /// shape; otherwise the island follows the state machine. The window itself
    /// never resizes — only the island inside it does.
    func renderIsland(stackCount: Int? = nil) {
        if machine.presentation != .interactive {
            showsDashboardOverApp = false
        }
        if currentIslandState() == .idle {
            petSleepHoverSession = false
        }
        let petUpdate = updatePet()
        let state = currentIslandState()
        let status = wingStatus()
        let contentSize = computeContentSize(state: state, status: status)
        let panel = panelContent()
        window.apply(state: state, content: contentSize)

        let model = islandModel
        let frame = window.swiftUIFrame(for: state, content: contentSize)
        let isIdle = state == .idle
        let wasIdle = model.isIdle
        let surfaceChanged = model.state != state
            || model.localFrame != frame
            || model.current?.id != machine.activity?.id
            || (model.panelContent == nil) != (panel == nil)
        let motion: IslandMotion = surfaceChanged
            ? IslandMotion.between(from: model.localFrame, fromIdle: wasIdle, to: frame, toIdle: isIdle)
            : .none

        // With the pet shown, idle keeps a small black dock beside the notch.
        if !isIdle || petDocked {
            surfaceFadeTask?.cancel()
            surfaceFadeTask = nil
            if !model.surfaceVisible {
                // Emerging: the surface starts at the notch's own size, hidden
                // behind the physical notch, so it can be opaque at once.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { model.surfaceVisible = true }
            }
        }

        func apply() {
            model.current = machine.activity
            model.stackCount = stackCount ?? queue.stackCount
            model.state = state
            model.contentSize = contentSize
            model.localFrame = frame
            model.isIdle = isIdle
            model.wingStatus = status
            model.panelContent = panel
            model.meeting = meeting
            // In the same transaction as the shape, so the pet's move from where
            // it was drawn rides the island's spring.
            publishPet(petUpdate)
        }

        if let animation = DesignTokens.animation(for: motion) {
            withAnimation(animation) { apply() }
            log("motion: \(motion.rawValue) → \(state)")
        } else {
            apply()
        }

        // While idle, only the pet itself (not its whole dock) takes the mouse.
        window.idlePetFrame = isIdle && petOnScreen ? petRect() : nil
        clearStalePetHover()

        if isIdle, !wasIdle, !petDocked {
            scheduleSurfaceFade()
        }
    }

    /// Fades the surface once the retract has carried it home. Cancelled if the
    /// island re-emerges first, so a quick re-hover never flickers.
    func scheduleSurfaceFade() {
        surfaceFadeTask?.cancel()
        surfaceFadeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(DesignTokens.retractFadeDelay * 1_000_000_000))
            guard !Task.isCancelled, let self, self.islandModel.isIdle else { return }
            withAnimation(DesignTokens.surfaceFade) {
                self.islandModel.surfaceVisible = false
            }
        }
    }

    func computeContentSize(state: IslandState, status: WingStatus) -> IslandContentSize {
        switch state {
        case .appPanel:
            var size = IslandContentSize.default
            size.panelHeight = appPanelHeight()
            return size
        case .wings:
            let sides = IslandMetrics.wings(status, petSlot: petBarReserve)
            var size = IslandContentSize(compactLead: 0, compactTrail: 0, wingSide: sides.trail)
            size.wingLead = sides.lead
            return size
        case .compact:
            guard let current = machine.activity else { return .default }
            return IslandMetrics.compact(current, petSlot: petBarReserve)
        case .idle:
            var size = IslandContentSize.default
            size.petDock = petIdleDock
            return size
        case .skin:
            var size = IslandContentSize.default
            size.panelAnchor = panel == .pet ? petPanelAnchor : nil
            return size
        default:
            return .default
        }
    }

    /// The shape the island should take right now.
    ///
    /// Panels outrank the state machine. A call shows as an ordinary compact
    /// bar; its control panel is a deliberate detail surface, so it appears
    /// only once the island is expanded (hover or click) — it must not hang a
    /// large panel over the screen for the whole length of a call.
    func currentIslandState() -> IslandState {
        switch panel {
        case .tray: return .tray
        case .dictation: return .dictation
        case .settings: return .settings
        case .fileDrop: return .fileDrop
        case .pet: return .skin
        case .none: break
        }
        if machine.activity?.kind == .meeting, machine.presentation == .expanded {
            return .meeting
        }
        let state = islandState(for: machine.presentation)
        // A click opens the frontmost app's own panel when it has one; the
        // panel's clock switches to the dashboard.
        if state == .interactive, appPanelAvailable, !showsDashboardOverApp {
            return .appPanel
        }
        return state
    }

    /// Maps the machine's presentation onto the window's shape.
    func islandState(for presentation: IslandPresentation) -> IslandState {
        switch presentation {
        case .idle: return .idle
        case .wings: return .wings
        case .compact: return .compact
        case .expanded: return .expanded
        case .interactive: return .interactive
        }
    }

    // MARK: - Wings

    /// What the two wings show while the island is in its sideways peek.
    func wingStatus() -> WingStatus {
        WingStatus(
            left: wingAppItem(),
            right: wingStatusItems(),
            musicPlaying: musicTitle != nil,
            strip: appStrip()
        )
    }

    /// The left wing: the frontmost app, with its real icon when we have one.
    func wingAppItem() -> WingItem? {
        guard let skin else { return nil }
        return WingItem(symbol: skin.symbol, iconData: skin.iconData, label: skin.name)
    }

    /// The right wing: the small live facts worth a glance, in the order they
    /// matter.
    func wingStatusItems() -> [WingItem] {
        var items: [WingItem] = []

        // Charging is the one battery status that wants attention.
        if isCharging {
            items.append(WingItem(
                symbol: "battery.100.bolt",
                label: batteryPercent.map { "\($0)%" },
                tint: .accent
            ))
        }
        if let musicTitle {
            items.append(WingItem(symbol: "music.note", label: musicTitle, tint: .accent))
        }
        if let focusMode {
            items.append(WingItem(symbol: "moon.fill", label: focusMode))
        }
        if wifiConnected {
            items.append(WingItem(symbol: "wifi", label: "Wi-Fi"))
        }
        if let weather = weatherActivity {
            items.append(WingItem(symbol: weather.resolvedSymbol, label: weather.subtitle))
        }
        return items
    }

    // MARK: - Ticker

    func startTicker() {
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    func tick() {
        let now = Date()
        // Advance a demo stopwatch (the real one ticks through TimerService).
        if let start = demoStart, !timerService.isRunning,
           let current = currentActivity, current.kind == .timer {
            queue.update(id: current.id, elapsed: now.timeIntervalSince(start))
        }

        // Let the state machine auto-collapse / auto-dismiss, then re-render if
        // the presentation or the queue changed.
        let presentationBefore = machine.presentation
        machine.tick(now)
        if holdWings, machine.presentation != .wings {
            machine.forceWings()
        }
        let changed = queue.tick(now: now)

        if NotchLog.isVerbose {
            let loc = NSEvent.mouseLocation
            let state = islandState(for: machine.presentation)
            let frame = window.localFrame(for: state, content: islandModel.contentSize)
            let win = window.frame
            let panelName = panel == .none ? "none" : "\(panel)"
            log("mouse=\(Int(loc.x)),\(Int(loc.y)) island=\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width))x\(Int(frame.height)) window=\(Int(win.width))x\(Int(win.height)) inside=\(frame.contains(loc)) state=\(machine.presentation) panel=\(panelName) islandState=\(currentIslandState()) key=\(window.isKeyWindow) needsInt=\(window.needsInteraction)")
        }

        if machine.presentation != presentationBefore || !changed.isEmpty || currentActivity != queue.current {
            renderQueue()
        }
    }
}
