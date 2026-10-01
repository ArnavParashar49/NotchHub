import CoreGraphics
import Foundation

/// What NEO's lane shows: the orb's state, and the line that describes it.
///
/// The lane DRAWS only the orb (`NeoLaneLayout`); `line` is what NEO hears,
/// says or is doing, kept for accessibility (the lane's spoken label) and
/// for anything that wants to know what the orb stands for. It never widens
/// the lane.
public struct NeoLaneContent: Equatable, Sendable {
    public var state: NeoState
    /// What the orb stands for: what NEO hears, what it says, or its label.
    public var line: String
    /// Whether `line` is a transcript (its latest words matter) rather than
    /// a label.
    public var isTranscript: Bool

    public init(state: NeoState, line: String, isTranscript: Bool = false) {
        self.state = state
        self.line = line
        self.isTranscript = isTranscript
    }
}

/// The lane's own state: NEO's held state, its transcript lines, the notes
/// and errors that briefly replace them, and when the lane tucks back in.
///
/// Pure and clock-driven: every method takes `now`, and `nextWake(at:)` says
/// when something will change on its own, so the app runs no timers of its
/// own and the behaviour can be tested to the millisecond. Nothing here is an
/// activity — NEO never competes with the island's queue.
public struct NeoLaneModel: Equatable, Sendable {
    /// How long after NEO returns to idle the lane stays out, so the last
    /// thing it said can be read, before tucking back into the notch.
    public static let hideDelay: TimeInterval = 1.2
    /// How long a note or an error replaces the line.
    public static let noteLifetime: TimeInterval = 8

    public private(set) var hold: NeoStateHold
    /// Whether the core's socket is up. While it is not, there is nothing to
    /// show — NEO may simply be off.
    public private(set) var isConnected = false
    private var userText = ""
    private var assistantText = ""
    private var notice: (text: String, until: Date)?
    /// When the lane's state became idle after being busy — the hide delay
    /// runs from it. `nil` while busy, or when it was never out.
    private var idleAt: Date?
    /// What the lane showed when the app last heard from the model, so
    /// `tick` can say whether a render is due.
    private var lastReported: NeoLaneContent?

    public init(minDwell: TimeInterval = NeoStateHold.defaultMinDwell) {
        hold = NeoStateHold(minDwell: minDwell)
    }

    public static func == (lhs: NeoLaneModel, rhs: NeoLaneModel) -> Bool {
        lhs.hold == rhs.hold && lhs.isConnected == rhs.isConnected
            && lhs.userText == rhs.userText && lhs.assistantText == rhs.assistantText
            && lhs.notice?.text == rhs.notice?.text && lhs.notice?.until == rhs.notice?.until
            && lhs.idleAt == rhs.idleAt
    }

    /// The state the lane shows (after the dwell).
    public var state: NeoState { hold.current }

    /// Takes one fact from the core. Returns when to come back with
    /// `tick(at:)`, if something will change on its own.
    @discardableResult
    public mutating func receive(_ fact: NeoFact, at now: Date) -> Date? {
        switch fact {
        case let .connected(up):
            isConnected = up
            if !up {
                // The core went away: whatever it was doing is over.
                hold.receive(.idle, at: now)
                hold.settle(at: now)
                userText = ""
                assistantText = ""
                notice = nil
                idleAt = nil
            }
        case let .state(next):
            if next == .listening { userText = "" } // a fresh listen
            let wasIdle = hold.current == .idle
            hold.receive(next, at: now)
            noteIdle(wasIdle: wasIdle, at: now)
        case let .transcript(role, text, _):
            switch role {
            case .user:
                userText = text
                assistantText = "" // the reply to this comes later
            case .assistant:
                assistantText = text
            }
        case let .note(text):
            notice = text.isEmpty ? nil : (text, now.addingTimeInterval(Self.noteLifetime))
        case let .error(message):
            notice = message.isEmpty ? nil : (message, now.addingTimeInterval(Self.noteLifetime))
        case .card, .woke:
            break // the panel's business (`NeoPanelModel`), not the lane's
        }
        lastReported = content(at: now)
        return nextWake(at: now)
    }

    /// Advances the clock: applies a held state whose dwell has ended and drops
    /// an expired notice. Returns whether what the lane shows has changed
    /// since the app last heard from it (including tucking in).
    @discardableResult
    public mutating func tick(at now: Date) -> Bool {
        let wasIdle = hold.current == .idle
        if hold.settle(at: now) { noteIdle(wasIdle: wasIdle, at: now) }
        if let notice, now >= notice.until { self.notice = nil }
        let current = content(at: now)
        defer { lastReported = current }
        return current != lastReported
    }

    /// Starts the tuck-in clock when the shown state has just become idle,
    /// and stops it while NEO is busy.
    private mutating func noteIdle(wasIdle: Bool, at now: Date) {
        if hold.current == .idle {
            if !wasIdle { idleAt = now }
        } else {
            idleAt = nil
        }
    }

    /// The next moment the lane will change on its own, if any: a held state
    /// becoming due, a notice expiring, or the lane tucking back in.
    public func nextWake(at now: Date) -> Date? {
        var dates: [Date] = []
        if let pending = hold.pending { dates.append(pending.due) }
        if let notice { dates.append(notice.until) }
        if hold.current == .idle, hold.pending == nil, let hideAt = hideDate, hideAt > now { dates.append(hideAt) }
        return dates.min()
    }

    /// When the lane tucks in after NEO went idle.
    private var hideDate: Date? { idleAt?.addingTimeInterval(Self.hideDelay) }

    /// Whether the lane is out of the notch: while NEO is doing anything, and
    /// for `hideDelay` after it stops.
    public func isShown(at now: Date) -> Bool {
        guard isConnected else { return false }
        if hold.current != .idle { return true }
        if let pending = hold.pending, pending.state != .idle { return true }
        guard let hideAt = hideDate else { return false }
        return now < hideAt
    }

    /// What the lane shows now, or `nil` while it is tucked in.
    public func content(at now: Date) -> NeoLaneContent? {
        guard isShown(at: now) else { return nil }
        let state = hold.current
        if let notice, now < notice.until {
            return NeoLaneContent(state: state, line: notice.text)
        }
        switch state {
        case .listening:
            return userText.isEmpty
                ? NeoLaneContent(state: state, line: state.label)
                : NeoLaneContent(state: state, line: userText, isTranscript: true)
        case .speaking, .idle:
            // Idle is only shown during the tuck-in delay: the last reply
            // stays readable until the lane is gone.
            return assistantText.isEmpty
                ? NeoLaneContent(state: state, line: state.label)
                : NeoLaneContent(state: state, line: assistantText, isTranscript: true)
        case .thinking, .working, .searching, .connecting, .confirming:
            return NeoLaneContent(state: state, line: state.label)
        }
    }
}

/// Where the orb goes, and how wide the lane is.
///
/// The lane is the notch-height strip at the island's own LEFT EDGE:
/// `[inset][orb][inset]`, then whatever the shape holds, then the notch —
/// the orb and nothing else, no words. Its width is the orb plus a little
/// padding on either side (the notch's height plus 12 pt), the same in every
/// state and every island shape. The bars grow their left side by it, so
/// their content sits between the orb and the notch; and because the orb is
/// glued to the island's edge, it RIDES every change of shape — a volume
/// readout growing the bar, the wings, the expanded song — on the island's
/// own spring, instead of standing still while the island moves around it.
public enum NeoLaneLayout {
    /// From the lane's outer edge to the orb.
    public static let outerInset: CGFloat = 8
    /// From the orb to the notch's edge.
    public static let innerInset: CGFloat = 8
    /// The orb's inset from the top and bottom of the notch strip: the orb is
    /// the full notch height less a hair, so it is the first thing you see.
    public static let orbInset: CGFloat = 2

    /// The orb's diameter: the notch's height less its insets.
    public static func orbSize(notchHeight: CGFloat) -> CGFloat {
        max(16, notchHeight - orbInset * 2)
    }

    /// How far the lane reaches left of the notch: the orb and its padding.
    public static func width(notchHeight: CGFloat) -> CGFloat {
        outerInset + orbSize(notchHeight: notchHeight) + innerInset
    }

    /// The lane's rectangle on an island of `island` (AppKit coordinates,
    /// origin bottom-left): the notch strip at the island's left edge.
    public static func rect(in island: CGRect, width: CGFloat, notchHeight: CGFloat) -> CGRect {
        CGRect(x: island.minX, y: island.maxY - notchHeight, width: width, height: notchHeight)
    }

    /// The lane as it fits a FIXED surface (a panel, the expanded island),
    /// which does not grow for it: the room between the surface's left edge
    /// and the notch, less a hair. Every such surface is wider than the
    /// lane, so this is the lane's own width; it only ever cuts the lane on
    /// a surface narrower than the notch plus two lanes.
    public static func fitted(width: CGFloat, surfaceWidth: CGFloat, notchWidth: CGFloat) -> CGFloat {
        let room = ((surfaceWidth - notchWidth) / 2 - 2).rounded(.down)
        return max(0, min(width, room))
    }
}

/// What a click on the island does for NEO.
///
/// While NEO is active — its orb out of the notch — the island IS NEO's
/// door: a click anywhere on it (not only on the orb) opens the chat. With
/// NEO tucked in, clicks keep the island's own meaning (the dashboard, the
/// song, the call controls). With the panel open, a click on the lane in
/// its strip closes it; the rest of the panel is the page's.
public enum NeoIslandClick {
    public enum Outcome: Equatable, Sendable {
        case open
        case close
        case none
    }

    /// - Parameters:
    ///   - laneShown: whether NEO's orb is out (`IslandContentSize.neoLead > 0`).
    ///   - panelOpen: whether NEO's panel has the island.
    ///   - otherPanel: whether another surface (settings, the Tray, the pet…)
    ///     has the island — its controls keep their clicks.
    ///   - point: the click, in the same coordinates as `laneRect`.
    public static func outcome(laneShown: Bool, panelOpen: Bool, otherPanel: Bool, point: CGPoint, laneRect: CGRect) -> Outcome {
        if panelOpen {
            return laneRect.contains(point) ? .close : .none
        }
        guard laneShown, !otherPanel else { return .none }
        return .open
    }
}
