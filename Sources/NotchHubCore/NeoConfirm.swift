import CoreGraphics
import Foundation

/// A confirmation NEO is waiting on: the core's `confirm` event (and the
/// `confirm` object of its `hello`, for a question still pending when
/// NotchHub connects). The island shows none of its words — only Allow and
/// Cancel — but it keeps them: the summary is what assistive technology
/// reads, and the action id is what an answer must name.
public struct NeoConfirmCard: Equatable, Sendable {
    /// The id the core gave this staging; an answer naming any other id
    /// approves nothing.
    public var actionID: String
    /// The tool that asked ("trash", "shell" …).
    public var tool: String
    /// The action in plain words ("move report.pdf to the Trash").
    public var summary: String
    /// Exactly what would run (a path, a command). Never drawn.
    public var detail: String

    public init(actionID: String, tool: String = "", summary: String = "", detail: String = "") {
        self.actionID = actionID
        self.tool = tool
        self.summary = summary
        self.detail = detail
    }

    /// From the core's JSON object. `nil` without an action id: there would
    /// be nothing an answer could name.
    public init?(payload: [String: Any]) {
        guard let id = payload["action_id"] as? String, !id.isEmpty else { return nil }
        actionID = String(id.prefix(Self.maxID))
        tool = String((payload["tool"] as? String ?? "").prefix(64))
        summary = Self.plain(payload["summary"] as? String ?? "", limit: Self.maxSummary)
        detail = Self.plain(payload["detail"] as? String ?? "", limit: Self.maxDetail)
    }

    static let maxID = 200
    static let maxSummary = 200
    static let maxDetail = 400

    /// One line of plain text: whitespace runs (a script's newlines) become
    /// single spaces, and it is cut at `limit` characters.
    static func plain(_ text: String, limit: Int) -> String {
        let line = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        return line.count > limit ? String(line.prefix(limit - 1)) + "…" : line
    }

    /// What assistive technology is told when the buttons come up, and the
    /// surface's own label: "Neo needs your OK: move report.pdf to the Trash".
    public var announcement: String {
        summary.isEmpty ? "Neo needs your OK" : "Neo needs your OK: \(summary)"
    }
}

/// One of the two buttons.
public enum NeoConfirmChoice: String, Equatable, Sendable, CaseIterable {
    case allow
    case cancel

    /// The button's title, and its accessibility label.
    public var title: String {
        switch self {
        case .allow: return "Allow"
        case .cancel: return "Cancel"
        }
    }
}

/// The answer to a card, as it goes to NEO's core — the very command NEO's
/// own page sends from its card's buttons (`ui/src/App.tsx`):
/// `{"cmd":"confirm","yes":true,"action_id":"…"}`.
public struct NeoConfirmAnswer: Equatable, Sendable {
    public var actionID: String
    public var yes: Bool

    public init(actionID: String, yes: Bool) {
        self.actionID = actionID
        self.yes = yes
    }

    /// The command, as one line of JSON. The id is JSON-encoded, so nothing
    /// in it can break out of its string.
    public var command: String {
        let encoded = (try? JSONSerialization.data(withJSONObject: [actionID]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        let id = encoded.dropFirst().dropLast()
        return #"{"cmd":"confirm","yes":\#(yes),"action_id":\#(id)}"#
    }
}

/// Whether the island shows NEO's Allow / Cancel, and what an answer does.
///
/// Pure and clock-driven like NEO's other models. The rules:
///
/// - A card arriving (`confirm`, or the `hello`'s) brings the buttons up; a
///   newer card replaces the one showing, and its guard starts afresh.
/// - They stay until the card is answered here, or the core says it is done
///   (`confirm_done`: answered elsewhere — by voice, in NEO's page — or
///   expired), or the core goes away.
/// - While NEO's chat panel is open the page shows its own card, so the
///   buttons are not drawn twice; when the panel closes with the card still
///   pending they come up then.
/// - **Allow** counts only once the buttons have been up `allowGuard`
///   (0.6 s), by click or by Return: buttons that appear under a click or a
///   keystroke meant for something else approve nothing. **Cancel** always
///   counts.
/// - An answer hides the buttons at once (the core confirms a moment later);
///   the island is then whatever it was underneath — the buttons are drawn
///   over the island's own state, never in place of it.
/// - NEO's page asks its host to show it whenever a question comes up on its
///   card. That request no longer opens the chat for a confirmation: while a
///   card waits it is declined, and a panel the page had opened a moment
///   before the card reached the island folds again — the two arrive over
///   separate sockets, in either order. A panel the USER opened stays.
public struct NeoConfirmModel: Equatable, Sendable {
    /// How long the buttons must have been up before Allow counts.
    public static let allowGuard: TimeInterval = 0.6
    /// How long after the page asked to be seen a card arriving still counts
    /// as what it asked for.
    public static let pageShowWindow: TimeInterval = 1.5

    /// The card waiting, if one is.
    public private(set) var card: NeoConfirmCard?
    /// When the buttons came up for it; `nil` while they are not drawn.
    public private(set) var shownAt: Date?
    /// NEO's chat panel is open: the page shows the card itself.
    public private(set) var chatOpen = false
    /// When the page last got the chat opened by asking; `nil` once the user
    /// opened it by hand.
    private var pageShowAt: Date?

    public init() {}

    /// Whether the buttons are on the island now.
    public var isShowing: Bool { card != nil && !chatOpen }

    /// Takes one fact from the core. Returns whether what the island shows
    /// changed.
    @discardableResult
    public mutating func receive(_ fact: NeoFact, at now: Date) -> Bool {
        let before = (card, isShowing)
        switch fact {
        case let .confirm(next):
            if next.actionID != card?.actionID {
                card = next
                shownAt = chatOpen ? nil : now // a newer question: its guard starts now
            } else {
                card = next // the same card, told again (a reconnect's hello)
            }
        case let .confirmDone(id):
            if card?.actionID == id { clear() }
        case .connected(false):
            clear() // nobody is there to take an answer
        case .connected(true), .state, .transcript, .note, .error, .card, .songCard, .cameraCard, .cameraFrame, .woke:
            break
        }
        return before.0 != card || before.1 != isShowing
    }

    /// NEO's chat panel opened or closed. Returns whether the buttons came
    /// up or went away for it.
    @discardableResult
    public mutating func chat(open: Bool, at now: Date) -> Bool {
        guard open != chatOpen else { return false }
        let before = isShowing
        chatOpen = open
        shownAt = isShowing ? now : nil
        return before != isShowing
    }

    /// NEO's page asked to be seen. Returns whether the chat may open for
    /// it: not while a card waits behind the island's own buttons.
    public mutating func pageAsksToShow(at now: Date) -> Bool {
        guard !isShowing else { return false }
        pageShowAt = now
        return true
    }

    /// The user opened the chat by hand (a click on the island, the hotkey):
    /// whatever arrives next, that panel is theirs and stays.
    public mutating func userOpenedChat() {
        pageShowAt = nil
    }

    /// Whether the chat panel should fold for `fact`: a card arriving just
    /// after the page got the panel opened for that very card.
    public func foldsChat(for fact: NeoFact, at now: Date) -> Bool {
        guard case .confirm = fact, chatOpen, let pageShowAt else { return false }
        return now.timeIntervalSince(pageShowAt) <= Self.pageShowWindow
    }

    /// Whether Allow counts yet.
    public func mayAllow(at now: Date) -> Bool {
        guard isShowing, let shownAt else { return false }
        return now.timeIntervalSince(shownAt) >= Self.allowGuard
    }

    /// The user chose: the command to send, or `nil` when nothing is showing
    /// or Allow came before its guard. The buttons go at once.
    public mutating func answer(_ choice: NeoConfirmChoice, at now: Date) -> NeoConfirmAnswer? {
        guard isShowing, let card else { return nil }
        if choice == .allow, !mayAllow(at: now) { return nil }
        clear()
        return NeoConfirmAnswer(actionID: card.actionID, yes: choice == .allow)
    }

    /// The shape the island takes: the buttons while they show — over
    /// activities, the idle island and every panel but NEO's own chat —
    /// else exactly the shape underneath.
    public func state(over underlying: IslandState) -> IslandState {
        isShowing && underlying != .neoPanel ? .neoConfirm : underlying
    }

    private mutating func clear() {
        card = nil
        shownAt = nil
    }
}

/// What a key does while the buttons have the keyboard.
public enum NeoConfirmKey {
    public static let returnKey: UInt16 = 36
    public static let enterKey: UInt16 = 76
    public static let escapeKey: UInt16 = 53

    /// Whether the key is one of the buttons' (and so goes no further while
    /// they have the keyboard, even when it does nothing).
    public static func handles(keyCode code: UInt16) -> Bool {
        code == returnKey || code == enterKey || code == escapeKey
    }

    /// Return or Enter allow, Esc cancels; any other key is not the buttons'.
    /// A key held down from before (an auto-repeat) is nobody's choice: a
    /// Return still repeating from whatever the user was typing must not
    /// become an Allow once the guard has passed.
    public static func choice(forKeyCode code: UInt16, isRepeat: Bool = false) -> NeoConfirmChoice? {
        guard !isRepeat else { return nil }
        switch code {
        case returnKey, enterKey: return .allow
        case escapeKey: return .cancel
        default: return nil
        }
    }
}

/// The geometry of NEO's Allow / Cancel under the notch.
///
/// The island drops just far enough for one row of two buttons. It is the
/// notch's width plus the fox's dock on either side, so the fox — in its "!"
/// pose — stays exactly where it stands on the idle dock while the buttons
/// come out beneath it. `NeoConfirmView` draws the buttons from these numbers
/// and the window hit-tests clicks against them: the island takes no key
/// focus for them, so a button cannot draw in one place and take clicks in
/// another.
public enum NeoConfirmLayout {
    /// How far the surface reaches beyond the notch on each side: the pet's
    /// idle dock.
    public static var sideReach: CGFloat { PetLayout.idleDock }
    /// The row under the notch strip.
    public static let rowHeight: CGFloat = 40
    /// Each button's height.
    public static let buttonHeight: CGFloat = 26
    /// From the notch strip down to the buttons.
    public static let topGap: CGFloat = 4
    /// From the surface's sides to the buttons.
    public static let horizontalInset: CGFloat = 12
    /// Between the two buttons.
    public static let spacing: CGFloat = 8
    /// The surface's bottom corners: concentric with the capsules inside.
    public static let cornerRadius: CGFloat = 22
    /// The buttons, left to right — the order of NEO's own card.
    public static let order: [NeoConfirmChoice] = [.allow, .cancel]

    /// The surface's size for a notch of `notch`.
    public static func size(notch: CGSize) -> CGSize {
        CGSize(width: notch.width + sideReach * 2, height: notch.height + rowHeight)
    }

    /// The buttons for a surface frame in AppKit coordinates (origin
    /// bottom-left). The row starts below the notch cutout, which takes the
    /// top `notchInset` points.
    public static func buttons(in frame: CGRect, notchInset: CGFloat) -> [(choice: NeoConfirmChoice, rect: CGRect)] {
        let width = max(0, (frame.width - horizontalInset * 2 - spacing * CGFloat(order.count - 1)) / CGFloat(order.count))
        let y = frame.maxY - notchInset - topGap - buttonHeight
        return order.enumerated().map { index, choice in
            (choice, CGRect(x: frame.minX + horizontalInset + (width + spacing) * CGFloat(index), y: y, width: width, height: buttonHeight))
        }
    }

    /// The button under a point, or `nil` for a miss. Two points of slop, as
    /// with the island's other drawn controls (less than half the gap, so
    /// the two never overlap).
    public static func choice(at point: CGPoint, in frame: CGRect, notchInset: CGFloat) -> NeoConfirmChoice? {
        buttons(in: frame, notchInset: notchInset)
            .first { $0.rect.insetBy(dx: -2, dy: -2).contains(point) }?
            .choice
    }
}

/// Where the island catches the mouse, and whether its window must take
/// mouse events for where the cursor is.
///
/// The window is a transparent envelope that lets every click through unless
/// the cursor is on the island. That used to be decided from the last HOVER
/// the window had heard of — so a surface that came up under a cursor that
/// was not moving (NEO's buttons, its panel) was still "not hovered", the
/// window still ignored the mouse, and the first click went to whatever was
/// underneath. It is decided from the island's frame and the cursor's real
/// position instead: the hit region is the surface's final frame from the
/// moment it is presented, spring or no spring.
public struct IslandHitRegion: Equatable, Sendable {
    /// The island's frame (window coordinates) — its FINAL frame: what it is
    /// springing to, not where the animation has got to.
    public var islandFrame: CGRect
    /// The notch itself: where the cursor opens the island while it is idle.
    public var idleNotchFrame: CGRect
    /// While idle, the pet's own rectangle.
    public var idlePetFrame: CGRect?
    public var isIdle: Bool

    /// A little slop around the island so a small pill is easy to catch.
    public static let slop: CGFloat = 8
    public static let petSlop: CGFloat = 3

    public init(islandFrame: CGRect, idleNotchFrame: CGRect, idlePetFrame: CGRect? = nil, isIdle: Bool) {
        self.islandFrame = islandFrame
        self.idleNotchFrame = idleNotchFrame
        self.idlePetFrame = idlePetFrame
        self.isIdle = isIdle
    }

    /// Where the cursor opens the island: the notch while idle (not the
    /// pet's dock), otherwise the island's whole frame.
    public var hoverRegion: CGRect {
        (isIdle ? idleNotchFrame : islandFrame).insetBy(dx: -Self.slop, dy: -Self.slop)
    }

    public func isOverIdlePet(_ point: CGPoint) -> Bool {
        isIdle && (idlePetFrame?.insetBy(dx: -Self.petSlop, dy: -Self.petSlop).contains(point) ?? false)
    }

    /// Whether the mouse at `point` belongs to the island (hover or click).
    public func catchesMouse(at point: CGPoint) -> Bool {
        hoverRegion.contains(point) || isOverIdlePet(point)
    }

    /// Whether the cursor at `point` opens the island. Pointing at the
    /// resting pet does not — the pet notices it instead.
    public func opensIsland(at point: CGPoint) -> Bool {
        hoverRegion.contains(point) && !isOverIdlePet(point)
    }

    /// Whether the window must ignore the mouse with the cursor at `point`:
    /// only where the island does not catch it. `interactive`: a panel with
    /// real controls holds the window key, and it never ignores the mouse.
    public func windowIgnoresMouse(cursorAt point: CGPoint, interactive: Bool) -> Bool {
        !interactive && !catchesMouse(at: point)
    }
}
