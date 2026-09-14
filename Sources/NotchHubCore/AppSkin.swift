import Foundation

/// The frontmost app, dressed for the island.
///
/// NotchBay's "app skins": whichever app is in front takes over the island —
/// its identity on the left, its live state on the right. This is the neutral
/// model; the system layer fills it in.
public struct AppSkin: Equatable {
    /// The bundle identifier of the frontmost app.
    public let bundleID: String
    /// Display name, e.g. "Google Chrome".
    public var name: String
    /// SF Symbol standing in for the app's icon.
    public var symbol: String
    /// The app's real icon as PNG data, resolved from `NSWorkspace` by the
    /// system layer. `nil` when it could not be resolved, in which case the
    /// view falls back to `symbol`.
    public var iconData: Data?
    /// The app's live state, e.g. "12 tabs", "working", "2 errors".
    public var state: String?
    /// The longer line under it, e.g. the page title or the session summary.
    public var detail: String?

    public init(
        bundleID: String,
        name: String,
        symbol: String,
        iconData: Data? = nil,
        state: String? = nil,
        detail: String? = nil
    ) {
        self.bundleID = bundleID
        self.name = name
        self.symbol = symbol
        self.iconData = iconData
        self.state = state
        self.detail = detail
    }
}

/// Which apps are worth dressing the island for, and how they look.
///
/// Data, not logic — the system layer reads the frontmost app and asks this
/// table whether it has a skin.
public enum AppSkinRegistry {

    /// A known app's presentation.
    public struct Entry: Equatable {
        public let name: String
        public let symbol: String
        public let category: Category

        public enum Category: Equatable {
            /// Browsers: the current tab becomes the island's state.
            case browser
            /// AI coding tools: session state and token burn.
            case aiTool
            /// Everything else: identity only.
            case plain
        }
    }

    /// Bundle identifier → skin. Browsers and AI tools get live state; the
    /// rest are identity-only, which is the common case.
    public static let table: [String: Entry] = [
        // Browsers — current tab drives the state line.
        "com.google.Chrome": Entry(name: "Chrome", symbol: "globe", category: .browser),
        "com.apple.Safari": Entry(name: "Safari", symbol: "safari.fill", category: .browser),
        "company.thebrowser.Browser": Entry(name: "Arc", symbol: "globe.americas.fill", category: .browser),
        "com.brave.Browser": Entry(name: "Brave", symbol: "shield.lefthalf.filled", category: .browser),
        "ai.perplexity.comet": Entry(name: "Comet", symbol: "globe.badge.chevron.backward", category: .browser),
        "com.microsoft.edgemac": Entry(name: "Edge", symbol: "globe", category: .browser),
        "org.mozilla.firefox": Entry(name: "Firefox", symbol: "flame.fill", category: .browser),

        // AI coding tools — session, tokens, elapsed.
        "com.anthropic.claudefordesktop": Entry(name: "Claude", symbol: "sparkle", category: .aiTool),
        "com.openai.chat": Entry(name: "ChatGPT", symbol: "bubble.left.and.bubble.right.fill", category: .aiTool),
        "com.todesktop.230313mzl4w4u92": Entry(name: "Cursor", symbol: "cursorarrow.rays", category: .aiTool),
        "com.microsoft.VSCode": Entry(name: "Code", symbol: "chevron.left.forwardslash.chevron.right", category: .aiTool),

        // Everything else — identity only.
        "com.apple.finder": Entry(name: "Finder", symbol: "folder.fill", category: .plain),
        "com.apple.Terminal": Entry(name: "Terminal", symbol: "terminal.fill", category: .plain),
        "com.googlecode.iterm2": Entry(name: "iTerm", symbol: "terminal.fill", category: .plain),
        "dev.warp.Warp-Stable": Entry(name: "Warp", symbol: "terminal.fill", category: .plain),
        "com.apple.dt.Xcode": Entry(name: "Xcode", symbol: "hammer.fill", category: .plain),
        "com.figma.Desktop": Entry(name: "Figma", symbol: "square.on.circle", category: .plain),
        "com.tinyspeck.slackmacgap": Entry(name: "Slack", symbol: "number.square.fill", category: .plain),
        "com.apple.mail": Entry(name: "Mail", symbol: "envelope.fill", category: .plain),
        "com.apple.Music": Entry(name: "Music", symbol: "music.note", category: .plain),
        "com.spotify.client": Entry(name: "Spotify", symbol: "music.note", category: .plain),
        "com.apple.iCal": Entry(name: "Calendar", symbol: "calendar", category: .plain),
        "com.apple.Notes": Entry(name: "Notes", symbol: "note.text", category: .plain),
        "com.apple.Photos": Entry(name: "Photos", symbol: "photo.fill", category: .plain),
        "com.hnc.Discord": Entry(name: "Discord", symbol: "bubble.left.fill", category: .plain),
        "com.apple.systempreferences": Entry(name: "Settings", symbol: "gearshape.fill", category: .plain),
        "com.apple.ActivityMonitor": Entry(name: "Activity Monitor", symbol: "waveform.path.ecg", category: .plain),
    ]

    /// The entry for a bundle id, if it is worth skinning.
    public static func entry(for bundleID: String) -> Entry? {
        table[bundleID]
    }

    /// Whether this app gets a skin at all.
    public static func isSkinnable(_ bundleID: String) -> Bool {
        table[bundleID] != nil
    }

    /// Whether the frontmost app's state should come from its current tab.
    public static func isBrowser(_ bundleID: String) -> Bool {
        table[bundleID]?.category == .browser
    }

    /// Apps a coding agent runs in: terminals, editors, and the Claude app.
    /// When one is in front and a session is active, the island shows it.
    public static let agentHosts: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable",
        "com.mitchellh.ghostty", "net.kovidgoyal.kitty", "org.alacritty",
        "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "dev.zed.Zed",
        "com.exafunction.windsurf", "com.anthropic.claudefordesktop",
        "com.openai.codex", "ai.foxora.desktop",
    ]

    public static func isAgentHost(_ bundleID: String) -> Bool {
        agentHosts.contains(bundleID)
    }

    /// Whether the frontmost app reports session state (tokens, turns).
    public static func isAITool(_ bundleID: String) -> Bool {
        table[bundleID]?.category == .aiTool
    }
}
