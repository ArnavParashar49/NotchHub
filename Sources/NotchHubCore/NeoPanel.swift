import CoreGraphics
import Foundation

/// A card NEO opens in its chat: the live browser, the camera preview, the
/// song it is listening for. While one is open the panel stays open.
public enum NeoCardKind: String, CaseIterable, Equatable, Sendable {
    case browser
    case camera
    case song
}

/// Whether NEO's panel — its whole chat, hanging down from the notch — is
/// open, and when it closes on its own.
///
/// The rules, as the lane's: pure and clock-driven, every method takes `now`
/// and `nextWake(at:)` says when the panel will change by itself.
///
/// - NEO thinking, working, searching or speaking never opens it: a voice
///   answer is the orb's alone, animating in the notch. It opens only when
///   NEO needs the user — a confirmation ("Needs your OK"), a card (the
///   browser, the camera, a song), the page asking to be seen (a login
///   page, a question) — or when the user asks: a click on the lane, or
///   NEO summoned by hand (the hotkey, the tray: `woke`).
/// - Once open it closes `idleCollapseDelay` after NEO is quiet (idle or
///   merely listening) — unless the mouse is in it, a card is open, it is
///   pinned, or it was opened by hand and NEO has not answered since. While
///   NEO is answering an open panel stays open: it never folds mid-reply.
/// - Esc / the page's collapse / a click on the lane close it at once; closed
///   while NEO was busy, it stays closed until NEO is quiet again, so the
///   rest of that turn (a card, a confirmation) does not pop it back open.
public struct NeoPanelModel: Equatable, Sendable {
    /// How long after NEO goes quiet the panel folds back into the lane.
    public static let idleCollapseDelay: TimeInterval = 5
    /// The states in which NEO is answering: an open panel is held through
    /// them, and a hand-opened hold is spent by them. They do NOT open it.
    public static let answeringStates: Set<NeoState> = [.thinking, .working, .searching, .speaking, .confirming]
    /// The one state that opens the panel on its own: NEO needs the user.
    public static let openingStates: Set<NeoState> = [.confirming]

    public private(set) var isOpen = false
    public private(set) var cards: Set<NeoCardKind> = []
    public private(set) var isHovered = false
    public private(set) var isPinned = false
    /// Opened by hand or at the page's request: held until NEO answers once
    /// more (then the ordinary quiet delay applies) or the user closes it.
    private var heldByUser = false
    /// Closed by the user while NEO was answering: stays closed until quiet.
    private var dismissedUntilQuiet = false
    private var state: NeoState = .idle
    /// When the panel became collapsible; `nil` while something holds it.
    private var quietSince: Date?
    private var lastReported = false

    public init() {}

    static func isAnswering(_ state: NeoState) -> Bool { answeringStates.contains(state) }

    /// Whether anything keeps the panel from folding.
    public var isHeld: Bool {
        isPinned || isHovered || !cards.isEmpty || heldByUser || Self.isAnswering(state)
    }

    /// NEO's (held, shown) state — from the lane, so lane and panel agree.
    public mutating func receive(state next: NeoState, at now: Date) {
        state = next
        if Self.isAnswering(next) {
            // A new answer: the hand-opened hold is spent (the quiet clock
            // runs once NEO is done). Only NEO needing the user opens it.
            heldByUser = false
            if Self.openingStates.contains(next), !dismissedUntilQuiet {
                isOpen = true
            }
        } else {
            dismissedUntilQuiet = false
        }
        settle(at: now)
    }

    /// A card opened or closed in the chat.
    public mutating func card(_ kind: NeoCardKind, open: Bool, at now: Date) {
        if open {
            cards.insert(kind)
            if !dismissedUntilQuiet { isOpen = true }
        } else {
            cards.remove(kind)
        }
        settle(at: now)
    }

    /// The page asked to be seen (a login page, a question), NEO was
    /// summoned by hand (the hotkey, the tray), or the lane was clicked
    /// while closed: the explicit show.
    public mutating func show(at now: Date) {
        isOpen = true
        heldByUser = true
        dismissedUntilQuiet = false
        settle(at: now)
    }

    /// Esc, the page's collapse, or the lane clicked while open.
    public mutating func close(at now: Date) {
        isOpen = false
        heldByUser = false
        isPinned = false
        if Self.isAnswering(state) { dismissedUntilQuiet = true }
        settle(at: now)
    }

    /// A click on the lane.
    public mutating func toggle(at now: Date) {
        if isOpen { close(at: now) } else { show(at: now) }
    }

    public mutating func hover(_ inside: Bool, at now: Date) {
        isHovered = inside
        settle(at: now)
    }

    public mutating func pin(_ on: Bool, at now: Date) {
        isPinned = on
        settle(at: now)
    }

    /// The core went away: nothing to show.
    public mutating func disconnected(at now: Date) {
        isOpen = false
        cards = []
        heldByUser = false
        dismissedUntilQuiet = false
        isPinned = false
        state = .idle
        settle(at: now)
    }

    /// Applies a due collapse. Returns whether `isOpen` changed since the app
    /// last heard from the model.
    @discardableResult
    public mutating func tick(at now: Date) -> Bool {
        if isOpen, let since = quietSince, now >= since.addingTimeInterval(Self.idleCollapseDelay) {
            isOpen = false
            quietSince = nil
        }
        defer { lastReported = isOpen }
        return isOpen != lastReported
    }

    /// When the panel will fold on its own, if it will.
    public func nextWake(at now: Date) -> Date? {
        guard isOpen, let since = quietSince else { return nil }
        let due = since.addingTimeInterval(Self.idleCollapseDelay)
        return due > now ? due : now
    }

    /// Starts or stops the quiet clock from what holds the panel now.
    private mutating func settle(at now: Date) {
        if !isOpen || isHeld {
            quietSince = nil
        } else if quietSince == nil {
            quietSince = now
        }
        lastReported = isOpen
    }
}

/// How big NEO's panel is: the chat's own size, grown when the page asks for
/// more (a browser card), within what the screen allows.
public enum NeoPanelLayout {
    /// The chat's size in CSS points — what NEO's page lays itself out for.
    public static let standard = CGSize(width: 420, height: 520)
    /// The widest and tallest the page may ask for, as fractions of the screen.
    public static let maxWidthFraction: CGFloat = 0.6
    public static let maxWidth: CGFloat = 1000
    public static let maxHeightFraction: CGFloat = 0.86

    /// The most the page may have on a screen of `screen`.
    public static func maxPageSize(screen: CGSize) -> CGSize {
        CGSize(
            width: max(standard.width, min(screen.width * maxWidthFraction, maxWidth)),
            height: max(standard.height, screen.height * maxHeightFraction)
        )
    }

    /// The page size the panel gives for a request, never smaller than the
    /// chat and never more than the screen allows.
    public static func pageSize(requested: CGSize?, screen: CGSize) -> CGSize {
        let limit = maxPageSize(screen: screen)
        let request = requested ?? standard
        return CGSize(
            width: min(limit.width, max(standard.width, request.width.rounded())),
            height: min(limit.height, max(standard.height, request.height.rounded()))
        )
    }
}

/// What NEO's page asks of its host, through `window.webkit.messageHandlers.neo`
/// (see `ui/src/shell.ts` in NEO). Parsed here so a malformed message is a
/// `nil`, never a crash — the page is NEO's, but the parser is ours.
public enum NeoHostMessage: Equatable, Sendable {
    /// Be seen: a login page, a question, a wake.
    case show
    /// Fold away: Esc, the collapse button.
    case collapse
    /// Keys should reach the page.
    case focus
    /// Open a link in the user's browser (http(s) only).
    case openURL(URL)
    /// Write the pasteboard (the browser card's copy).
    case clipboard(String)
    /// The page would like this much room, in CSS points.
    case size(CGSize)
    /// The user pinned the panel open (or unpinned it).
    case pin(Bool)

    /// The most text a clipboard message may carry (NEO's own shell caps the
    /// same way).
    public static let maxClipboard = 400_000

    public static func parse(_ body: Any) -> NeoHostMessage? {
        guard let dict = body as? [String: Any], let type = dict["type"] as? String else { return nil }
        switch type {
        case "show": return .show
        case "collapse": return .collapse
        case "focus": return .focus
        case "open_url":
            guard let text = dict["url"] as? String, let url = URL(string: text),
                  let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", url.host != nil else { return nil }
            return .openURL(url)
        case "clipboard":
            guard let text = dict["text"] as? String else { return nil }
            return .clipboard(String(text.utf8.prefix(maxClipboard)).map { $0 } ?? text)
        case "size":
            guard let w = number(dict["w"]), let h = number(dict["h"]), w > 0, h > 0, w < 10_000, h < 10_000 else { return nil }
            return .size(CGSize(width: w, height: h))
        case "pin":
            guard let on = dict["on"] as? Bool else { return nil }
            return .pin(on)
        default:
            return nil
        }
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let n as NSNumber: return n.doubleValue.isFinite ? n.doubleValue : nil
        case let d as Double: return d.isFinite ? d : nil
        case let i as Int: return Double(i)
        default: return nil
        }
    }
}
