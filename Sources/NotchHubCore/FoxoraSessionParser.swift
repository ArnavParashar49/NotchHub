import Foundation

/// Follows a Foxora Studio session from its event log (the app's IndexedDB
/// `events` store), one decoded record at a time.
///
/// A record is `{sessionId, id, event, startedAt?, completedAt?}`; the useful
/// events are `user-prompt` (a turn), `run-signal` (started / queued /
/// completed / cancelled), `step-finish` (token usage — each step re-reports
/// the whole prompt, so a run counts its PEAK, not the sum of its steps),
/// `data-om-status` (the
/// memory window's size and threshold) and messages carrying the model id.
/// Credits are not recorded locally, so they are not shown. Unknown events are
/// ignored.
public struct FoxoraSessionParser {

    public private(set) var modelID: String?
    public private(set) var title: String?
    public private(set) var turns = 0
    /// Peak tokens per run. Summing every step would count the resent context
    /// once per step (tens of millions for one session).
    private var runPeaks: [String: Int] = [:]
    public var tokens: Int { runPeaks.values.reduce(0, +) }
    public private(set) var startedAt: Date?
    public private(set) var lastActivity: Date?
    public private(set) var contextTokens: Int?
    public private(set) var contextLimit: Int?
    public private(set) var isRunning = false

    public init() {}

    public mutating func consume(_ record: [String: Any]) {
        let event = record["event"] as? [String: Any] ?? [:]
        let payload = event["payload"] as? [String: Any]

        for raw in [record["startedAt"], record["completedAt"], event["createdAt"], payload?["startedAt"], payload?["completedAt"]] {
            guard let ms = Self.number(raw), ms > 0 else { continue }
            let date = Date(timeIntervalSince1970: ms / 1000)
            startedAt = min(startedAt ?? date, date)
            lastActivity = max(lastActivity ?? date, date)
        }

        switch event["type"] as? String {
        case "user-prompt":
            turns += 1
            isRunning = true
        case "run-signal":
            switch event["signal"] as? String {
            case "started", "queued": isRunning = true
            case "completed", "cancelled", "failed", "error": isRunning = false
            default: break
            }
        case "step-finish":
            let usage = (payload?["output"] as? [String: Any])?["usage"] as? [String: Any]
            if let usage {
                let total = Self.number(usage["totalTokens"])
                    ?? ((Self.number(usage["promptTokens"]) ?? 0) + (Self.number(usage["completionTokens"]) ?? 0))
                let run = (event["runId"] as? String) ?? ""
                runPeaks[run] = max(runPeaks[run] ?? 0, Int(total))
            }
        case "data-om-status":
            let active = ((event["data"] as? [String: Any])?["windows"] as? [String: Any])?["active"] as? [String: Any]
            if let messages = active?["messages"] as? [String: Any] {
                contextTokens = Self.number(messages["tokens"]).map { Int($0) }
                contextLimit = Self.number(messages["threshold"]).map { Int($0) }
            }
        default:
            break
        }

        if let metadata = (event["message"] as? [String: Any])?["metadata"] as? [String: Any],
           let model = metadata["modelId"] as? String, !model.isEmpty {
            modelID = model
        }
        if let text = (event["title"] as? String) ?? (payload?["title"] as? String),
           !text.trimmingCharacters(in: .whitespaces).isEmpty {
            title = text
        }
    }

    public func session(now: Date, workingWindow: TimeInterval = 120) -> AgentSession {
        let recent = lastActivity.map { now.timeIntervalSince($0) < workingWindow } ?? false
        return AgentSession(
            tool: "Foxora",
            model: modelID.map(AgentFormat.foxoraModelName),
            title: title,
            project: nil,
            isWorking: isRunning && recent,
            tokens: tokens,
            turns: turns,
            startedAt: startedAt,
            lastActivity: lastActivity,
            contextTokens: contextTokens,
            contextLimit: max(1, contextLimit ?? 1_000_000)
        )
    }

    static func number(_ value: Any?) -> Double? {
        switch value {
        case let v as Double: return v
        case let v as Int: return Double(v)
        case let v as Int32: return Double(v)
        case let v as NSNumber: return v.doubleValue
        default: return nil
        }
    }
}

public extension AgentFormat {
    /// "foxora/foxora-ai-premium" → "Foxora AI Premium".
    static func foxoraModelName(_ id: String) -> String {
        let last = id.split(separator: "/").last.map(String.init) ?? id
        return last.split(separator: "-").map { part -> String in
            part.lowercased() == "ai" ? "AI" : part.prefix(1).uppercased() + part.dropFirst()
        }.joined(separator: " ")
    }
}
