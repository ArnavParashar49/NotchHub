import Foundation
import Testing
@testable import NotchHubCore

@Suite("CodexSessionParser")
struct CodexSessionParserTests {

    private let lines = [
        #"{"timestamp":"2026-09-14T09:00:00.000Z","type":"session_meta","payload":{"id":"s","cwd":"/Users/a/NotchyWebsite","originator":"codex_cli_rs"}}"#,
        #"{"timestamp":"2026-09-14T09:00:01.000Z","type":"turn_context","payload":{"cwd":"/Users/a/NotchyWebsite","model":"gpt-5.1-codex-max"}}"#,
        #"{"timestamp":"2026-09-14T09:00:02.000Z","type":"event_msg","payload":{"type":"user_message","message":"Port the island chips\nextra"}}"#,
        #"{"timestamp":"2026-09-14T09:00:05.000Z","type":"response_item","payload":{"type":"function_call","name":"shell"}}"#,
        #"{"timestamp":"2026-09-14T09:00:06.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":18000,"cached_input_tokens":9000,"output_tokens":800,"total_tokens":18800},"last_token_usage":{"total_tokens":12000},"model_context_window":272000},"rate_limits":{"primary":{"used_percent":54.0,"window_minutes":300,"resets_in_seconds":3600},"secondary":{"used_percent":67.0,"window_minutes":10080,"resets_at":1789462800}}}}"#,
    ]

    private func feed(_ lines: [String]) -> CodexSessionParser {
        var parser = CodexSessionParser()
        for line in lines { parser.consume(Data(line.utf8)) }
        return parser
    }

    @Test("a rollout yields model, project, tokens, context and plan limits")
    func parsesRollout() {
        let now = ClaudeSessionParser.date(from: "2026-09-14T09:00:07.000Z")!
        let session = feed(lines).session(now: now)
        #expect(session.tool == "Codex")
        #expect(session.model == "GPT-5.1 Codex Max")
        #expect(session.project == "NotchyWebsite")
        #expect(session.title == "Port the island chips")
        #expect(session.turns == 1)
        #expect(session.tokens == 18_800)
        #expect(session.contextTokens == 12_000)
        #expect(session.contextLimit == 272_000)
        #expect(session.isWorking)
        #expect(session.limits.map(\.label) == ["5-hour limit", "Weekly limit"])
        #expect(session.limits[0].usedPercent == 54)
        #expect(session.limits[0].resetsAt == ClaudeSessionParser.date(from: "2026-09-14T10:00:06.000Z"))
        #expect(session.limits[1].resetsAt == Date(timeIntervalSince1970: 1_789_462_800))
    }

    @Test("a completed task is idle")
    func completedIsIdle() {
        let done = lines + [#"{"timestamp":"2026-09-14T09:00:09.000Z","type":"event_msg","payload":{"type":"task_complete"}}"#]
        let now = ClaudeSessionParser.date(from: "2026-09-14T09:00:10.000Z")!
        #expect(!feed(done).session(now: now).isWorking)
    }

    @Test("model names and limit labels read naturally")
    func names() {
        #expect(AgentFormat.codexModelName("gpt-5-codex") == "GPT-5 Codex")
        #expect(AgentFormat.codexModelName("o4-mini") == "o4 Mini")
        #expect(AgentLimit.label(windowMinutes: 300) == "5-hour limit")
        #expect(AgentLimit.label(windowMinutes: 10_080) == "Weekly limit")
        #expect(AgentLimit.label(windowMinutes: nil) == "Limit")
    }
}
