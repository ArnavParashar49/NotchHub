import AppKit
import NotchHubCore
import NotchHubSystem

/// NEO in the notch.
///
/// NEO's core speaks through `NeoListener` (a system listener like any
/// other); its facts reach `record`, which feeds `NeoLaneModel`. The model
/// is pure and clock-driven: it says when something will change on its own
/// (a held state becoming due, a note expiring, the lane tucking in), and
/// `scheduleNeoWake` comes back exactly then. NEO's state lives here and in
/// the model only — never in the activity queue or the state machine — so
/// the lane can show in every island shape without competing with anything.
extension NotchHubApp {

    /// A fact from the core: update the lane and plan its next change.
    func neoReceive(_ fact: NeoFact) {
        let now = Date()
        let wake = neoLane.receive(fact, at: now)
        scheduleNeoWake(wake)
    }

    /// Advances the lane's clock and re-renders if what it shows changed.
    func neoTick() {
        let now = Date()
        if neoLane.tick(at: now) {
            renderIsland()
        }
        scheduleNeoWake(neoLane.nextWake(at: now))
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

    /// What the lane shows right now, or `nil` while it is tucked in (or NEO
    /// is switched off in settings).
    func neoContent(at now: Date) -> NeoLaneContent? {
        guard featureSettings.isEnabled(.neo) else { return nil }
        return neoLane.content(at: now)
    }

    /// How far the lane reaches left of the notch for `content`: measured
    /// from the line it will draw, like every other bar.
    func neoLead(for content: NeoLaneContent?) -> CGFloat {
        guard let content else { return 0 }
        return NeoLaneLayout.width(notchHeight: window.notchHeight, textWidth: IslandMetrics.textWidth(content.line))
    }

    /// The left wing's width as the hit layouts need it: the measured wing
    /// plus NEO's lane, which sits between the wing and the notch.
    var wingHitLead: CGFloat {
        let content = islandModel.contentSize
        return (content.wingLead ?? content.wingSide) + content.neoLead
    }

    // MARK: - Demo

    /// `--neo-demo`: a scripted NEO turn, fed straight into the lane without
    /// a core — connect, listen (with what it hears), think, search, speak
    /// (with what it says), go idle — repeating, so the lane can be watched
    /// coming out of the notch and tucking back in.
    func runNeoDemo() {
        let heard = "what's the weather like in Paris this weekend"
        let said = "Paris looks mild this weekend: sunny on Saturday, around 19 degrees, with a few clouds on Sunday."
        func words(_ text: String) -> [String] {
            var out: [String] = []
            for word in text.split(separator: " ") {
                out.append((out.last.map { $0 + " " } ?? "") + word)
            }
            return out
        }
        var steps: [(TimeInterval, NeoFact)] = [
            (0.0, .connected(true)),
            (0.0, .state(.idle)),
            (1.0, .state(.connecting)),
            (2.2, .state(.listening)),
        ]
        var t = 2.6
        for line in words(heard) {
            steps.append((t, .transcript(role: .user, text: line, final: false)))
            t += 0.22
        }
        steps.append((t, .transcript(role: .user, text: heard, final: true)))
        steps.append((t + 0.3, .state(.thinking)))
        steps.append((t + 1.8, .state(.searching)))
        steps.append((t + 3.6, .state(.speaking)))
        var s = t + 3.8
        for line in words(said) {
            steps.append((s, .transcript(role: .assistant, text: line, final: false)))
            s += 0.16
        }
        steps.append((s, .transcript(role: .assistant, text: said, final: true)))
        steps.append((s + 0.8, .state(.confirming)))
        steps.append((s + 2.4, .state(.idle)))
        let period = s + 6.0

        func run(round: Int) {
            for (delay, fact) in steps {
                after(delay) { app in
                    app.neoReceive(fact)
                    app.renderIsland()
                }
            }
            after(period) { $0.runNeoDemoRound(round + 1) }
        }
        neoDemoRound = run
        run(round: 0)
        log("neo-demo: one turn every \(Int(period)) s")
    }

    func runNeoDemoRound(_ round: Int) {
        neoDemoRound?(round)
    }
}
