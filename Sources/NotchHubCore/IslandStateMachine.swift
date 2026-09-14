import Foundation

/// The island's explicit presentation states.
///
/// The island is one continuous black object that morphs between these shapes;
/// the state machine owns *which* shape it is in, so the view never juggles a
/// handful of ad-hoc booleans.
public enum IslandPresentation: String, CaseIterable, Equatable, Sendable {
    /// Invisible — merged with the physical notch.
    case idle
    /// The sideways hover peek: a notch-height bar that stretches left and
    /// right of the notch, showing the frontmost app on the left and live
    /// status on the right. Never grows downward.
    case wings
    /// A small pill just wider than the notch.
    case compact
    /// A wider information surface.
    case expanded
    /// The dashboard a click opens: the time, the next event, quick actions.
    case interactive
}

/// The events that drive the island between states.
public enum IslandEvent: Equatable, Sendable {
    case activityStarted
    case activityUpdated
    case activityEnded
    case hoverEntered
    case hoverExited
    case clicked
    case dismissed
    case priorityChanged
}

/// A deterministic state machine for island presentation.
///
/// Rules:
/// - idle→wings on `hoverEntered` (the sideways peek — no activity present)
/// - idle→compact on `activityStarted`
/// - wings→compact on `activityStarted` (a real activity takes the pill)
/// - idle/wings→interactive (the dashboard) on `clicked`; wings→idle on
///   `hoverExited` / `dismissed`
/// - compact→expanded on `hoverEntered` / `clicked` / `priorityChanged`,
///   but ONLY when the current activity has more to show (`Activity.canExpand`).
///   A transient readout — volume, brightness, battery, Wi-Fi, a device
///   connecting — is complete in the compact bar, so it stays a pill; a CLICK
///   on it opens the dashboard instead.
/// - expanded→interactive on `clicked`; interactive→resting (compact while an
///   activity is live, the wings while the cursor is on the notch, else idle)
///   on `clicked` again, `dismissed`, or the cursor leaving
/// - expanded/interactive→compact on `hoverExited` (only once
///   `shouldCollapse` is true, so a momentary leave during animation doesn't
///   collapse) or on `activityEnded`
/// - compact→idle on `activityEnded` / `dismissed`
///
/// `tick(_:)` enforces auto-collapse so the island can never get stuck
/// expanded: a transient activity that has expired, or a presentation that has
/// sat expanded/interactive past `autoCollapseDelay` with no hover, collapses
/// in ONE motion to its resting shape — compact while an activity remains,
/// idle when it has expired or there is none. The wings are a bare peek and
/// step straight back to idle — never down into the compact pill.
public final class IslandStateMachine {
    public private(set) var presentation: IslandPresentation = .idle
    public private(set) var activity: Activity?
    public private(set) var isTransitioning = false

    /// How long to wait after the cursor leaves before collapsing (lets a
    /// momentary exit during animation pass without collapsing).
    public var hoverCollapseDelay: TimeInterval = 0.6
    /// How long an expanded/interactive island lingers with no interaction
    /// before stepping down toward idle.
    public var autoCollapseDelay: TimeInterval = 1.6

    /// How long `isTransitioning` stays true after an event.
    private let transitionDuration: TimeInterval = 0.3

    /// Whether the cursor is currently over the island. Public so the app can
    /// keep a bare hover peek open instead of collapsing it when no activity
    /// is present.
    public var isHovering = false
    private var lastHoverExit: Date?
    private var lastInteraction: Date?
    private var lastTransition: Date?

    public init() {}

    /// Sets the activity the island is currently presenting. The coordinator
    /// calls this as activities come and go; the machine only mirrors it.
    public func setActivity(_ activity: Activity?) {
        self.activity = activity
    }

    /// Feeds one event into the machine and returns the resulting state.
    @discardableResult
    public func send(_ e: IslandEvent) -> IslandPresentation {
        let now = Date()
        isTransitioning = true
        lastTransition = now

        switch e {
        case .activityStarted:
            lastInteraction = now
            switch presentation {
            case .idle: presentation = .compact
            case .wings: presentation = .compact // a real activity takes the pill
            default: break
            }

        case .activityUpdated:
            lastInteraction = now

        case .activityEnded:
            lastInteraction = now
            switch presentation {
            case .compact: presentation = .idle
            case .wings: presentation = .idle
            case .expanded: presentation = .compact
            // The dashboard does not depend on the activity: it stays open.
            case .interactive, .idle: break
            }

        case .hoverEntered:
            isHovering = true
            lastInteraction = now
            switch presentation {
            case .idle:
                // Peek: hovering the notch reveals the island even when no
                // activity is present. From a true idle the peek is the
                // sideways wings — the resting surface tucks back behind the
                // notch once the cursor leaves.
                presentation = .wings
            case .wings:
                break // already showing the wings; stay put
            case .compact:
                // Only expand when the activity has something more to show. A
                // transient readout (volume, brightness, battery, …) already
                // says everything in the bar, so hovering leaves it a pill —
                // and a call's bar holds its own buttons to be clicked.
                if activity?.expandsOnHover ?? false { presentation = .expanded }
            default:
                break
            }

        case .hoverExited:
            isHovering = false
            lastHoverExit = now
            // Collapse only once the exit has "settled" — a momentary leave
            // during animation must not collapse the island.
            if shouldCollapse(now: now) {
                switch presentation {
                case .wings: presentation = .idle
                case .expanded: presentation = .compact
                case .interactive: presentation = restingPresentation(now: now)
                default: break
                }
            }

        case .clicked:
            lastInteraction = now
            switch presentation {
            case .idle, .wings:
                // A click on the notch opens the dashboard.
                presentation = .interactive
            case .compact:
                // A bar with more to show (a song, a call) grows first; a
                // readout that is complete in the bar opens the dashboard
                // rather than growing its pill.
                presentation = (activity?.canExpand ?? false) ? .expanded : .interactive
            case .expanded:
                presentation = .interactive
            case .interactive:
                // A second click closes the dashboard.
                presentation = restingPresentation(now: now)
            }

        case .dismissed:
            lastInteraction = now
            switch presentation {
            case .interactive: presentation = restingPresentation(now: now)
            case .expanded: presentation = .compact
            case .wings: presentation = .idle
            case .compact: presentation = .idle
            case .idle: break
            }

        case .priorityChanged:
            lastInteraction = now
            if presentation == .compact, activity?.canExpand ?? false {
                presentation = .expanded
            }
        }

        return presentation
    }

    /// Forces the island into the sideways wings and holds it there.
    ///
    /// This is an inspection hook, not part of the interaction model: it exists
    /// so the peek can be held open on screen (`--wings`) without a cursor on
    /// the notch. It marks the cursor as hovering so `tick(_:)` will not
    /// auto-collapse the wings out from under the inspection.
    public func forceWings() {
        isHovering = true
        lastInteraction = Date()
        presentation = .wings
        isTransitioning = true
        lastTransition = Date()
    }

    /// Where the island rests when a larger surface closes: the compact bar
    /// while an activity is live, otherwise the wings if the cursor is still
    /// on the notch, otherwise idle.
    private func restingPresentation(now: Date) -> IslandPresentation {
        if let activity, !activity.isExpired(at: now) { return .compact }
        return isHovering ? .wings : .idle
    }

    /// Whether the island is allowed to collapse from a hover exit at `now`.
    ///
    /// False immediately after the cursor leaves; true once `hoverCollapseDelay`
    /// has passed since the last exit.
    public func shouldCollapse(now: Date) -> Bool {
        guard let exit = lastHoverExit else { return true }
        return now.timeIntervalSince(exit) >= hoverCollapseDelay
    }

    /// Advances time. Clears the transition flag, then steps the presentation
    /// down toward idle whenever it would otherwise get stuck expanded.
    @discardableResult
    public func tick(_ now: Date) -> IslandPresentation {
        if let lt = lastTransition, now.timeIntervalSince(lt) >= transitionDuration {
            isTransitioning = false
        }

        let activityExpired = activity?.isExpired(at: now) ?? false
        let idleSince = lastInteraction.map { now.timeIntervalSince($0) } ?? .greatestFiniteMagnitude
        let hoverExitCollapse = !isHovering && lastHoverExit != nil && shouldCollapse(now: now)
        let idleAutoCollapse = !isHovering && idleSince > autoCollapseDelay
        let shouldStepDown = activityExpired || hoverExitCollapse || idleAutoCollapse

        switch presentation {
        case .interactive:
            // The dashboard is its own surface: an activity expiring behind it
            // does not close it — only the cursor leaving or inactivity does.
            if hoverExitCollapse || idleAutoCollapse {
                presentation = restingPresentation(now: now)
                isTransitioning = true
                lastInteraction = now
            }
        case .expanded:
            // Collapse straight to the resting shape in ONE motion. Stepping
            // down a level per tick played as a staircase of separate springs.
            if shouldStepDown {
                presentation = restingPresentation(now: now)
                isTransitioning = true
                lastInteraction = now
            }
        case .wings:
            // The wings are a bare hover peek: they tuck back behind the notch
            // as soon as the cursor leaves (or nothing has happened for a
            // while). They never step down to compact — that would grow the
            // island downward, which is exactly what the wings exist to avoid.
            if hoverExitCollapse || idleAutoCollapse || activityExpired {
                presentation = .idle
                isTransitioning = true
            }
        case .compact:
            // An activity-driven compact expires on its own; a bare hover peek
            // (no activity) tucks back behind the notch once the cursor leaves.
            let barePeek = (activity == nil)
            if activityExpired || (barePeek && (hoverExitCollapse || idleAutoCollapse)) {
                presentation = .idle
                isTransitioning = true
            }
        case .idle:
            break
        }

        return presentation
    }
}
