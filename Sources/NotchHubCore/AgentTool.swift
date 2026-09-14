import Foundation

/// The coding agents whose sessions the island can follow.
public enum AgentTool: String, CaseIterable, Sendable {
    case claudeCode
    case codex
    case foxora
}

/// A session log parser, fed one line at a time.
public protocol AgentTranscriptParser {
    init()
    mutating func consume(_ line: Data)
    func agentSession(now: Date) -> AgentSession
}

extension ClaudeSessionParser: AgentTranscriptParser {
    public func agentSession(now: Date) -> AgentSession { session(now: now) }
}

extension CodexSessionParser: AgentTranscriptParser {
    public func agentSession(now: Date) -> AgentSession { session(now: now) }
}

public extension AppSkinRegistry {
    /// The agent an app is dedicated to. Terminals and editors have none: they
    /// show whichever session was active most recently.
    static func dedicatedAgent(for bundleID: String) -> AgentTool? {
        switch bundleID {
        case "com.anthropic.claudefordesktop": return .claudeCode
        case "com.openai.codex": return .codex
        case "ai.foxora.desktop": return .foxora
        default: return nil
        }
    }
}
