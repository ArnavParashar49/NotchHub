import Foundation
import NotchHubCore

/// A diagnostic: the latest session each agent reader can find, regardless of
/// age. Backs `NotchHub --agent-sessions`.
public enum AgentSessionProbe {

    public static func latest(now: Date = Date()) -> [AgentSession] {
        let claude = AgentSessionReader<ClaudeSessionParser>(findNewest: AgentTranscripts.newestClaude)
        let codex = AgentSessionReader<CodexSessionParser>(findNewest: AgentTranscripts.newestCodex)
        let foxora = FoxoraSessionReader()
        claude.maxAge = .greatestFiniteMagnitude
        codex.maxAge = .greatestFiniteMagnitude
        foxora.maxAge = .greatestFiniteMagnitude
        return [claude.currentSession(now: now), codex.currentSession(now: now), foxora.currentSession(now: now)]
            .compactMap { $0 }
    }
}
