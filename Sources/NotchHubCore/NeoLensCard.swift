import Foundation

/// Search Screen's card in the notch: when NotchHub hosts NEO's UI, the
/// area the user selected on NEO's Search Screen overlay flies up into the
/// notch, and NEO's panel opens with its results (drawn by NEO's own page,
/// which hears them from NEO's core directly). NotchHub's connection hears
/// only the card's id, whether it is open and why it closed — never what it
/// shows.
///
/// What the app does about it, pure:
/// - offered (`lens_card` open): NotchHub says it shows it, unless it can't
///   (`canShow`: the NEO feature off, no NEO page, NEO's camera holding the
///   island, Allow / Cancel showing) — then it refuses, and NEO shows its
///   results beside the selection instead;
/// - `openDelay` later the panel opens for it (as the area arrives in the
///   notch), and takes the keys without taking them from the user's app;
/// - closed by the core: the panel folds — except for Continue in NEO and a
///   chat turn, which turn the panel into the chat (`keepsPanel`);
/// - the panel folding for any other reason (Esc, a click elsewhere, another
///   panel, NEO's camera) closes the card (`panelFolded`).
public struct NeoLensCardModel: Equatable, Sendable {
    /// The panel opens this long after the offer: as the flying area arrives.
    public static let openDelay: TimeInterval = 0.24
    /// The closes after which the panel stays, as the chat.
    public static let keepsPanel: Set<String> = ["continue", "chat"]

    /// The card offered or showing, if any.
    public private(set) var cid: String?
    /// Whether the panel is open for it (after `openDelay`).
    public private(set) var isOpen = false

    public enum Step: Equatable, Sendable {
        /// Say it is shown (`lens_card_shown`), then open the panel after `openDelay`.
        case offer(String)
        /// Say it can't be shown (`lens_card_close` "unshown").
        case refuse(String)
        /// Open the panel for it now.
        case open(String)
        /// It closed: take it off the panel, and fold the panel when `fold`.
        case close(fold: Bool)
        case none
    }

    public init() {}

    /// A `lens_card` from the core.
    public mutating func receive(cid: String, open: Bool, why: String, canShow: Bool) -> Step {
        if open {
            guard canShow else { return .refuse(cid) }
            if self.cid != cid { isOpen = false }
            self.cid = cid
            return .offer(cid)
        }
        guard cid == self.cid else { return .none } // (an older card's close)
        let wasOpen = isOpen
        self.cid = nil
        isOpen = false
        return .close(fold: wasOpen && !Self.keepsPanel.contains(why))
    }

    /// `openDelay` after the offer: the panel opens — if the card is still
    /// the one offered (the core may have closed it meanwhile).
    public mutating func due(cid: String) -> Step {
        guard cid == self.cid, !isOpen else { return .none }
        isOpen = true
        return .open(cid)
    }

    /// It could not open after all (the island was taken in those 240 ms):
    /// forgotten, so nothing more is said of it.
    public mutating func dropped(cid: String) {
        guard cid == self.cid else { return }
        self.cid = nil
        isOpen = false
    }

    /// The panel folded for something that is not the card's own close: the
    /// card it showed, to close (once).
    public mutating func panelFolded() -> String? {
        guard let cid, isOpen else { return nil }
        self.cid = nil
        isOpen = false
        return cid
    }

    /// The core went away: the card went with it.
    public mutating func disconnected() {
        cid = nil
        isOpen = false
    }
}
