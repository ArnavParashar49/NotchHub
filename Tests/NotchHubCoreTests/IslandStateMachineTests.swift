import Foundation
import Testing
@testable import NotchHubCore

@Suite("IslandStateMachine")
struct IslandStateMachineTests {

    @Test("idle → compact on activityStarted")
    func idleToCompact() {
        let m = IslandStateMachine()
        #expect(m.presentation == .idle)
        #expect(m.send(.activityStarted) == .compact)
        #expect(m.presentation == .compact)
    }

    @Test("compact → expanded on hoverEntered")
    func compactToExpandedOnHover() {
        let m = IslandStateMachine()
        m.setActivity(.music(title: "Midnight City", artist: "M83"))
        m.send(.activityStarted) // idle → compact
        #expect(m.send(.hoverEntered) == .expanded)
    }

    @Test("compact-only readout does NOT expand on hover")
    func compactOnlyDoesNotExpandOnHover() {
        let m = IslandStateMachine()
        m.setActivity(.volume(0.62)) // complete in the bar — nothing to reveal
        m.send(.activityStarted) // idle → compact
        #expect(m.send(.hoverEntered) == .compact)
        #expect(m.presentation == .compact)
    }

    @Test("a click on a compact-only readout opens the dashboard, not a bigger pill")
    func compactOnlyClickOpensDashboard() {
        let m = IslandStateMachine()
        m.setActivity(.brightness(0.75))
        m.send(.activityStarted)
        #expect(m.send(.clicked) == .interactive)
    }

    @Test("every transient readout kind stays compact on hover")
    func allTransientKindsStayCompact() {
        let kinds: [ActivityKind] = [
            .volume, .brightness, .battery, .lowBattery, .wifi, .bluetooth,
            .airpods, .recording, .microphone, .camera, .calendar, .focus,
            .dnd, .clipboard, .notification, .timer, .download,
        ]
        for kind in kinds {
            let m = IslandStateMachine()
            m.setActivity(Activity(kind: kind, title: kind.rawValue))
            m.send(.activityStarted)
            #expect(m.send(.hoverEntered) == .compact, "\(kind) should not expand")
        }
    }

    @Test("timer and download stay compact on hover")
    func timerAndDownloadStayCompact() {
        for activity in [
            Activity.timer(elapsed: 12),
            Activity.download(name: "Report.pdf", progress: 0.4),
        ] {
            let m = IslandStateMachine()
            m.setActivity(activity)
            m.send(.activityStarted)
            #expect(m.send(.hoverEntered) == .compact, "\(activity.kind) should not expand")
            #expect(m.send(.clicked) == .interactive, "\(activity.kind) click opens the dashboard")
        }
    }

    @Test("only music and a meeting may expand")
    func onlyInteractiveKindsExpand() {
        #expect(Activity.music(title: "A", artist: "B").canExpand)
        #expect(!Activity.timer(elapsed: 1).canExpand)
        #expect(!Activity.download(name: "f", progress: 0.2).canExpand)
        #expect(!Activity.volume(0.5).canExpand)
        #expect(!Activity.brightness(0.5).canExpand)
        #expect(!Activity.battery(percent: 50, charging: false).canExpand)
    }

    @Test("a readout's compact text is the value, not the redundant word")
    func readoutCompactTextIsTheValue() {
        // The glyph names the kind; the percentage is the news. A word here
        // would clip on a narrow bar.
        #expect(Activity.volume(0.62).compactText == "62%")
        #expect(Activity.brightness(0.75).compactText == "75%")
        #expect(Activity.battery(percent: 100, charging: false).compactText == "100%")
        #expect(Activity.download(name: "f", progress: 0.35).compactText == "35%")
        // A song shows its (marquee-bounded) title beside the artwork, with the
        // visualizer on the other side — see `IslandMetrics.compact`.
        #expect(Activity.music(title: "Midnight City", artist: "M83").compactText == "Midnight City")
        #expect(Activity.music(title: "Midnight City", artist: "M83").compactDetail == nil)
    }

    @Test("idle → wings on hoverEntered (sideways peek)")
    func idlePeekOnHover() {
        let m = IslandStateMachine()
        #expect(m.presentation == .idle)
        #expect(m.send(.hoverEntered) == .wings)
        #expect(m.isHovering)
    }

    @Test("bare hover peek (wings) tucks back behind the notch after cursor leaves")
    func barePeekCollapsesAfterHoverExit() {
        let m = IslandStateMachine()
        m.send(.hoverEntered) // idle → wings peek, no activity
        #expect(m.presentation == .wings)
        m.send(.hoverExited)
        // Not immediately — the collapse delay must elapse first.
        #expect(m.presentation == .wings)
        let now = Date().addingTimeInterval(m.hoverCollapseDelay + 0.1)
        #expect(m.tick(now) == .idle)
    }

    @Test("a click on the wings opens the dashboard")
    func wingsClickOpensDashboard() {
        let m = IslandStateMachine()
        m.send(.hoverEntered) // idle → wings
        #expect(m.presentation == .wings)
        #expect(m.send(.clicked) == .interactive)
    }

    @Test("a click on the idle notch opens the dashboard")
    func idleClickOpensDashboard() {
        let m = IslandStateMachine()
        #expect(m.send(.clicked) == .interactive)
    }

    @Test("closing the dashboard rests on the wings while the cursor is on the notch")
    func dashboardClosesToWingsWhileHovering() {
        let m = IslandStateMachine()
        m.send(.hoverEntered)
        m.send(.clicked) // dashboard
        #expect(m.send(.clicked) == .wings)
    }

    @Test("the dashboard stays open when the activity behind it expires")
    func dashboardSurvivesExpiringActivity() {
        let m = IslandStateMachine()
        m.setActivity(Activity(kind: .volume, title: "Volume", autoDismiss: 1.6))
        m.send(.activityStarted)
        m.send(.hoverEntered)
        m.send(.clicked) // dashboard
        let later = Date().addingTimeInterval(5)
        #expect(m.tick(later) == .interactive)
        #expect(m.send(.activityEnded) == .interactive)
    }

    @Test("the dashboard closes once the cursor has left")
    func dashboardClosesAfterHoverExit() {
        let m = IslandStateMachine()
        m.send(.hoverEntered)
        m.send(.clicked) // dashboard
        m.send(.hoverExited)
        let later = Date().addingTimeInterval(m.hoverCollapseDelay + 0.1)
        #expect(m.tick(later) == .idle)
    }

    @Test("wings → compact when a real activity starts")
    func wingsToCompactOnActivity() {
        let m = IslandStateMachine()
        m.send(.hoverEntered) // idle → wings
        #expect(m.presentation == .wings)
        #expect(m.send(.activityStarted) == .compact)
    }

    @Test("wings never step down to compact — they go straight back to idle")
    func wingsNeverGrowDownward() {
        let m = IslandStateMachine()
        m.send(.hoverEntered) // idle → wings
        #expect(m.presentation == .wings)

        // While still hovering, the wings stay put even past the auto-collapse
        // delay — the cursor is on them.
        let whileHovering = Date().addingTimeInterval(m.autoCollapseDelay + 0.1)
        #expect(m.tick(whileHovering) == .wings)

        // Once the cursor leaves, auto-collapse returns to idle — never down
        // into the compact pill (which would grow the island downward).
        m.send(.hoverExited)
        let afterExit = Date().addingTimeInterval(m.hoverCollapseDelay + 0.1)
        #expect(m.tick(afterExit) == .idle)
    }

    @Test("expanded → interactive on clicked")
    func expandedToInteractive() {
        let m = IslandStateMachine()
        m.setActivity(.music(title: "Midnight City", artist: "M83"))
        m.send(.activityStarted)
        m.send(.hoverEntered) // compact → expanded
        #expect(m.send(.clicked) == .interactive)
    }

    @Test("a second click closes the dashboard to the compact bar")
    func secondClickClosesDashboard() {
        let m = IslandStateMachine()
        m.setActivity(.music(title: "Midnight City", artist: "M83"))
        m.send(.activityStarted)
        m.send(.hoverEntered)
        m.send(.clicked) // expanded → dashboard
        #expect(m.send(.clicked) == .compact)
    }

    @Test("hoverExited does not collapse immediately")
    func hoverExitDoesNotCollapseImmediately() {
        let m = IslandStateMachine()
        m.setActivity(.music(title: "Midnight City", artist: "M83"))
        m.send(.activityStarted)
        m.send(.hoverEntered) // expanded
        #expect(m.presentation == .expanded)

        // Right after exiting, the collapse is still gated.
        m.send(.hoverExited)
        #expect(m.presentation == .expanded)
        #expect(m.shouldCollapse(now: Date()) == false)
    }

    @Test("hoverExited collapses after hoverCollapseDelay")
    func hoverExitCollapsesAfterDelay() {
        let m = IslandStateMachine()
        m.setActivity(.music(title: "Midnight City", artist: "M83"))
        m.send(.activityStarted)
        m.send(.hoverEntered) // expanded
        m.send(.hoverExited)

        let later = Date().addingTimeInterval(m.hoverCollapseDelay + 0.1)
        #expect(m.shouldCollapse(now: later))
        #expect(m.tick(later) == .compact)
    }

    @Test("machine never gets stuck expanded — tick collapses after autoCollapseDelay")
    func neverStuckExpanded() {
        let m = IslandStateMachine()
        m.setActivity(.music(title: "Midnight City", artist: "M83"))
        m.send(.activityStarted) // idle → compact
        m.send(.clicked) // compact → expanded, cursor not over the island
        #expect(m.presentation == .expanded)

        // No interaction for longer than autoCollapseDelay → back to compact.
        let t1 = Date().addingTimeInterval(m.autoCollapseDelay + 0.1)
        #expect(m.tick(t1) == .compact)
    }

    @Test("an expired activity collapses expanded straight to idle — no staircase")
    func expiredCollapsesToIdleInOneMotion() {
        let m = IslandStateMachine()
        m.setActivity(Activity(kind: .music, title: "Midnight City", autoDismiss: 1.6))
        m.send(.activityStarted)
        m.send(.clicked) // expanded, cursor not over the island
        #expect(m.presentation == .expanded)

        let t1 = Date().addingTimeInterval(m.autoCollapseDelay + 0.1)
        #expect(m.tick(t1) == .idle)
    }

    @Test("interactive collapses to compact in one motion, not via expanded")
    func interactiveCollapsesInOneMotion() {
        let m = IslandStateMachine()
        m.setActivity(.music(title: "Midnight City", artist: "M83"))
        m.send(.activityStarted)
        m.send(.clicked) // expanded
        m.send(.clicked) // interactive
        #expect(m.presentation == .interactive)

        let t1 = Date().addingTimeInterval(m.autoCollapseDelay + 0.1)
        #expect(m.tick(t1) == .compact)
    }

    @Test("compact → idle on activityEnded")
    func compactToIdleOnEnd() {
        let m = IslandStateMachine()
        m.send(.activityStarted) // compact
        #expect(m.send(.activityEnded) == .idle)
    }

    @Test("expanded → compact on activityEnded")
    func expandedToCompactOnEnd() {
        let m = IslandStateMachine()
        m.setActivity(.music(title: "Midnight City", artist: "M83"))
        m.send(.activityStarted)
        m.send(.hoverEntered) // expanded
        #expect(m.send(.activityEnded) == .compact)
    }

    /// A found song as NEO's popup shows it: the bar, grown by the app's
    /// `priorityChanged`, held open for its minimum display time.
    private func heldSongPopup(for seconds: TimeInterval) -> (IslandStateMachine, Date) {
        let m = IslandStateMachine()
        m.setActivity(Activity(kind: .identifiedSong, title: "Midnight City", subtitle: "M83"))
        m.send(.activityStarted) // compact
        let start = Date()
        m.holdExpanded(until: start.addingTimeInterval(seconds))
        #expect(m.send(.priorityChanged) == .expanded)
        return (m, start)
    }

    @Test("a held expansion outlasts the idle timer and the cursor leaving, then rests as usual")
    func holdExpanded() {
        let (m, start) = heldSongPopup(for: 4.25)
        // Past the auto-collapse delay, and the cursor passing through: still open.
        #expect(m.tick(start.addingTimeInterval(m.autoCollapseDelay + 0.5)) == .expanded)
        m.send(.hoverEntered)
        #expect(m.send(.hoverExited) == .expanded)
        #expect(!m.shouldCollapse(now: start.addingTimeInterval(3)))
        #expect(m.tick(start.addingTimeInterval(4)) == .expanded)
        // Its time is up: back to the bar in one step.
        #expect(m.tick(start.addingTimeInterval(4.3)) == .compact)
        // The hold is spent: the next expansion is an ordinary one.
        m.send(.priorityChanged)
        #expect(m.presentation == .expanded)
        #expect(m.tick(Date().addingTimeInterval(m.autoCollapseDelay + 0.5)) == .compact)
    }

    @Test("a hold only ever lengthens, and only keeps the expanded shape")
    func holdOnlyLengthens() {
        let (m, start) = heldSongPopup(for: 5)
        m.holdExpanded(until: start.addingTimeInterval(2)) // a shorter one changes nothing
        #expect(m.tick(start.addingTimeInterval(3)) == .expanded)
        #expect(m.tick(start.addingTimeInterval(5.1)) == .compact)
        // A hold set while the island is not expanded keeps nothing in place.
        let idle = IslandStateMachine()
        idle.holdExpanded(until: Date().addingTimeInterval(60))
        idle.send(.hoverEntered)
        #expect(idle.send(.hoverExited) == .wings)
        #expect(idle.tick(Date().addingTimeInterval(idle.hoverCollapseDelay + 0.1)) == .idle)
    }

    @Test("a cleared hold, a click or a dismissal lets the popup go at once")
    func holdReleased() {
        // Replaced or cleared (a new song, the result gone): the usual timers apply.
        var (m, start) = heldSongPopup(for: 60)
        m.clearExpandedHold()
        #expect(m.tick(start.addingTimeInterval(m.autoCollapseDelay + 0.5)) == .compact)
        // A click is the user's: it opens the dashboard, and the hold is gone.
        (m, _) = heldSongPopup(for: 60)
        #expect(m.send(.clicked) == .interactive)
        #expect(m.send(.clicked) == .compact)
        m.send(.priorityChanged)
        #expect(m.tick(Date().addingTimeInterval(m.autoCollapseDelay + 0.5)) == .compact)
        // Dismissed: straight back to the bar.
        (m, _) = heldSongPopup(for: 60)
        #expect(m.send(.dismissed) == .compact)
    }

    @Test("isTransitioning is true after a send and clears over ticks")
    func isTransitioningLifecycle() {
        let m = IslandStateMachine()
        m.send(.activityStarted)
        #expect(m.isTransitioning)
        let later = Date().addingTimeInterval(1.0)
        m.tick(later)
        #expect(!m.isTransitioning)
    }
}
