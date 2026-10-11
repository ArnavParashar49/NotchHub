import CoreGraphics
import Foundation

/// A card NEO can open: browser cards use the embedded page; camera and song
/// cards are rendered by NotchHub's native surfaces.
public enum NeoCardKind: String, CaseIterable, Equatable, Sendable {
    case browser
    case camera
    case song
}

/// A live song-identification update from NEO. The cover is already fetched
/// by NEO and arrives as image bytes; the notch never loads a remote image.
public struct NeoSongCardState: Equatable, Sendable {
    public var sid: String
    public var status: String
    public var level: Double
    public var elapsed: Double
    public var message: String?
    public var title: String?
    public var artist: String?
    public var album: String?
    public var year: String?
    public var cover: Data?

    public init(sid: String, status: String, level: Double = 0, elapsed: Double = 0,
                message: String? = nil, title: String? = nil, artist: String? = nil,
                album: String? = nil, year: String? = nil, cover: Data? = nil) {
        self.sid = sid
        self.status = status
        self.level = level
        self.elapsed = elapsed
        self.message = message
        self.title = title
        self.artist = artist
        self.album = album
        self.year = year
        self.cover = cover
    }
}

/// The textual part of NEO's camera card. Preview pixels travel separately so
/// they never enter the event log or transcript history.
public struct NeoCameraBox: Equatable, Sendable, Identifiable {
    public var id: Int
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double
    public var label: String
    public var score: Double

    public init(id: Int, x: Double, y: Double, w: Double, h: Double, label: String, score: Double) {
        self.id = id
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.label = label
        self.score = score
    }
}

public struct NeoCameraCardState: Equatable, Sendable {
    public var sid: String
    public var status: String
    public var answer: String?
    public var labels: [String]
    public var boxes: [NeoCameraBox]

    public init(sid: String, status: String, answer: String? = nil, labels: [String] = [], boxes: [NeoCameraBox] = []) {
        self.sid = sid
        self.status = status
        self.answer = answer
        self.labels = labels
        self.boxes = boxes
    }
}

/// Whether NEO's embedded chat — hanging down from the notch — is open, and
/// when it closes on its own. Native camera and song surfaces are tracked by
/// NotchHub separately and do not open this panel.
///
/// The rules, as the lane's: pure and clock-driven, every method takes `now`
/// and `nextWake(at:)` says when the panel will change by itself.
///
/// - NEO thinking, working, searching or speaking never opens it: a voice
///   answer is the orb's alone, animating in the notch. Nor does NEO needing
///   an OK: that is the island's own Allow / Cancel under the notch
///   (`NeoConfirmModel`), not the whole chat. It opens only for a browser
///   card, the page asking to be seen (a login
///   page, a question) — or when the user asks: a click on the lane, or
///   NEO summoned by hand (the hotkey, the tray: `woke`). A panel that is
///   already open shows the page's own confirm card, and is held open
///   while NEO waits on it.
/// - Once open it closes `idleCollapseDelay` after NEO is quiet (idle or
///   merely listening) — unless the mouse is in it, a card is open, it is
///   pinned, or it was opened by hand and NEO has not answered since. While
///   NEO is answering an open panel stays open: it never folds mid-reply.
/// - Esc / the page's collapse / a click on the lane close it at once; closed
///   while NEO was busy, it stays closed until NEO is quiet again, so the
///   rest of that turn (a card, a confirmation) does not pop it back open.
/// - The core going away does not yank an open panel: the page shows its
///   own quiet "reconnecting…" line and the panel waits `reconnectGrace`
///   for the core to come back (a restart takes a few seconds). Only if it
///   does not does the panel fold; a panel that was closed stays closed.
public struct NeoPanelModel: Equatable, Sendable {
    /// How long after NEO goes quiet the panel folds back into the lane.
    public static let idleCollapseDelay: TimeInterval = 5
    /// How long an open panel waits for a restarting core before folding: a
    /// restart of NEO's core (python, its models, its voice session) takes
    /// up to ten-odd seconds on a MacBook.
    public static let reconnectGrace: TimeInterval = 15
    /// The states in which NEO is answering: an open panel is held through
    /// them, and a hand-opened hold is spent by them. They do NOT open it.
    public static let answeringStates: Set<NeoState> = [.thinking, .working, .searching, .speaking, .confirming]
    /// The states that open the panel on their own: none. NEO needing an OK
    /// used to (the whole chat came down for two buttons); the island's own
    /// Allow / Cancel show instead.
    public static let openingStates: Set<NeoState> = []

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
    /// When the core went away with the panel open; `nil` once it is back.
    private var disconnectedAt: Date?
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
            // runs once NEO is done). No state opens it on its own.
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

    /// The core went away. The cards and holds go with it; an open panel
    /// stays for `reconnectGrace` so a restart is not a panel folding and
    /// popping back — the page says "reconnecting…" in the meantime.
    public mutating func disconnected(at now: Date) {
        cards = []
        heldByUser = false
        dismissedUntilQuiet = false
        isPinned = false
        state = .idle
        if isOpen, disconnectedAt == nil { disconnectedAt = now }
        settle(at: now)
    }

    /// The core is back: the panel is an ordinary open panel again (and
    /// folds after the quiet delay unless something holds it).
    public mutating func reconnected(at now: Date) {
        disconnectedAt = nil
        settle(at: now)
    }

    /// Whether the panel is open only because the core may still come back.
    public var isWaitingForCore: Bool { isOpen && disconnectedAt != nil }

    /// Applies a due collapse. Returns whether `isOpen` changed since the app
    /// last heard from the model.
    @discardableResult
    public mutating func tick(at now: Date) -> Bool {
        if isOpen, let gone = disconnectedAt, now >= gone.addingTimeInterval(Self.reconnectGrace) {
            isOpen = false
            disconnectedAt = nil
            quietSince = nil
        }
        if isOpen, let since = quietSince, now >= since.addingTimeInterval(Self.idleCollapseDelay) {
            isOpen = false
            quietSince = nil
        }
        defer { lastReported = isOpen }
        return isOpen != lastReported
    }

    /// When the panel will fold on its own, if it will.
    public func nextWake(at now: Date) -> Date? {
        guard isOpen else { return nil }
        let due: Date?
        if let gone = disconnectedAt {
            due = gone.addingTimeInterval(Self.reconnectGrace)
        } else if let since = quietSince {
            due = since.addingTimeInterval(Self.idleCollapseDelay)
        } else {
            due = nil
        }
        guard let due else { return nil }
        return due > now ? due : now
    }

    /// Starts or stops the quiet clock from what holds the panel now. While
    /// the core is away the grace clock runs instead of the quiet one.
    private mutating func settle(at now: Date) {
        if !isOpen { disconnectedAt = nil }
        if !isOpen || isHeld || disconnectedAt != nil {
            quietSince = nil
        } else if quietSince == nil {
            quietSince = now
        }
        lastReported = isOpen
    }
}

/// How big NEO's panel is: compact by default — the chat opened by a click
/// or a confirmation — and bigger only when the page asks for more because
/// its content needs it (a browser card up to most of the screen, the
/// camera or song card a little taller), never beyond the screen's share.
///
/// The numbers were settled against captures of the page in the notch on a
/// 1512×982 pt MacBook screen: at 340×300 the slim header, four or five
/// lines of chat and the input bar fit under the notch without the panel
/// covering the window below; a browser card at 60%×70% leaves the menu
/// bar's ends and the Dock free.
public enum NeoPanelLayout {
    /// The chat's size in CSS points — what NEO's page lays itself out for
    /// when nothing bigger is on it. The panel is this plus the notch strip.
    public static let standard = CGSize(width: 340, height: 300)
    /// The widest and tallest the page may ask for, as fractions of the screen.
    public static let maxWidthFraction: CGFloat = 0.6
    public static let maxWidth: CGFloat = 1000
    public static let maxHeightFraction: CGFloat = 0.7
    public static let maxHeight: CGFloat = 800

    /// The most the page may have on a screen of `screen`.
    public static func maxPageSize(screen: CGSize) -> CGSize {
        CGSize(
            width: max(standard.width, min(screen.width * maxWidthFraction, maxWidth)),
            height: max(standard.height, min(screen.height * maxHeightFraction, maxHeight))
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
