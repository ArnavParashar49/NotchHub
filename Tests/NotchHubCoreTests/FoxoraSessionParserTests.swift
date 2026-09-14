import Foundation
import Testing
@testable import NotchHubCore

@Suite("FoxoraSessionParser")
struct FoxoraSessionParserTests {

    let t0: Double = 1_789_316_000_000

    private func records() -> [[String: Any]] {
        [
            ["sessionId": "s", "id": "1", "event": ["type": "user-prompt", "createdAt": t0]],
            ["sessionId": "s", "id": "2", "event": ["type": "run-signal", "signal": "started"], "startedAt": t0 + 500],
            ["sessionId": "s", "id": "3", "event": [
                "type": "text-start",
                "message": ["metadata": ["modelId": "foxora-ai-max", "provider": "foxora"]],
            ]],
            ["sessionId": "s", "id": "4", "event": ["type": "step-finish", "runId": "r1", "payload": ["output": ["usage": ["totalTokens": 1200, "promptTokens": 1000, "completionTokens": 200]]]]],
            ["sessionId": "s", "id": "5", "event": ["type": "step-finish", "runId": "r2", "payload": ["output": ["usage": ["promptTokens": 300, "completionTokens": 50]]]]],
            ["sessionId": "s", "id": "6", "event": ["type": "data-om-status", "data": ["windows": ["active": ["messages": ["tokens": 72441, "threshold": 838861]]]]]],
            ["sessionId": "s", "id": "7", "event": ["type": "tool-call", "title": "Collapse Animation Frames", "createdAt": t0 + 30_000]],
        ]
    }

    @Test("events yield model, tokens, turns, memory window and task")
    func parsesEvents() {
        var parser = FoxoraSessionParser()
        records().forEach { parser.consume($0) }
        let now = Date(timeIntervalSince1970: (t0 + 31_000) / 1000)
        let session = parser.session(now: now)
        #expect(session.tool == "Foxora")
        #expect(session.model == "Foxora AI Max")
        #expect(session.tokens == 1200 + 350)
        #expect(session.turns == 1)
        #expect(session.contextTokens == 72441)
        #expect(session.contextLimit == 838861)
        #expect(session.title == "Collapse Animation Frames")
        #expect(session.isWorking)
        #expect(session.startedAt == Date(timeIntervalSince1970: t0 / 1000))
    }

    @Test("steps of one run count the run's peak, not their sum")
    func runPeak() {
        var parser = FoxoraSessionParser()
        for total in [270_000, 265_000, 271_500] {
            parser.consume(["sessionId": "s", "event": ["type": "step-finish", "runId": "r", "payload": ["output": ["usage": ["totalTokens": total]]]]])
        }
        parser.consume(["sessionId": "s", "event": ["type": "step-finish", "runId": "q", "payload": ["output": ["usage": ["totalTokens": 1000]]]]])
        #expect(parser.tokens == 271_500 + 1000)
    }

    @Test("a completed or cancelled run is idle")
    func finishedRunIsIdle() {
        for signal in ["completed", "cancelled"] {
            var parser = FoxoraSessionParser()
            records().forEach { parser.consume($0) }
            parser.consume(["sessionId": "s", "event": ["type": "run-signal", "signal": signal, "createdAt": t0 + 40_000]])
            #expect(!parser.session(now: Date(timeIntervalSince1970: (t0 + 41_000) / 1000)).isWorking)
        }
    }

    @Test("model ids read as names")
    func modelNames() {
        #expect(AgentFormat.foxoraModelName("foxora/foxora-ai-premium") == "Foxora AI Premium")
        #expect(AgentFormat.foxoraModelName("foxora-ai-max") == "Foxora AI Max")
    }
}
