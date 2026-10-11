import Foundation

/// What NotchHub does with NEO's camera facts: open its native camera panel,
/// keep it current, close it — or leave the island alone.
///
/// Only NEO opening its camera (`camera_open`, or the hello's `camera.live`
/// when NotchHub connects after it opened) opens the panel. A `camera_state`
/// is news for a panel that is already showing and never opens one. That
/// matters most at the end of a session: NEO says `camera_state off` just
/// before `camera_close`, so a state that opened the panel turned the ×
/// into shut, open, shut — and took the island back from the Tray, Settings
/// or NEO's chat that had just replaced the camera, leaving nothing showing
/// once the close arrived.
///
/// A session the user closed, or covered with another panel, is `released`:
/// nothing NEO still says about it reaches the island. If a hello lists it
/// as live again (the stop never reached the core), NEO is asked once more
/// to stop it instead of the panel springing back open.
///
/// Pure: the app says whether the panel is showing, and acts on the `Step`.
public struct NeoCameraSurface: Equatable, Sendable {

    /// What the app does for one fact.
    public enum Step: Equatable, Sendable {
        /// Nothing for the island.
        case none
        /// Take the island for NEO's camera panel (a no-op if it shows).
        case open
        /// The showing card's state changed. `refresh` when its words did
        /// (status, answer, labels) and the panel must be redrawn; boxes
        /// alone move through the preview's own stream.
        case update(refresh: Bool)
        /// Close the camera panel.
        case close
        /// A session the user let go of is live again: ask NEO to stop it.
        case stop(String)
    }

    /// The card the panel shows, or the one an opening is about to show.
    /// `nil` while no NEO camera is on the island.
    public private(set) var card: NeoCameraCardState?
    /// The session the user closed or another panel displaced, until NEO
    /// closes it.
    public private(set) var released: String?
    /// The session NEO spoke about last — the one an opening or a close
    /// that follows it is about (the listener sends a session's state before
    /// its opening, and NEO its `off` before its close).
    private var latestSID: String?

    public init() {}

    /// A fact from NEO. `showing` is whether NEO's camera panel is on the
    /// island right now. Facts that are not about the camera are `.none`.
    public mutating func receive(_ fact: NeoFact, showing: Bool) -> Step {
        switch fact {
        case let .cameraCard(state):
            latestSID = state.sid
            guard state.sid != released else { return .none }
            let previous = card
            card = state
            // Not showing: kept for the opening that follows, never an opening.
            guard showing else { return .none }
            let reworded = previous?.status != state.status || previous?.answer != state.answer
                || previous?.labels != state.labels
            return .update(refresh: reworded)

        case .card(.camera, open: true):
            let sid = latestSID
            latestSID = nil
            if let sid, sid == released {
                // The core still has the session the user closed (its stop
                // was lost): stop it again rather than show it again.
                return .stop(sid)
            }
            return .open

        case .card(.camera, open: false):
            let sid = latestSID
            latestSID = nil
            if let sid, sid == released {
                // The session the user let go of is over: nothing left to ignore.
                released = nil
            }
            // A close for some older session never closes a newer one.
            if let sid, let shown = card?.sid, sid != shown { return .none }
            card = nil
            return showing ? .close : .none

        case .connected(false):
            // The core is gone, and with it whatever was released: a stop it
            // never received cannot have stopped anything, so the hello that
            // follows a reconnect may bring the camera back.
            self = NeoCameraSurface()
            return .none

        default:
            return .none
        }
    }

    /// The panel lets go of the camera — the ×, or another panel taking the
    /// island. Returns the session to stop (for `camera_stop`), when known.
    public mutating func release() -> String? {
        let sid = card?.sid ?? latestSID
        released = sid
        card = nil
        return sid
    }
}
