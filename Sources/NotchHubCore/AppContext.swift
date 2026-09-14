import Foundation

// MARK: - Snapshot

/// What NotchHub knows about the frontmost app beyond its identity.
public enum AppContext: Equatable, Sendable {
    /// A browser's front window: its current page and tabs.
    case browser(BrowserContext)
    /// A coding-agent session running in the frontmost terminal, editor or
    /// Claude app.
    case agent(AgentSession)
    /// Any other app: the title of its focused window (the open document,
    /// project, or folder).
    case window(title: String)
}

/// A context, tagged with the app it describes so a stale reading is never
/// shown for a different app.
public struct AppContextSnapshot: Equatable, Sendable {
    public var bundleID: String
    public var context: AppContext

    public init(bundleID: String, context: AppContext) {
        self.bundleID = bundleID
        self.context = context
    }
}

// MARK: - Browser

public struct BrowserTab: Equatable, Sendable {
    /// 1-based, the way browser scripting counts tabs.
    public var index: Int
    public var title: String
    public var host: String?

    public init(index: Int, title: String, host: String?) {
        self.index = index
        self.title = title
        self.host = host
    }
}

public struct BrowserContext: Equatable, Sendable {
    public var title: String
    public var host: String?
    public var tabs: [BrowserTab]
    /// The active tab's index, when it could be matched.
    public var activeIndex: Int?

    public var tabCount: Int { tabs.count }

    public init(title: String, host: String?, tabs: [BrowserTab], activeIndex: Int?) {
        self.title = title
        self.host = host
        self.tabs = tabs
        self.activeIndex = activeIndex
    }

    /// Builds a context from the lists a browser script returns.
    public static func from(activeTitle: String, activeURL: String, titles: [String], urls: [String]) -> BrowserContext {
        let count = min(titles.count, urls.count)
        let tabs = (0..<count).map { i in
            BrowserTab(index: i + 1, title: titles[i], host: host(of: urls[i]))
        }
        let active = (0..<count).first { urls[$0] == activeURL }.map { $0 + 1 }
        return BrowserContext(title: activeTitle, host: host(of: activeURL), tabs: tabs, activeIndex: active)
    }

    /// Up to `limit` tabs around the active one (active included), in order —
    /// the panel's tab row.
    public func nearbyTabs(limit: Int = 3) -> [BrowserTab] {
        guard tabs.count > limit else { return tabs }
        let active = (activeIndex ?? 1) - 1
        let start = max(0, min(active - limit / 2, tabs.count - limit))
        return Array(tabs[start..<(start + limit)])
    }

    /// "google.com" for "https://www.google.com/search?q=…".
    public static func host(of urlString: String) -> String? {
        guard let host = URL(string: urlString)?.host?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

// MARK: - Agent session

public struct AgentSession: Equatable, Sendable {
    /// "Claude Code".
    public var tool: String
    /// Display name, e.g. "Opus 5".
    public var model: String?
    /// The session's title, or the last prompt when it has none.
    public var title: String?
    /// The working directory's folder name.
    public var project: String?
    public var isWorking: Bool
    /// Tokens processed in the session (input + cache writes + output).
    public var tokens: Int
    /// Prompts the user has sent.
    public var turns: Int
    public var startedAt: Date?
    public var lastActivity: Date?
    /// The size of the latest request's context.
    public var contextTokens: Int?
    public var contextLimit: Int
    /// Plan usage windows, when the tool records them locally (Codex does;
    /// Claude Code does not).
    public var limits: [AgentLimit] = []

    public init(
        tool: String,
        model: String?,
        title: String?,
        project: String?,
        isWorking: Bool,
        tokens: Int,
        turns: Int,
        startedAt: Date?,
        lastActivity: Date?,
        contextTokens: Int?,
        contextLimit: Int
    ) {
        self.tool = tool
        self.model = model
        self.title = title
        self.project = project
        self.isWorking = isWorking
        self.tokens = tokens
        self.turns = turns
        self.startedAt = startedAt
        self.lastActivity = lastActivity
        self.contextTokens = contextTokens
        self.contextLimit = contextLimit
    }

    /// 0…1 share of the context window in use.
    public var contextFraction: Double? {
        contextTokens.map { min(1, Double($0) / Double(max(1, contextLimit))) }
    }
}

public enum AgentFormat {

    /// "812", "19.7k", "1.2M".
    public static func tokens(_ count: Int) -> String {
        if count < 1_000 { return "\(count)" }
        if count < 1_000_000 { return String(format: "%.1fk", Double(count) / 1_000) }
        return String(format: "%.1fM", Double(count) / 1_000_000)
    }

    /// "claude-opus-5" → "Opus 5", "claude-sonnet-4-5-20250929" → "Sonnet 4.5",
    /// "claude-3-5-haiku-20241022" → "Haiku 3.5". `nil` for placeholders.
    public static func modelName(_ id: String) -> String? {
        var raw = id.lowercased()
        guard !raw.hasPrefix("<") else { return nil }
        if let bracket = raw.firstIndex(of: "[") { raw = String(raw[..<bracket]) }
        if raw.hasPrefix("claude-") { raw.removeFirst("claude-".count) }
        let parts = raw.split(separator: "-").map(String.init)
            .filter { !($0.count == 8 && $0.allSatisfy(\.isNumber)) }
        guard let family = parts.first(where: { !$0.allSatisfy(\.isNumber) }) else { return nil }
        let version = parts.filter { $0.allSatisfy(\.isNumber) }.joined(separator: ".")
        let name = family.prefix(1).uppercased() + family.dropFirst()
        return version.isEmpty ? name : "\(name) \(version)"
    }
}

/// Reads a Claude Code session transcript (`~/.claude/projects/*/*.jsonl`),
/// one line at a time, so a long session can be followed incrementally.
public struct ClaudeSessionParser {

    public private(set) var modelID: String?
    public private(set) var customTitle: String?
    public private(set) var lastPrompt: String?
    public private(set) var cwd: String?
    public private(set) var turns = 0
    public private(set) var startedAt: Date?
    public private(set) var lastActivity: Date?
    public private(set) var contextTokens: Int?
    /// True while the latest main-thread entry leaves the agent mid-task: a
    /// prompt or tool result waiting on the model, or a reply that asked for a
    /// tool. False once a reply ends its turn.
    public private(set) var awaitingModel = false
    /// Tokens per API message. A message is written once per content block,
    /// each line repeating its usage, so it is keyed by message id.
    private var usageByMessage: [String: Int] = [:]

    public init() {}

    public var tokens: Int { usageByMessage.values.reduce(0, +) }

    public mutating func consume(_ line: Data) {
        guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { return }
        if let cwd = object["cwd"] as? String { self.cwd = cwd }
        if let stamp = object["timestamp"] as? String, let date = Self.date(from: stamp) {
            if startedAt == nil { startedAt = date }
            lastActivity = max(lastActivity ?? date, date)
        }
        let isSidechain = (object["isSidechain"] as? Bool) == true

        switch object["type"] as? String {
        case "custom-title":
            customTitle = Self.clean(object["customTitle"] as? String)
        case "last-prompt":
            lastPrompt = Self.clean(object["lastPrompt"] as? String)
        case "user":
            guard (object["isMeta"] as? Bool) != true, !isSidechain else { return }
            if object["promptSource"] != nil { turns += 1 }
            awaitingModel = true
        case "assistant":
            guard let message = object["message"] as? [String: Any] else { return }
            if let usage = message["usage"] as? [String: Any] {
                let input = Self.int(usage["input_tokens"])
                let written = Self.int(usage["cache_creation_input_tokens"])
                let read = Self.int(usage["cache_read_input_tokens"])
                let output = Self.int(usage["output_tokens"])
                let id = (message["id"] as? String) ?? UUID().uuidString
                usageByMessage[id] = input + written + output
                if !isSidechain { contextTokens = input + written + read }
            }
            guard !isSidechain else { return }
            if let model = message["model"] as? String, !model.hasPrefix("<") { modelID = model }
            awaitingModel = (message["stop_reason"] as? String) != "end_turn"
        default:
            break
        }
    }

    /// The session as the island shows it. It reads as working only while
    /// awaiting the model AND recently active, so an abandoned session does
    /// not claim to be working forever.
    public func session(now: Date, workingWindow: TimeInterval = 120) -> AgentSession {
        let recent = lastActivity.map { now.timeIntervalSince($0) < workingWindow } ?? false
        let large = (modelID?.contains("[1m]") ?? false) || (contextTokens ?? 0) > 200_000
        return AgentSession(
            tool: "Claude Code",
            model: modelID.flatMap(AgentFormat.modelName),
            title: customTitle ?? lastPrompt,
            project: cwd.map { URL(fileURLWithPath: $0).lastPathComponent },
            isWorking: awaitingModel && recent,
            tokens: tokens,
            turns: turns,
            startedAt: startedAt,
            lastActivity: lastActivity,
            contextTokens: contextTokens,
            contextLimit: large ? 1_000_000 : 200_000
        )
    }

    private static func int(_ value: Any?) -> Int {
        (value as? NSNumber)?.intValue ?? 0
    }

    /// First line, trimmed and clipped.
    private static func clean(_ text: String?) -> String? {
        guard let line = text?
            .split(whereSeparator: \.isNewline)
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { !$0.isEmpty }) else { return nil }
        return line.count > 160 ? String(line.prefix(160)) + "…" : line
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let iso = ISO8601DateFormatter()

    static func date(from stamp: String) -> Date? {
        isoFractional.date(from: stamp) ?? iso.date(from: stamp)
    }
}

// MARK: - Strip labels

/// Short, glanceable labels for the hover strip.
public enum AppStripLabel {

    /// A window title made glanceable: the app's own name removed
    /// ("Report.pdf — Preview" → "Report.pdf"), a web address reduced to its
    /// site, a file path to its file name. `nil` when nothing useful is left
    /// (an empty title, or just the app's name).
    public static func windowTitle(_ title: String, appName: String?) -> String? {
        var text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let appName, !appName.isEmpty {
            for separator in [" — ", " – ", " - ", " | ", ": "] {
                if text.hasSuffix(separator + appName) {
                    text.removeLast((separator + appName).count)
                }
                if text.hasPrefix(appName + separator) {
                    text.removeFirst((appName + separator).count)
                }
            }
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let host = BrowserContext.host(of: text), text.lowercased().hasPrefix("http") {
            text = host
        } else if text.hasPrefix("/") || text.hasPrefix("~/") {
            text = (text as NSString).lastPathComponent
        }
        guard !text.isEmpty, text.caseInsensitiveCompare(appName ?? "") != .orderedSame else { return nil }
        return text
    }
}

