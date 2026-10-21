import Foundation

/// The keyboard Search Screen's card takes without activating NotchHub
/// (`NotchWindow.takeKeysQuietly`), and when it goes back.
///
/// Keys taken quietly go back by ordering the island's window out and
/// straight back in — what ends a non-activating panel's key status (the
/// window server hands the keyboard to the active app, the user's). That
/// never happens while the island moves: the panel folds with its keys
/// still held, the page no longer first responder (nothing typed reaches
/// the card), and they go back once the retract is home (`returnDelay`) —
/// or at once when a key is pressed before then: the user typing into their
/// own app again outranks the wait.
///
/// Pure: the window asks it what to do, and does it.
public struct NeoQuietKeys: Equatable, Sendable {
    /// How long after the fold starts the keys go back: once the retract is
    /// home — the moment the island itself counts it done and starts fading
    /// the surface (`DesignTokens.retractFadeDelay`), hidden behind the
    /// physical notch. Every visible step of the fold (the content's exit, the
    /// spring's travel) is over by then.
    public static let returnDelay: TimeInterval = DesignTokens.retractFadeDelay

    public enum Phase: Equatable, Sendable {
        /// The island holds no keys of the card's.
        case none
        /// The card's panel has the keyboard.
        case taken
        /// The panel folded: the keys are held until `returnAt`, then go back.
        case returning
    }

    public private(set) var phase: Phase = .none
    /// When the keys go back (while `returning`).
    public private(set) var returnAt: Date?

    public init() {}

    /// The card's panel has the keys (`canBecomeKey`, the page first for ⌘-keys).
    public var isTaken: Bool { phase == .taken }
    /// The fold is under way and the keys are still held.
    public var isReturning: Bool { phase == .returning }

    /// The card's panel takes the keys — a new card's panel opening while the
    /// last one's keys were still going back keeps them.
    public mutating func take() {
        phase = .taken
        returnAt = nil
    }

    /// The panel folds. Returns when to give the keys back, or `nil` when
    /// there is nothing to give back (no keys of the card's, or the window
    /// is no longer key: a click elsewhere took them already).
    public mutating func fold(isKey: Bool, at now: Date) -> Date? {
        guard phase == .taken else { return nil }
        guard isKey else {
            phase = .none
            returnAt = nil
            return nil
        }
        let due = now.addingTimeInterval(Self.returnDelay)
        phase = .returning
        returnAt = due
        return due
    }

    /// The timer `fold` asked for (`at` is the time it returned) went off:
    /// whether to give the keys back now — once, and only for this fold (a
    /// timer left over from an earlier one does nothing).
    public mutating func due(_ at: Date) -> Bool {
        guard phase == .returning, returnAt == at else { return false }
        phase = .none
        returnAt = nil
        return true
    }

    /// A key pressed while the keys are going back: give them back now.
    /// Returns whether it was so (the key itself is then swallowed — no
    /// responder of the island's wants it).
    public mutating func typed() -> Bool {
        guard phase == .returning else { return false }
        phase = .none
        returnAt = nil
        return true
    }

    /// The window stopped being key on its own (a click elsewhere). Returns
    /// whether the card's panel had the keys — then it folds ("away"); keys
    /// that were already going back are simply gone.
    public mutating func resigned() -> Bool {
        let had = phase == .taken
        phase = .none
        returnAt = nil
        return had
    }

    /// A panel took the keys for real (`needsInteraction`: it is made key and
    /// NotchHub activated): nothing is given back behind its back.
    public mutating func interaction() {
        guard phase == .returning else { return }
        phase = .none
        returnAt = nil
    }
}
