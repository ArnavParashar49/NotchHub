import Foundation
import NotchHubCore

/// Detects coding agents running on the machine (Claude Code, Codex, Cursor's
/// agent, Aider, …).
///
/// These tools are command-line processes, so `NSWorkspace.runningApplications`
/// never shows them — the reliable signal is the process table itself.
/// Matching a known agent's process name is a real, honest detector: it means
/// the tool is genuinely running, not that we guessed.
///
/// The island only needs to know when an agent starts and stops, so the poll is
/// slow and emits solely on a transition.
public final class CodingAgentListener: SystemListener {

    /// Process name (as the kernel truncates it, ≤16 chars) → display name.
    private static let knownAgents: [(process: String, display: String)] = [
        ("claude", "Claude Code"),
        ("codex", "Codex"),
        ("cursor-agent", "Cursor Agent"),
        ("aider", "Aider"),
        ("opencode", "opencode"),
        ("goose", "Goose"),
        ("gemini", "Gemini CLI"),
    ]

    private let emit: (SystemEvent) -> Void
    private var timer: Timer?
    private var lastAgent: String?

    public init(emit: @escaping (SystemEvent) -> Void) {
        self.emit = emit
    }

    public var name: String { "CodingAgent" }

    public func start() {
        stop()
        lastAgent = Self.runningAgent()
        // Report an agent that was already running, so the wings show it
        // without waiting for the next start.
        if let lastAgent {
            emit(SystemEvent(source: .codingAgent, payload: .codingAgent(running: true, agent: lastAgent)))
        }
        let timer = Timer(timeInterval: 4, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let agent = Self.runningAgent()
        guard agent != lastAgent else { return }
        let previous = lastAgent
        lastAgent = agent

        if let agent {
            emit(SystemEvent(source: .codingAgent, payload: .codingAgent(running: true, agent: agent)))
        } else if let previous {
            emit(SystemEvent(source: .codingAgent, payload: .codingAgent(running: false, agent: previous)))
        }
    }

    /// The display name of the first known agent found running, if any.
    static func runningAgent() -> String? {
        let names = ProcessTable.names()
        return knownAgents.first { names.contains($0.process) }?.display
    }
}
