import Foundation

/// How a wing glyph is tinted.
///
/// The wings are a glance, not a dashboard: almost everything is plain white,
/// and colour is reserved for the few states that genuinely want attention.
public enum WingTint: String, Equatable, Sendable {
    /// Ordinary white — the default.
    case normal
    /// The island's accent, for something live and good (music playing).
    case accent
    /// Amber, for something that wants a look (low battery).
    case warning
    /// Red, for something recording or on air.
    case live
}

/// One glyph in a wing.
///
/// A wing item is either a real app icon (`iconData`, a PNG the app layer
/// resolved from `NSWorkspace`) or an SF Symbol (`symbol`). The icon wins when
/// both are present, so a frontmost app shows its true icon rather than a
/// stand-in.
public struct WingItem: Equatable, Sendable {
    /// SF Symbol name — the fallback, and the whole story for status glyphs.
    public var symbol: String
    /// A real app icon as PNG data, when the item stands for an app.
    public var iconData: Data?
    /// A short label for the item, e.g. "82%" or the app's name.
    public var label: String?
    /// How the glyph is tinted.
    public var tint: WingTint

    public init(
        symbol: String,
        iconData: Data? = nil,
        label: String? = nil,
        tint: WingTint = .normal
    ) {
        self.symbol = symbol
        self.iconData = iconData
        self.label = label
        self.tint = tint
    }
}

/// The frontmost app's own hover strip: its name on the left wing, and
/// app-specific content on the right in place of the generic status glyphs.
public struct AppStrip: Equatable, Sendable {
    public enum Trailing: Equatable, Sendable {
        /// The usual live-status glyphs.
        case status
        /// Back, forward, new tab (`WingControlLayout`).
        case browserControls
        /// A coding agent's token count and whether it is working.
        case agent(tokens: String, isWorking: Bool)
    }

    /// The app's name, the page's site, the agent's model, or a window title.
    public var label: String
    public var trailing: Trailing

    public init(label: String, trailing: Trailing) {
        self.label = label
        self.trailing = trailing
    }
}

/// What the two wings show while the island is in its sideways peek.
///
/// The left wing is the frontmost app's identity — its real icon, the way
/// NotchBay dresses the island for whatever you are in. The right wing is live
/// status: charging, music, Wi-Fi, the weather — the small facts worth a glance
/// without opening anything.
public struct WingStatus: Equatable, Sendable {
    /// The left wing: the frontmost app, or `nil` when there is nothing to show.
    public var left: WingItem?
    /// The right wing: live status glyphs, in the order they should read.
    public var right: [WingItem]
    /// Whether music is playing right now. When true, the right wing shows a
    /// live audio visualizer instead of (or alongside) the static music glyph —
    /// a glanceable "something is playing" signal.
    public var musicPlaying: Bool
    /// The frontmost app's strip, when it has more to say than its icon.
    public var strip: AppStrip?

    public init(left: WingItem? = nil, right: [WingItem] = [], musicPlaying: Bool = false, strip: AppStrip? = nil) {
        self.left = left
        self.right = right
        self.musicPlaying = musicPlaying
        self.strip = strip
    }

    /// Whether there is anything at all to show. An empty status still opens
    /// the wings (the peek is the point), but the view can use this to decide
    /// whether to draw a resting face instead.
    public var isEmpty: Bool { left == nil && right.isEmpty }
}
