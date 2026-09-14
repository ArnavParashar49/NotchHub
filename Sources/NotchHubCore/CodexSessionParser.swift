import Foundation

/// A usage limit an agent's plan reports (Codex's 5-hour and weekly windows).
public struct AgentLimit: Equatable, Sendable {
    /// "5-hour limit", "Weekly limit".
    public var label: String
    /// 0…100.
    public var usedPercent: Double
    public var resetsAt: Date?

    public init(label: String, usedPercent: Double, resetsAt: Date?) {
        self.label = label
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }

    /// "5-hour limit" for 300 minutes, "Weekly limit" for 10080.
    public static func label(windowMinutes: Int?) -> String {
        guard let minutes = windowMinutes, minutes > 0 else { return "Limit" }
        if minutes % 10_080 == 0 { return minutes == 10_080 ? "Weekly limit" : "\(minutes / 10_080)-week limit" }
        if minutes % 1_440 == 0 { return "\(minutes / 1_440)-day limit" }
        if minutes % 60 == 0 { return "\(minutes / 60)-hour limit" }
        return "\(minutes)-minute limit"
    }
}

/// Reads a Codex session log (`$CODEX_HOME/sessions/YYYY/MM/DD/rollout-*.jsonl`,
/// written by the Codex CLI and the Codex app), one line at a time.
///
/// Each line is `{"timestamp", "type", "payload"}`: `session_meta` (cwd),
/// `turn_context` (model), `event_msg` (user_message, agent_message,
/// token_count with usage and plan rate limits, task_started / task_complete)
/// and `response_item` (messages, tool calls). Unknown lines are ignored, so a
/// newer format degrades to fewer details rather than failing.
public struct CodexSessionParser {

    public private(set) var modelID: String?
    public private(set) var cwd: String?
    public private(set) var lastPrompt: String?
    public private(set) var turns = 0
    public private(set) var totalTokens = 0
    public private(set) var contextTokens: Int?
    public private(set) var contextWindow: Int?
    public private(set) var limits: [AgentLimit] = []
    public private(set) var startedAt: Date?
    public private(set) var lastActivity: Date?
    public private(set) var awaitingModel = false

    public init() {}

    public mutating func consume(_ line: Data) {
        guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { return }
        var stamp: Date?
        if let text = object["timestamp"] as? String, let date = ClaudeSessionParser.date(from: text) {
            stamp = date
            if startedAt == nil { startedAt = date }
            lastActivity = max(lastActivity ?? date, date)
        }
        let payload = object["payload"] as? [String: Any] ?? [:]

        switch object["type"] as? String {
        case "session_meta":
            if let cwd = payload["cwd"] as? String { self.cwd = cwd }
        case "turn_context":
            if let cwd = payload["cwd"] as? String { self.cwd = cwd }
            if let model = payload["model"] as? String { modelID = model }
        case "event_msg":
            consumeEvent(payload, at: stamp)
        case "response_item":
            switch payload["type"] as? String {
            case "function_call", "function_call_output", "custom_tool_call", "custom_tool_call_output", "reasoning", "local_shell_call":
                awaitingModel = true
            default:
                break
            }
        default:
            break
        }
    }

    private mutating func consumeEvent(_ payload: [String: Any], at stamp: Date?) {
        switch payload["type"] as? String {
        case "user_message":
            turns += 1
            awaitingModel = true
            if let message = payload["message"] as? String {
                lastPrompt = Self.firstLine(message)
            }
        case "task_started":
            awaitingModel = true
        case "task_complete", "turn_aborted":
            awaitingModel = false
        case "agent_message":
            // Interim commentary also arrives as agent messages; only a
            // completed task ends the turn, but without task events the last
            // agent message is the best signal.
            break
        case "token_count":
            if let info = payload["info"] as? [String: Any] {
                if let total = info["total_token_usage"] as? [String: Any] {
                    totalTokens = Self.int(total["total_tokens"])
                }
                if let last = info["last_token_usage"] as? [String: Any] {
                    contextTokens = Self.int(last["total_tokens"])
                }
                if let window = info["model_context_window"] as? NSNumber {
                    contextWindow = window.intValue
                }
            }
            if let rates = payload["rate_limits"] as? [String: Any] {
                limits = ["primary", "secondary"].compactMap { key in
                    guard let window = rates[key] as? [String: Any],
                          let used = window["used_percent"] as? NSNumber else { return nil }
                    var resets: Date?
                    if let at = window["resets_at"] as? NSNumber {
                        resets = Date(timeIntervalSince1970: at.doubleValue)
                    } else if let seconds = window["resets_in_seconds"] as? NSNumber, let stamp {
                        resets = stamp.addingTimeInterval(seconds.doubleValue)
                    }
                    return AgentLimit(
                        label: AgentLimit.label(windowMinutes: (window["window_minutes"] as? NSNumber)?.intValue),
                        usedPercent: used.doubleValue,
                        resetsAt: resets
                    )
                }
            }
        default:
            break
        }
    }

    public func session(now: Date, workingWindow: TimeInterval = 120) -> AgentSession {
        let recent = lastActivity.map { now.timeIntervalSince($0) < workingWindow } ?? false
        var session = AgentSession(
            tool: "Codex",
            model: modelID.map(AgentFormat.codexModelName),
            title: lastPrompt,
            project: cwd.map { URL(fileURLWithPath: $0).lastPathComponent },
            isWorking: awaitingModel && recent,
            tokens: totalTokens,
            turns: turns,
            startedAt: startedAt,
            lastActivity: lastActivity,
            contextTokens: contextTokens,
            contextLimit: contextWindow ?? 272_000
        )
        session.limits = limits
        return session
    }

    private static func int(_ value: Any?) -> Int {
        (value as? NSNumber)?.intValue ?? 0
    }

    private static func firstLine(_ text: String) -> String? {
        guard let line = text
            .split(whereSeparator: \.isNewline)
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { !$0.isEmpty }) else { return nil }
        return line.count > 160 ? String(line.prefix(160)) + "…" : line
    }
}

public extension AgentFormat {
    /// "gpt-5-codex" → "GPT-5 Codex", "gpt-5.1-codex-max" → "GPT-5.1 Codex Max",
    /// "o4-mini" → "o4 Mini".
    static func codexModelName(_ id: String) -> String {
        var parts = id.split(separator: "-").map(String.init)
        guard !parts.isEmpty else { return id }
        var name: String
        if parts[0].lowercased() == "gpt", parts.count > 1 {
            name = "GPT-\(parts[1])"
            parts.removeFirst(2)
        } else {
            name = parts.removeFirst()
        }
        for part in parts {
            name += " " + part.prefix(1).uppercased() + part.dropFirst()
        }
        return name
    }
}
