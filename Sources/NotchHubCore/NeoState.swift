import Foundation
import NotchHubOrbs

/// What NEO (the voice assistant) is doing, as its core reports it.
///
/// The names are NEO's own (`neo2/core/events.py`); the island only ever
/// mirrors them. `idle` is NEO's ready state — hidden in the notch.
public enum NeoState: String, CaseIterable, Equatable, Sendable {
    case idle
    case connecting
    case listening
    case thinking
    case working
    case searching
    case speaking
    case confirming

    /// The thinking-orb animation NEO's own overlay plays for this state.
    public var orb: OrbState {
        switch self {
        case .idle: return .breathing
        case .listening: return .listening
        case .thinking, .working: return .solving
        case .searching: return .searching
        case .speaking: return .composing
        case .connecting: return .connecting
        case .confirming: return .shaping
        }
    }

    /// The one-line label NEO's overlay shows for the state.
    public var label: String {
        switch self {
        case .idle: return "Ready"
        case .listening: return "Listening…"
        case .thinking: return "Thinking…"
        case .working: return "Working…"
        case .searching: return "Searching…"
        case .speaking: return "Speaking…"
        case .connecting: return "Connecting…"
        case .confirming: return "Needs your OK"
        }
    }
}

/// Who a line of NEO's transcript belongs to.
public enum NeoRole: String, Equatable, Sendable {
    case user
    case assistant
}

/// A neutral fact from NEO's core, as the listener relays it. The island's
/// lane (`NeoLaneModel`) is the only thing that interprets these.
public enum NeoFact: Equatable, Sendable {
    /// The core's socket came up or went away.
    case connected(Bool)
    /// NEO's state changed (or was reported on connect).
    case state(NeoState)
    /// A transcript line. `text` is cumulative while it streams; `final`
    /// closes it.
    case transcript(role: NeoRole, text: String, final: Bool)
    /// A short-lived line NEO shows under its title (timeouts, quiet results).
    case note(String)
    /// Something went wrong in the core.
    case error(String)
    /// A card opened or closed by NEO. The browser uses chat; camera and song
    /// cards are handled by NotchHub's native surfaces.
    case card(NeoCardKind, open: Bool)
    /// NEO's song-identification state for a native notch surface.
    case songCard(NeoSongCardState)
    /// NEO's camera status; image bytes are a separate ephemeral update.
    case cameraCard(NeoCameraCardState)
    case cameraFrame(Data)
    /// NEO was summoned by hand — the hotkey, the menu-bar item, its orb —
    /// rather than by its wake word: the user asked to see it.
    case woke
    /// NEO staged a confirmation and waits for the user's OK (`confirm`, or
    /// the one still pending in the `hello`): the island's Allow / Cancel.
    case confirm(NeoConfirmCard)
    /// The confirmation with this action id is over (`confirm_done`):
    /// answered — here, by voice, in NEO's page — superseded or expired.
    case confirmDone(String)
    /// Every timer of NEO's counting down now, from the hello's `timers`
    /// (soonest first): it replaces whatever the island knew. Only a core
    /// that has timers to tell says it; an older one's hello yields nothing.
    case neoTimers([NeoTimerInfo])
    /// One of NEO's timers started, or came back after a restart (an
    /// `activity` event, `op: present`): kept by its id.
    case neoTimer(NeoTimerInfo)
    /// One of NEO's timers is over (`activity`, `op: end`): it went off
    /// (`done`), or it was cancelled. `title` is the core's, for a timer the
    /// island had not heard of.
    case neoTimerEnd(id: String, title: String, done: Bool)
    /// Search Screen's card (`lens_card`): an area of the screen the user
    /// selected, offered to the notch (`open`) or closed (and `why`). Only its
    /// id: what it shows is NEO's page's alone (`NeoLensCardModel`).
    case lensCard(cid: String, open: Bool, why: String)
}

/// Keeps each NEO state on screen for at least `minDwell`, as NEO's own
/// overlay does, so a rapid speaking → listening → speaking never strobes the
/// orb. A newer state replaces a waiting one; the last state to arrive is the
/// one that shows once things settle.
public struct NeoStateHold: Equatable, Sendable {
    /// A state must show at least this long before the next one replaces it.
    public static let defaultMinDwell: TimeInterval = 0.35

    public let minDwell: TimeInterval
    /// The state on screen now.
    public private(set) var current: NeoState = .idle
    /// A state waiting for the dwell to end, and when it may apply.
    public private(set) var pending: (state: NeoState, due: Date)?
    private var lastChange: Date?

    public init(minDwell: TimeInterval = NeoStateHold.defaultMinDwell) {
        self.minDwell = minDwell
    }

    public static func == (lhs: NeoStateHold, rhs: NeoStateHold) -> Bool {
        lhs.minDwell == rhs.minDwell && lhs.current == rhs.current
            && lhs.pending?.state == rhs.pending?.state && lhs.pending?.due == rhs.pending?.due
            && lhs.lastChange == rhs.lastChange
    }

    /// Takes a new state. Applied at once when the current one has shown long
    /// enough; otherwise it waits, and the date it may apply is returned so
    /// the caller can come back with `settle(at:)` then.
    @discardableResult
    public mutating func receive(_ next: NeoState, at now: Date) -> Date? {
        pending = nil
        let wait = lastChange.map { minDwell - now.timeIntervalSince($0) } ?? 0
        guard wait > 0 else {
            apply(next, at: now)
            return nil
        }
        let due = now.addingTimeInterval(wait)
        pending = (next, due)
        return due
    }

    /// Applies the waiting state once its time has come. Returns whether the
    /// state on screen changed.
    @discardableResult
    public mutating func settle(at now: Date) -> Bool {
        guard let waiting = pending, now >= waiting.due else { return false }
        pending = nil
        let changed = waiting.state != current
        apply(waiting.state, at: now)
        return changed
    }

    private mutating func apply(_ state: NeoState, at now: Date) {
        lastChange = now
        current = state
    }
}
