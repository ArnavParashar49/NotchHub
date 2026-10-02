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
/// doing. One thing is added, and only while NEO is LISTENING: a soft glow
/// breathes behind the pet (`NeoListeningIndicator`). For the first 1.5 s
/// the word "Listening" stands beside the pet and the pet's side of the
/// island makes room for it; after that the island is exactly as wide as it
/// is without NEO. The models are pure
/// and clock-driven: they say when something will change on its own (a held
/// state becoming due, the settle after idle, the panel folding, the word
/// stepping aside), and `scheduleNeoWake` comes back exactly then. NEO's state lives here and in
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
        neoPresence.receive(fact, at: now)
        switch fact {
        case let .card(kind, open): neoPanel.card(kind, open: open, at: now)
        case .woke: neoPanel.show(at: now) // summoned by hand: the explicit show
        case .connected(false):
            neoPanel.disconnected(at: now)
            log("neo: core away — panel open=\(neoPanel.isOpen) waiting=\(neoPanel.isWaitingForCore)")
        case .connected(true):
            log("neo: core back — panel open=\(neoPanel.isOpen) waiting=\(neoPanel.isWaitingForCore)")
            neoPanel.reconnected(at: now)
        default: break
        }
        // The panel takes NEO's state from the presence's hold: one truth.
        neoPanel.receive(state: neoPresence.state, at: now)
        updateNeoListening(at: now)
        applyNeoPanel()
        if wasPresent != neoPresent {
            // NEO arriving puts the pet on screen (its dock is a change of
            // shape); leaving hands the island back as it was.
            renderIsland()
        } else {
            refreshNeoPet()
        }
        scheduleNeoWake(neoNextWake(at: now))
    }

    // MARK: - The listening mark

    /// Feeds the listening mark NEO's held state: it shows only while NEO is
    /// here and listening.
    func updateNeoListening(at now: Date) {
        neoListening.update(listening: neoPresent && neoPresence.state == .listening, at: now)
    }

    /// The word's width in the compact font.
    static var listeningLabelWidth: CGFloat { IslandMetrics.listeningLabelWidth }

    /// The listening mark for a shape right now, or `nil` where none shows:
    /// NEO not listening (or away), a surface the pet steps aside for, or the
    /// idle dock while the pet is not standing at its spot (hiding in the
    /// notch, peeking, mid-game — it comes home first, as for any NEO pose).
    func neoListeningMark(for state: IslandState, at now: Date = Date()) -> NeoListeningMark? {
        guard neoPresent else { return nil }
        let atHome = petDocked
            && petBrain.dock.reach >= PetLayout.idleDock
            && petBrain.presentation.mood != .mischief
        return neoListening.mark(for: state, at: now, labelWidth: Self.listeningLabelWidth, petAtHome: atHome)
    }

    /// Whether the mark the island drew is no longer the one it should show
    /// (listening began or ended, the word's moment passed, the pet came home).
    var listeningNeedsRender: Bool {
        neoListeningMark(for: currentIslandState()) != islandModel.listening
    }

    /// Re-poses the pet for NEO — and re-renders the island when the
    /// listening mark changed, so the word and the room it takes move on the
    /// island's own spring, in one transaction.
    func refreshNeoPet() {
        let update = updatePet()
        if listeningNeedsRender {
            renderIsland()
        } else {
            publishPet(update)
        }
    }

    /// Advances the clocks and re-poses the pet if what NEO shows changed.
    func neoTick() {
        let now = Date()
        let changed = neoPresence.tick(at: now)
        neoPanel.receive(state: neoPresence.state, at: now)
        _ = neoPanel.tick(at: now)
        updateNeoListening(at: now)
        applyNeoPanel()
        if changed || listeningNeedsRender {
            refreshNeoPet()
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

    /// The left wing's width as the hit layouts need it.
    var wingHitLead: CGFloat? {
        islandModel.contentSize.wingLead
    }

    // MARK: - Demo

    /// `--neo-demo`: a scripted NEO turn, fed straight into NEO's presence
    /// without a core — connect, wake (connecting), listen, think, search,
    /// speak, ask for an OK, go idle — repeating, so the pet can be watched
    /// posing as NEO through a turn and settling back into its own life. The
    /// island's shape changes only for the word "Listening" (2.6–4.1 s; the
    /// glow behind the pet stays until 5.6 s and takes no room); the panel stays closed
    /// through the answer and opens at "Needs your OK", folding 5 s after idle.
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
        steps.append((15.0, .state(.confirming)))
        steps.append((17.5, .state(.idle)))
        let period: TimeInterval = 24

        func run(round: Int) {
            for (delay, fact) in steps {
                after(delay) { app in app.neoReceive(fact) }
            }
            after(period) { $0.runNeoDemoRound(round + 1) }
        }
        neoDemoRound = run
        run(round: 0)
        log("neo-demo: one turn every \(Int(period)) s — the pet poses as NEO; the panel opens only at the OK")
    }

    func runNeoDemoRound(_ round: Int) {
        neoDemoRound?(round)
    }
}
