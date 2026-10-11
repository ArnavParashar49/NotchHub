import AppKit
import NotchHubCore
import NotchHubSystem

/// NEO in the notch: the pet is NEO.
///
/// NEO's core speaks through `NeoListener` (a system listener like any
/// other); its facts reach `record`, which feeds `NeoPresenceModel` — NEO's
/// held state and whether its core is there — and, from that state and the
/// card facts, `NeoPanelModel` (`+NeoPanel`). The pet takes NEO's state
/// through `petContext` (`PetContext.neoState`) and poses as what NEO is
/// doing. While NEO listens, a small animated voiceprint appears inside the
/// physical notch. It needs no extra island space and does not trace the edge.
/// The models are pure and clock-driven: they say when something will change
/// on its own (a held state becoming due, the settle after idle, the panel
/// folding), and
/// `scheduleNeoWake` comes back exactly then. NEO's state lives here and in
/// the models only — never in the activity queue or the state machine.
extension NotchHubApp {

    /// Whether NEO is here: its feature on and its core connected. Then the
    /// pet is on screen whatever the Show Pet setting says — it is NEO.
    var neoPresent: Bool {
        featureSettings.isEnabled(.neo) && neoPresence.isConnected
    }

    /// Whether NEO is busy, or just finished: a click on the island opens
    /// its chat.
    func neoActive(at now: Date) -> Bool {
        featureSettings.isEnabled(.neo) && neoPresence.isActive(at: now)
    }

    /// A fact from the core: update NEO's presence and the panel, re-pose the
    /// pet, and plan their next change.
    func neoReceive(_ fact: NeoFact) {
        let now = Date()
        let wasPresent = neoPresent
        let wasConfirming = neoConfirmShowing
        _ = neoConfirm.chat(open: panel == .neo, at: now)
        if neoConfirm.foldsChat(for: fact, at: now) {
            // The page got the chat opened for this very card a moment ago
            // (its socket was quicker than ours): the buttons are its UI.
            neoPanel.close(at: now)
            log("neo: the chat the page opened for a confirmation folds — the buttons show instead")
        }
        neoPresence.receive(fact, at: now)
        // A confirmation staged, answered elsewhere or lapsed — or the core
        // gone, with whatever it was waiting on.
        let confirmChanged = neoConfirm.receive(fact, at: now)
        switch fact {
        case let .card(kind, open):
            switch kind {
            case .browser:
                neoPanel.card(kind, open: open, at: now)
            case .camera:
                if open { openNeoCamera() } else { closeNeoCamera() }
            case .song:
                if open { updateNeoSongActivity(at: now) } else { finishNeoSongActivity(at: now) }
            }
        case let .cameraCard(state):
            let previous = neoCameraState
            neoCameraState = state
            if panel != .neoCamera { openNeoCamera() }
            neoCameraStream.boxes = state.boxes
            if panel == .neoCamera,
               previous?.status != state.status || previous?.answer != state.answer || previous?.labels != state.labels {
                refreshPanel()
            }
        case let .cameraFrame(frame):
            guard panel == .neoCamera else { return }
            neoCameraStream.frame = frame
            return // a preview pixel doesn't change NEO's state, the panel, or the pet
        case let .songCard(state):
            if let previousSID = neoSongSID, previousSID != state.sid {
                neoSongDismissTask?.cancel()
                if let id = neoSongActivityID { queue.remove(id: id) }
                neoSongActivityID = nil
                machine.clearExpandedHold()
            }
            neoSongCardState = state
            neoSongSID = state.sid
            updateNeoSongActivity(at: now)
        case .woke:
            neoConfirm.userOpenedChat()
            neoPanel.show(at: now) // summoned by hand: the explicit show
        case .connected(false):
            neoPanel.disconnected(at: now)
            if panel == .neoCamera { closePanel() }
            finishNeoSongActivity(at: now)
            log("neo: core away — panel open=\(neoPanel.isOpen) waiting=\(neoPanel.isWaitingForCore)")
        case .connected(true):
            log("neo: core back — panel open=\(neoPanel.isOpen) waiting=\(neoPanel.isWaitingForCore)")
            neoPanel.reconnected(at: now)
        default: break
        }
        // The panel takes NEO's state from the presence's hold: one truth.
        neoPanel.receive(state: neoPresence.state, at: now)
        applyNeoPanel()
        if confirmChanged || wasConfirming != neoConfirmShowing {
            // The buttons pop out, change card, or the island springs back.
            neoConfirmChanged(wasShowing: wasConfirming)
        } else if wasPresent != neoPresent {
            // NEO arriving puts the pet on screen (its dock is a change of
            // shape); leaving hands the island back as it was.
            renderIsland()
        } else {
            refreshNeoPet()
        }
        scheduleNeoWake(neoNextWake(at: now))
    }

    /// Camera and song cards have native NotchHub surfaces; only browser cards
    /// need NEO's embedded page. Camera pixels stay in memory while visible.
    func openNeoCamera() {
        guard panel != .neoCamera else {
            monitor?.neoCameraVisible(true)
            return
        }
        neoCameraStream.frame = nil
        neoCameraStream.boxes = []
        takePanel(.neoCamera)
        monitor?.neoCameraVisible(true)
        renderIsland()
    }

    func closeNeoCamera() {
        guard panel == .neoCamera else {
            neoCameraStream.frame = nil
            neoCameraStream.boxes = []
            neoCameraState = nil
            return
        }
        closePanel() // releaseCurrentPanel stops the session and hides its stream
    }

    func updateNeoSongActivity(at now: Date) {
        let state = neoSongCardState
        let title: String
        let subtitle: String
        let symbol: String
        let artwork: Data?
        let isListening = state?.status == "listening" || state?.status == "matching"
        let hasTrack = state?.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let previousKind = neoSongActivityID.flatMap { id in queue.all.first(where: { $0.id == id })?.kind }
        if let state, let track = state.title, !track.isEmpty {
            title = track
            subtitle = [state.artist, state.album, state.year].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            symbol = "music.note"
            artwork = state.cover
        } else {
            title = state?.status == "not_found" ? "No song found"
                : state?.status == "error" ? "Couldn't identify song"
                : "Listening for a song"
            let elapsed = Int(state?.elapsed ?? 0)
            let clock = String(format: "%d:%02d", elapsed / 60, elapsed % 60)
            subtitle = state?.message ?? (state?.status == "listening" || state?.status == "matching"
                ? "Listening · \(clock)" : "Try asking again")
            symbol = state?.status == "listening" || state?.status == "matching" ? "waveform" : "music.note"
            artwork = nil
        }
        let activity = Activity(
            id: neoSongActivityID ?? UUID(),
            kind: isListening ? .songRecognition : (state?.status == "found" && hasTrack ? .identifiedSong : .custom),
            title: title,
            subtitle: subtitle.isEmpty ? nil : subtitle, symbol: symbol,
            priority: 90, autoDismiss: 0, progress: state?.level,
            elapsed: state?.elapsed, artwork: artwork, createdAt: now
        )
        if let id = neoSongActivityID {
            queue.replace(id, with: activity)
        } else {
            neoSongActivityID = activity.id
            queue.push(activity)
        }
        renderQueue()
        // A found track earns a short details popup automatically. Its small
        // expanded layout is also available on hover after the popup settles.
        if activity.kind == .identifiedSong, panel == .none, !neoConfirmShowing {
            if previousKind != .identifiedSong, machine.presentation != .interactive {
                machine.holdExpanded(until: now.addingTimeInterval(4.25))
            }
            if machine.presentation == .compact {
                machine.send(.priorityChanged)
                renderIsland()
            }
        } else if previousKind == .identifiedSong {
            machine.clearExpandedHold()
        }
    }

    func finishNeoSongActivity(at now: Date) {
        guard let id = neoSongActivityID else { return }
        if let state = neoSongCardState,
           state.status == "found" || state.status == "not_found" || state.status == "error" {
            let current = queue.all.first(where: { $0.id == id })
            let final = Activity(
                id: id, kind: state.status == "found" && current?.title != nil ? .identifiedSong : .custom,
                title: current?.title ?? "Song identified",
                subtitle: current?.subtitle, symbol: current?.symbol, priority: current?.priority,
                autoDismiss: 4, artwork: current?.artwork, createdAt: now
            )
            queue.replace(id, with: final)
            neoSongDismissTask?.cancel()
            neoSongDismissTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard !Task.isCancelled, let self, self.neoSongActivityID == id else { return }
                self.queue.remove(id: id)
                self.neoSongActivityID = nil
                self.neoSongSID = nil
                self.neoSongCardState = nil
                self.machine.clearExpandedHold()
                self.renderQueue()
            }
        } else {
            neoSongDismissTask?.cancel()
            queue.remove(id: id)
            neoSongActivityID = nil
            neoSongSID = nil
            neoSongCardState = nil
            machine.clearExpandedHold()
        }
        renderQueue()
    }

    // MARK: - Legacy listening pulse (snapshot compatibility)

    /// Whether the pet stands at its spot on the idle dock — not hiding in
    /// the notch, peeking, or mid-game (it comes home first, as for any NEO
    /// pose).
    var petAtHome: Bool {
        petDocked
            && petBrain.dock.reach >= PetLayout.idleDock
            && petBrain.presentation.mood != .mischief
    }

    /// The legacy snapshot mark for a shape right now. The live view uses
    /// `neoListeningActive` and draws the moving notch outline instead.
    func neoListeningMark(for state: IslandState, at now: Date = Date()) -> NeoListeningMark? {
        guard neoPresent else { return nil }
        return neoListening.mark(for: state, at: now, petAtHome: petAtHome)
    }

    /// Feeds the legacy snapshot indicator NEO's held state and returns its
    /// mark. The live outline follows the core's listening state directly.
    func updatedNeoListeningMark(for state: IslandState, at now: Date = Date()) -> NeoListeningMark? {
        let begun = neoListening.pulseStart
        neoListening.update(
            listening: neoPresent && neoPresence.state == .listening,
            at: now,
            petInPlace: state != .idle || petAtHome
        )
        if neoListening.pulseStart != nil, neoListening.pulseStart != begun {
            scheduleNeoWake(neoNextWake(at: now))
        }
        return neoListeningMark(for: state, at: now)
    }

    /// Keeps the legacy snapshot mark current and publishes the live listening
    /// state that drives the moving blue notch outline.
    func publishNeoListening(at now: Date = Date()) {
        let mark = updatedNeoListeningMark(for: currentIslandState(), at: now)
        if islandModel.listening != mark {
            islandModel.listening = mark
        }
        islandModel.neoListeningActive = neoPresent && neoPresence.state == .listening
    }

    /// Re-poses the pet for NEO and refreshes its listening state.
    func refreshNeoPet() {
        publishPet(updatePet())
        publishNeoListening()
    }

    /// Advances the clocks and re-poses the pet if what NEO shows changed.
    func neoTick() {
        let now = Date()
        let changed = neoPresence.tick(at: now)
        neoPanel.receive(state: neoPresence.state, at: now)
        _ = neoPanel.tick(at: now)
        applyNeoPanel()
        if changed {
            refreshNeoPet()
        } else {
            // The pulse ending is a wake-up of its own.
            publishNeoListening(at: now)
        }
        scheduleNeoWake(neoNextWake(at: now))
    }

    /// Comes back at `date` (at most one wake-up is ever pending).
    func scheduleNeoWake(_ date: Date?) {
        neoWakeTask?.cancel()
        neoWakeTask = nil
        guard let date else { return }
        let delay = max(0, date.timeIntervalSinceNow)
        neoWakeTask = Task { @MainActor [weak self] in
            // A hair past the due time, so the model sees it as reached.
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000) + 2_000_000)
            guard !Task.isCancelled, let self else { return }
            self.neoTick()
        }
    }

    /// Where the notch sits inside the hover wings, as the hit layouts need
    /// it (`IslandContentSize.wingHitLead`): the centred strip's wider side.
    var wingHitLead: CGFloat? {
        islandModel.contentSize.wingHitLead
    }

    // MARK: - Demo

    /// `--neo-demo`: a scripted NEO turn, fed straight into NEO's presence
    /// without a core — connect, wake (connecting), listen, think, search,
    /// speak, ask for an OK, go idle — repeating, so the pet can be watched
    /// posing as NEO through a turn and settling back into its own life. The
    /// island's shape never changes for it; the glow pulses once behind the
    /// pet as listening starts (2.6–4.0 s; NEO listens until 5.6 s). The chat
    /// panel stays closed throughout; at "Needs your OK" (15 s) Allow and
    /// Cancel pop out under the notch and stay 6 s, unless one is clicked.
    func runNeoDemo() {
        let heard = "what's the weather like in Paris this weekend"
        let said = "Paris looks mild this weekend: sunny on Saturday, around 19 degrees, with a few clouds on Sunday."
        var steps: [(TimeInterval, NeoFact)] = [
            (0.0, .connected(true)),
            (0.0, .state(.idle)),
            (1.0, .state(.connecting)),
            (2.6, .state(.listening)),
            (2.8, .transcript(role: .user, text: heard, final: true)),
            (5.6, .state(.thinking)),
            (7.6, .state(.working)),
            (9.6, .state(.searching)),
            (11.6, .state(.speaking)),
            (11.8, .transcript(role: .assistant, text: said, final: true)),
        ]
        let card = NeoConfirmCard(actionID: "demo:ok", tool: "trash", summary: "move report.pdf to the Trash", detail: "~/Documents/report.pdf")
        steps.append((15.0, .state(.confirming)))
        steps.append((15.0, .confirm(card)))
        steps.append((21.0, .confirmDone(card.actionID)))
        steps.append((21.0, .state(.idle)))
        let period: TimeInterval = 24

        func run(round: Int) {
            for (delay, fact) in steps {
                after(delay) { app in app.neoReceive(fact) }
            }
            after(period) { $0.runNeoDemoRound(round + 1) }
        }
        neoDemoRound = run
        run(round: 0)
        log("neo-demo: one turn every \(Int(period)) s — the pet poses as NEO; at the OK, Allow and Cancel pop out under the notch")
    }

    func runNeoDemoRound(_ round: Int) {
        neoDemoRound?(round)
    }
}
