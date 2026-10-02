import AppKit
import NotchHubCore
import NotchHubSystem
import SwiftUI

/// The pixel pet: a tiny companion living in the notch — and NEO itself.
/// While NEO's core is connected the pet is on screen whatever Show Pet
/// says, and while NEO is busy its pose is what NEO is doing
/// (`PetContext.neoState`, `PetBrain.neoAnimation`).
///
/// Architecture — the pet never looks at views:
/// island state (activities, wing status, panels) → `petContext()` →
/// `PetBrain` (the Pet State Manager) → `PetPresentation` + `PetDock` →
/// `PetView` and the idle island's shape.
/// System events become `PetEvent`s in `petObserve`, BEFORE `record` updates
/// the state they are compared against. The brain schedules its own next
/// moment (`nextWakeup`), so an idle pet runs no timers in between; a moment
/// that moves its dock (mischief) re-renders the island so the black dock and
/// the pet move as one. With the pet hidden, none of this affects the island.
extension NotchHubApp {

    var petVisible: Bool { petSettings.showPet || neoPresent }

    /// Whether idle keeps the pet's black dock beside the notch. Only on a
    /// display with a notch: elsewhere idle stays fully transparent.
    var petDocked: Bool { petVisible && window.hasNotch }

    /// Room the pet takes at the right of notch-height bars — with the word
    /// "Listening" beside it, for the first moment NEO listens.
    var petBarReserve: CGFloat { petVisible ? PetLayout.barSlot + listeningSlot : 0 }

    /// Room the larger pet takes at the right of the expanded island.
    var petExpandedReserve: CGFloat { petVisible ? PetLayout.expandedReserve + listeningSlot : 0 }

    /// Room NEO's listening mark takes beside the pet in the island as
    /// drawn: its word's, while that shows; nothing for the glow alone.
    var listeningSlot: CGFloat { listeningMark?.slot ?? 0 }

    /// The idle island's dock for the pet, where the brain has it.
    var petIdleDock: PetDock? { petDocked ? petBrain.dock : nil }

    // MARK: - Context

    func petContext() -> PetContext {
        var context = PetContext()
        // After Sleep, the hover the panel closed in still counts until the
        // island really collapses, so pointing back at the pet is not a return.
        context.isHovering = machine.isHovering || petSleepHoverSession
        context.isPetHovered = petHovered
        context.cursorSide = petCursorSide
        context.interactionOpen = panel == .pet
        context.isMusicPlaying = musicTitle != nil
        if let meeting {
            context.inMeeting = true
            // The same values the call controls show, so the pet never disagrees.
            context.meetingMuted = meeting.isMuted
            context.meetingCameraOn = meeting.isCameraOn
        }
        if case let .agent(session)? = currentAppContext?.context {
            context.isAgentWorking = session.isWorking
        }
        // A focus session is its own mood (the laptop), not the stopwatch's clock.
        context.isTimerRunning = timerService.isStopwatchRunning
        context.isFocusing = timerService.isCountingDown
        context.isDownloading = queue.all.contains { $0.kind == .download && $0.autoDismiss == 0 }
        context.isCharging = isCharging
        context.batteryPercent = batteryPercent
        context.idleFlourishes = petSettings.idleAnimations
        context.mischief = petSettings.mischief
        context.canRoam = petDocked && currentIslandState() == .idle
        // A game on the dock needs an island that will come back to rest: a
        // lasting activity (music, a timer, a download, a call) holds it up —
        // even one waiting behind a transient readout.
        context.isDocked = petDocked && !queue.all.contains { $0.autoDismiss == 0 }
        // The pet is NEO: what NEO is doing is its pose.
        context.neoState = neoPresent ? neoPresence.state : nil
        return context
    }

    /// Whether the pet is drawn anywhere right now. Utility panels step it
    /// aside, and idle has no pet without a notch.
    var petOnScreen: Bool {
        if panel == .pet { return true }
        let state = currentIslandState()
        if state == .idle { return window.hasNotch }
        return PetLayout.placement(for: state, islandSize: CGSize(width: 600, height: 300), notchHeight: window.notchHeight) != nil
    }

    /// What `updatePet` found.
    enum PetUpdate {
        /// Show Pet is off.
        case hidden
        /// Nothing on screen draws the pet right now.
        case offScreen
        case shown(PetRenderModel)
    }

    /// Brings the pet up to date and schedules its next moment, without
    /// publishing anything.
    func updatePet() -> PetUpdate {
        guard petVisible else {
            petWakeTask?.cancel()
            petWakeTask = nil
            petWakeAt = nil
            return .hidden
        }
        let now = Date()
        let context = petContext()
        petBrain.update(context, now: now)
        // Off screen: keep the mood current, but schedule nothing — `renderIsland`
        // refreshes the pet the moment it is back.
        guard petOnScreen else {
            petWakeTask?.cancel()
            petWakeTask = nil
            petWakeAt = nil
            return .offScreen
        }
        schedulePetWakeup(context: context, now: now)
        return .shown(PetRenderModel(
            presentation: petBrain.presentation,
            look: petSettings.look,
            hat: petSettings.hat.hat(on: now, holiday: todaysHoliday(now: now))
        ))
    }

    /// Publishes an update, only what changed. `renderIsland` calls this inside
    /// the island's own transaction, so a pose change that comes with a change
    /// of shape rides the same spring.
    func publishPet(_ update: PetUpdate) {
        switch update {
        case .hidden:
            window.idlePetFrame = nil
            if islandModel.pet != nil { islandModel.pet = nil }
        case .offScreen:
            window.idlePetFrame = nil
        case let .shown(model):
            if islandModel.pet != model {
                islandModel.pet = model
                if panel == .pet {
                    // The panel draws its own larger pet: keep it live.
                    islandModel.panelContent = panelContent()
                }
            }
            window.idlePetFrame = currentIslandState() == .idle ? petRect() : nil
        }
    }

    /// Brings the pet up to date and publishes it (outside any island motion).
    func refreshPet() {
        publishPet(updatePet())
    }

    /// A pet moment: bring the pet up to date, and re-render the island when its
    /// dock moved, so the black dock and the pet move together.
    func petTick() {
        let update = updatePet()
        let dockMoved = petVisible && currentIslandState() == .idle && islandModel.contentSize.petDock != petIdleDock
        // The pet coming home from a game is also when NEO's listening glow
        // may come up behind it.
        if dockMoved || listeningNeedsRender {
            renderIsland()
        } else {
            publishPet(update)
        }
        clearStalePetHover()
    }

    /// The pet moved out from under a still cursor: a hover it no longer has.
    /// Only ever clears — a hover starts with a real mouse event.
    func clearStalePetHover() {
        guard petHovered || petCursorSide != nil else { return }
        // The big pet's hover belongs to `panelPetMouseMoved`, and it never moves
        // out from under the cursor.
        guard panel != .pet else { return }
        let mouse = NSEvent.mouseLocation
        let point = NSPoint(x: mouse.x - window.frame.minX, y: mouse.y - window.frame.minY)
        guard !(petRect(live: true)?.insetBy(dx: -3, dy: -3).contains(point) ?? false) else { return }
        petHovered = false
        petCursorSide = nil
        petTick()
    }

    /// One pending wakeup at the brain's next moment — never a polling timer.
    func schedulePetWakeup(context: PetContext, now: Date) {
        guard let next = petBrain.nextWakeup(context: context, now: now) else {
            petWakeTask?.cancel()
            petWakeTask = nil
            petWakeAt = nil
            return
        }
        if let scheduled = petWakeAt, petWakeTask != nil, abs(scheduled.timeIntervalSince(next)) < 0.02 {
            return
        }
        petWakeTask?.cancel()
        petWakeAt = next
        petWakeTask = Task { @MainActor [weak self] in
            let delay = max(0, next.timeIntervalSinceNow)
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.petWakeTask = nil
            self.petWakeAt = nil
            self.petTick()
        }
    }

    // MARK: - Events

    /// Apps whose notifications deserve a glance from the pet.
    static let importantNotificationApps = ["Messages", "FaceTime", "Calendar", "Reminders", "Phone"]

    /// Turns a system event into a pet moment. Runs before `record`, so
    /// "previous" values are still the old ones.
    func petObserve(_ event: SystemEvent) {
        guard petVisible, petSettings.reactions else { return }
        // Listeners report their starting state as they start; that is not news.
        if let started = monitorStartedAt, Date().timeIntervalSince(started) < Self.monitorSettlePeriod {
            return
        }
        let petEvent: PetEvent?
        switch event.payload {
        case let .nowPlaying(title, _, isPlaying, _, _):
            petEvent = (isPlaying && musicTitle != nil && musicTitle != title) ? .songChanged : nil
        case .timerFinished:
            // The stopwatch giving way to a focus session is not a finish.
            petEvent = timerService.isCountingDown ? nil : .timerFinished
        case let .focusFinished(completed):
            petEvent = completed ? .focusFinished : nil
        case .downloadFinished:
            petEvent = .downloadFinished
        case let .codingAgent(running, _):
            petEvent = running ? nil : .agentFinished
        case let .battery(percent, charging, chargingChanged):
            if chargingChanged, charging {
                petEvent = .chargingStarted
            } else if charging, percent >= 100, let previous = batteryPercent, previous < 100 {
                petEvent = .fullyCharged
            } else {
                petEvent = nil
            }
        case .lowBattery:
            petEvent = .lowBattery
        case let .bluetoothDevice(connected, name):
            let audio = ["airpods", "beats", "headphone", "buds"].contains { name.lowercased().contains($0) }
            petEvent = audio ? (connected ? .headphonesConnected : .headphonesDisconnected) : nil
        case let .notification(app, _, _):
            petEvent = .notification(important: Self.importantNotificationApps.contains { app.localizedCaseInsensitiveContains($0) })
        case let .privacy(camera, microphone):
            if camera, !isCameraActive, meeting == nil {
                petEvent = .cameraOn
            } else if microphone, !isMicActive, meeting == nil {
                petEvent = .microphoneOn
            } else {
                petEvent = nil
            }
        case let .screenRecording(active):
            petEvent = active ? .recordingStarted : nil
        case .calendarStarting:
            petEvent = .notification(important: true)
        default:
            petEvent = nil
        }
        if let petEvent {
            petBrain.handle(petEvent, context: petContext(), now: Date())
        }
    }

    // MARK: - Pointer

    /// The pet's rectangle in window coordinates. On the idle dock only the part
    /// that shows beside the notch counts: by pose (none while it hides inside
    /// the notch, half a pet while it peeks out) — the stable rect clicks use —
    /// or, `live`, exactly where the moving sprite is drawn this instant, which
    /// is what the cursor can point at.
    func petRect(live: Bool = false) -> CGRect? {
        guard petVisible else { return nil }
        let state = currentIslandState()
        guard state != .idle || window.hasNotch else { return nil }
        let content = islandModel.contentSize
        let dock = content.petDock ?? .home
        let frame = window.localFrame(for: state, content: content)
        guard let placement = PetLayout.placement(for: state, islandSize: frame.size, notchHeight: window.notchHeight, dock: dock) else {
            return nil
        }
        var rect = CGRect(
            x: frame.minX + placement.origin.x,
            y: frame.maxY - placement.origin.y - placement.size,
            width: placement.size,
            height: placement.size
        )
        if state == .idle {
            guard dock.reach > 0 else { return nil }
            if live {
                let presentation = petBrain.presentation
                let offset = presentation.animation.animation.offset(at: Date().timeIntervalSince(presentation.startedAt))
                rect.origin.x += CGFloat(presentation.mirrored ? -offset.dx : offset.dx)
                rect.origin.y -= CGFloat(offset.dy)
                let notch = window.localFrame(for: .idle, content: .default)
                // The dock as drawn: while the word "Listening" stands between
                // the notch and the pet, the pet sits that much further out.
                let reach = dock.reach + content.listeningSlot
                let beside = dock.side == .right
                    ? CGRect(x: notch.maxX, y: frame.minY, width: reach, height: frame.height)
                    : CGRect(x: notch.minX - reach, y: frame.minY, width: reach, height: frame.height)
                let showing = rect.intersection(beside)
                return showing.width >= 4 ? showing : nil
            }
            switch petBrain.presentation.animation.mischiefPose {
            case .hidden:
                return nil
            case .peeking:
                let half = placement.size / 2
                let offset = CGFloat(PetLayout.peekOffset)
                rect.origin.x += dock.side == .right ? offset + half : -offset
                rect.size.width = half
            case .home:
                break
            }
        }
        return rect
    }

    /// Notices the cursor on the pet (and which way it is) — only acting on a
    /// change, so ordinary mouse movement costs a rectangle test.
    func petMouseMoved(_ point: NSPoint) {
        guard petVisible else { return }
        if panel == .pet {
            panelPetMouseMoved(point)
            return
        }
        let restingPet = petDocked && currentIslandState() == .idle
        guard machine.isHovering || petHovered || petCursorSide != nil || restingPet else { return }
        let rect = petRect(live: true)
        let over = rect?.insetBy(dx: -3, dy: -3).contains(point) ?? false
        var side: PetContext.Side?
        if machine.isHovering, let rect {
            if point.x < rect.minX - 12 { side = .left } else if point.x > rect.maxX + 12 { side = .right }
        }
        guard over != petHovered || side != petCursorSide else { return }
        let entered = over && !petHovered
        petHovered = over
        petCursorSide = side
        if entered, petSettings.reactions {
            petBrain.handle(.petHovered, context: petContext(), now: Date())
        }
        petTick()
    }

    /// The big pet in its panel: it leans toward the cursor pointing at it, and
    /// purrs while the cursor strokes it back and forth.
    func panelPetMouseMoved(_ point: NSPoint) {
        let frame = window.localFrame(for: .skin, content: islandModel.contentSize)
        let rect = PetPanelLayout.layout(in: frame, notchInset: window.notchHeight).pet
        let over = rect.insetBy(dx: -3, dy: -3).contains(point)
        let side: PetContext.Side? = over ? (point.x < rect.midX ? .left : .right) : nil
        let now = Date()
        var stroked = false
        if over {
            stroked = petStroke.move(to: point.x, at: now)
        } else {
            petStroke.reset()
        }
        guard over != petHovered || side != petCursorSide || stroked else { return }
        petHovered = over
        petCursorSide = side
        if stroked, petSettings.interaction {
            petBrain.handle(.bigPetStroked, context: petContext(), now: now)
        }
        refreshPet()
    }

    // MARK: - Click interaction

    /// A click on the pet opens its panel; a click on a panel action performs
    /// it. Anything else falls through to the island.
    func petControlHit(at point: NSPoint) -> Bool {
        guard petVisible else { return false }
        if panel == .pet {
            let frame = window.localFrame(for: .skin, content: islandModel.contentSize)
            guard let hit = PetPanelLayout.hit(at: point, in: frame, notchInset: window.notchHeight) else {
                return false
            }
            switch hit {
            case let .action(action):
                performPetInteraction(action)
            case let .look(look):
                var settings = petSettings
                settings.look = look
                applyPetSettings(settings)
            case .hat:
                var settings = petSettings
                settings.hat = settings.hat.next
                applyPetSettings(settings)
            case .pet:
                petBrain.handle(.bigPetClicked, context: petContext(), now: Date())
                refreshPet()
            }
            return true
        }
        guard panel == .none, let rect = petRect(), rect.insetBy(dx: -3, dy: -3).contains(point) else { return false }
        // While idle the pet's rect takes clicks without opening the island;
        // with Interaction off such a click does nothing.
        guard petSettings.interaction else { return currentIslandState() == .idle }
        openPetPanel()
        return true
    }

    func openPetPanel() {
        // The panel is centred on the notch, like every other panel, so it
        // grows symmetrically out of whatever shape the island was in rather
        // than lurching toward the pet's side. The machine is left alone: the
        // panel outranks it, and on close the island returns to exactly the
        // shape it had.
        let state = currentIslandState()
        releaseCurrentPanel(except: .pet)
        panel = .pet
        petBrain.handle(.petClicked, context: petContext(), now: Date())
        renderIsland()
        if state == .idle {
            // The cursor is already on the panel: leaving it must close it.
            window.adoptHover()
        }
        log("pet: panel opened")
    }

    func closePetPanel() {
        guard panel == .pet else { return }
        panel = .none
        petStroke.reset()
        renderIsland()
    }

    /// A focus session's length.
    static let focusDuration: TimeInterval = 25 * 60

    func performPetInteraction(_ action: PetInteraction) {
        log("pet: \(action.rawValue)")
        switch action {
        case .sleep:
            petSleepHoverSession = true
        case .focus:
            if timerService.isCountingDown {
                timerService.stopCountdown()
            } else if featureSettings.isEnabled(.timers) {
                timerService.startCountdown(Self.focusDuration)
            } else {
                // Timers are off: the chip is dimmed, and a tap does nothing.
                log("pet: focus needs Timers")
                return
            }
        default:
            break
        }
        let context = petContext()
        petBrain.handle(.interaction(action), context: context, now: Date())
        switch action {
        case .sleep, .focus:
            closePetPanel()
        case .trick where context.isDocked:
            // The game plays on the dock once the island is back at rest.
            closePetPanel()
        default:
            refreshPet()
        }
    }

    // MARK: - Settings

    func applyPetSettings(_ settings: PetSettings) {
        guard settings != petSettings else { return }
        let holidaysTurnedOn = settings.holidays && !petSettings.holidays
        petSettings = settings
        // Keep the Settings panel's snapshot current, so saving any setting there
        // never writes back an older look or hat chosen in the pet's panel.
        settingsModel.petSettings = settings
        settings.save()
        holidayCache = nil
        if holidaysTurnedOn {
            scheduleHolidayGreeting()
        }
        if !settings.showPet {
            petHovered = false
            petCursorSide = nil
            if panel == .pet { panel = .none }
        }
        renderIsland()
        // Hiding the pet while idle: the dock retracts into the notch and fades.
        if !settings.showPet, currentIslandState() == .idle {
            scheduleSurfaceFade()
        }
    }
}
