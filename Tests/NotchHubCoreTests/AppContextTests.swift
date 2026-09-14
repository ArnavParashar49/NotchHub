import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import NotchHubCore

@Suite("App context")
struct AppContextTests {

    // MARK: Formatting

    @Test("model ids read as family and version")
    func modelNames() {
        #expect(AgentFormat.modelName("claude-opus-5") == "Opus 5")
        #expect(AgentFormat.modelName("claude-fable-5-1") == "Fable 5.1")
        #expect(AgentFormat.modelName("claude-sonnet-4-5-20250929") == "Sonnet 4.5")
        #expect(AgentFormat.modelName("claude-3-5-haiku-20241022") == "Haiku 3.5")
        #expect(AgentFormat.modelName("claude-opus-4-6[1m]") == "Opus 4.6")
        #expect(AgentFormat.modelName("<synthetic>") == nil)
    }

    @Test("token counts are compact")
    func tokenCounts() {
        #expect(AgentFormat.tokens(812) == "812")
        #expect(AgentFormat.tokens(19_700) == "19.7k")
        #expect(AgentFormat.tokens(82_000) == "82.0k")
        #expect(AgentFormat.tokens(1_260_000) == "1.3M")
    }

    // MARK: Browser

    @Test("a browser context matches the active tab and trims hosts")
    func browserContext() {
        let context = BrowserContext.from(
            activeTitle: "Search",
            activeURL: "https://www.google.com/search?q=x",
            titles: ["GitHub", "Search", "YouTube"],
            urls: ["https://github.com/", "https://www.google.com/search?q=x", "https://youtube.com/watch"]
        )
        #expect(context.host == "google.com")
        #expect(context.tabCount == 3)
        #expect(context.activeIndex == 2)
        #expect(context.tabs[0].host == "github.com")
    }

    @Test("the tab row shows the tabs around the active one")
    func nearbyTabs() {
        func context(active: Int) -> BrowserContext {
            let tabs = (1...10).map { BrowserTab(index: $0, title: "T\($0)", host: nil) }
            return BrowserContext(title: "T\(active)", host: nil, tabs: tabs, activeIndex: active)
        }
        #expect(context(active: 1).nearbyTabs().map(\.index) == [1, 2, 3])
        #expect(context(active: 5).nearbyTabs().map(\.index) == [4, 5, 6])
        #expect(context(active: 10).nearbyTabs().map(\.index) == [8, 9, 10])
    }

    // MARK: Claude sessions

    private func feed(_ lines: [String]) -> ClaudeSessionParser {
        var parser = ClaudeSessionParser()
        for line in lines { parser.consume(Data(line.utf8)) }
        return parser
    }

    private let transcript = [
        #"{"type":"user","promptSource":"typed","cwd":"/Users/a/NotchHub","timestamp":"2026-09-14T08:00:00.000Z","message":{"role":"user","content":"hi"}}"#,
        #"{"type":"assistant","timestamp":"2026-09-14T08:00:05.000Z","message":{"id":"m1","model":"claude-opus-5","stop_reason":null,"usage":{"input_tokens":2,"cache_creation_input_tokens":1000,"cache_read_input_tokens":40000,"output_tokens":50}}}"#,
        #"{"type":"assistant","timestamp":"2026-09-14T08:00:06.000Z","message":{"id":"m1","model":"claude-opus-5","stop_reason":"tool_use","usage":{"input_tokens":2,"cache_creation_input_tokens":1000,"cache_read_input_tokens":40000,"output_tokens":200}}}"#,
        #"{"type":"user","timestamp":"2026-09-14T08:00:07.000Z","message":{"role":"user","content":[{"type":"tool_result"}]}}"#,
        #"{"type":"assistant","isSidechain":true,"timestamp":"2026-09-14T08:00:08.000Z","message":{"id":"s1","model":"claude-haiku-4-5","stop_reason":"end_turn","usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":90}}}"#,
        #"{"type":"assistant","timestamp":"2026-09-14T08:00:10.000Z","message":{"id":"m2","model":"claude-opus-5","stop_reason":"end_turn","usage":{"input_tokens":5,"cache_creation_input_tokens":300,"cache_read_input_tokens":41000,"output_tokens":120}}}"#,
        #"{"type":"custom-title","customTitle":"Porting the island chips","sessionId":"x"}"#,
        #"not json"#,
    ]

    @Test("a transcript yields model, tokens, turns, context and title")
    func parsesTranscript() {
        let parser = feed(transcript)
        let end = ClaudeSessionParser.date(from: "2026-09-14T08:00:10.000Z")!
        let session = parser.session(now: end)
        #expect(session.model == "Opus 5")
        #expect(session.project == "NotchHub")
        #expect(session.title == "Porting the island chips")
        #expect(session.turns == 1)
        // m1 counted once (its last usage), plus the sidechain, plus m2.
        #expect(session.tokens == (2 + 1000 + 200) + (10 + 90) + (5 + 300 + 120))
        #expect(session.contextTokens == 5 + 300 + 41000)
        #expect(session.contextLimit == 200_000)
        #expect(!session.isWorking)
        #expect(session.startedAt == ClaudeSessionParser.date(from: "2026-09-14T08:00:00.000Z"))
    }

    @Test("a session is working only while awaiting the model and recently active")
    func workingState() {
        let parser = feed(Array(transcript.prefix(4)))
        let last = ClaudeSessionParser.date(from: "2026-09-14T08:00:07.000Z")!
        #expect(parser.session(now: last.addingTimeInterval(5)).isWorking)
        #expect(!parser.session(now: last.addingTimeInterval(3600)).isWorking)
    }

    // MARK: Layouts

    @Test("hover strip browser buttons sit on the right wing and resolve")
    func wingButtons() {
        let notchWidth: CGFloat = 200
        let frame = CGRect(x: 500, y: 0, width: 200 + 2 * 120, height: 32)
        let buttons = WingControlLayout.browserButtons(in: frame, notchWidth: notchWidth, inset: 16)
        #expect(buttons.map(\.action) == [.back, .forward, .newTab])
        for button in buttons {
            #expect(frame.contains(button.rect))
            #expect(button.rect.minX >= frame.midX + notchWidth / 2)
            let centre = CGPoint(x: button.rect.midX, y: button.rect.midY)
            #expect(WingControlLayout.browserAction(at: centre, in: frame, notchWidth: notchWidth, inset: 16) == button.action)
        }
    }

    @Test("hover wings size each side to its content; browser buttons stay clear of the notch")
    func asymmetricWings() {
        let g = NotchGeometry.make(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeAreaInsets: NSEdgeInsets(top: 32, left: 0, bottom: 0, right: 0),
            auxiliaryLeft: CGRect(x: 0, y: 950, width: 663.5, height: 32),
            auxiliaryRight: CGRect(x: 848.5, y: 950, width: 663.5, height: 32)
        )
        var content = IslandContentSize(compactLead: 0, compactTrail: 0, wingSide: 120)
        content.wingLead = 56
        let frame = g.frame(for: .wings, content: content)
        #expect(abs(frame.minX - (g.notchFrame.minX - 56)) < 0.001)
        #expect(abs(frame.maxX - (g.notchFrame.maxX + 120)) < 0.001)
        let buttons = WingControlLayout.browserButtons(in: frame, notchWidth: 185, inset: 16, lead: 56)
        #expect(buttons.allSatisfy { $0.rect.minX >= g.notchFrame.maxX + 16 && frame.contains($0.rect) })
    }

    @Test("app panel controls fit, never overlap, and select the right tabs")
    func appPanelControls() {
        let frame = CGRect(x: 100, y: 0, width: 440, height: 216)
        let tabs = (4...6).map { BrowserTab(index: $0, title: "t\($0)", host: nil) }
        let placed = AppPanelLayout.actions(in: frame, notchInset: 32, browserTabs: tabs)
        #expect(placed.contains { $0.action == .browser(.selectTab(6)) })
        #expect(placed.filter { if case .browser(.selectTab) = $0.action { true } else { false } }.count == AppPanelLayout.maxTabRows)
        // Clicks resolve to the thing drawn under them.
        for item in placed {
            #expect(AppPanelLayout.action(at: CGPoint(x: item.rect.midX, y: item.rect.midY), in: frame, notchInset: 32, browserTabs: tabs) == item.action)
        }
        #expect(placed.first { $0.action == .dashboard }!.rect.minY >= frame.maxY - 32)
        for (i, a) in placed.enumerated() {
            #expect(frame.contains(a.rect), "\(a.action) outside")
            for b in placed[(i + 1)...] {
                #expect(!a.rect.intersects(b.rect), "\(a.action) overlaps \(b.action)")
            }
        }
        let agent = AppPanelLayout.actions(in: frame, notchInset: 32, browserTabs: nil)
        #expect(agent.map(\.action) == [.dashboard, .settings])
    }

    @Test("browser names are shortened for the hover strip")
    func shortAppNames() {
        #expect(AppStripLabel.shortAppName("Google Chrome") == "Chrome")
        #expect(AppStripLabel.shortAppName("Microsoft Edge") == "Edge")
        #expect(AppStripLabel.shortAppName("Brave Browser") == "Brave")
        #expect(AppStripLabel.shortAppName("Safari") == "Safari")
        #expect(AppStripLabel.shortAppName("Google") == "Google")
    }

    @Test("a call's compact bar has mute and leave at its trailing end")
    func meetingCompactButtons() {
        let frame = CGRect(x: 400, y: 0, width: 420, height: 32)
        let buttons = MeetingControlLayout.compactButtons(in: frame, inset: 14)
        #expect(buttons.map(\.control) == [.mute, .leave])
        #expect(buttons.allSatisfy { frame.contains($0.rect) })
        let leave = buttons[1].rect
        #expect(MeetingControlLayout.compactControl(at: CGPoint(x: leave.midX, y: leave.midY), in: frame, inset: 14) == .leave)
    }

    @Test("a browser keystroke is a virtual key code with ⌘")
    func browserShortcuts() {
        #expect(BrowserAction.back.shortcut == KeyChord(keyCode: 0x21))
        #expect(BrowserAction.newTab.shortcut == KeyChord(keyCode: 0x11))
        #expect(BrowserAction.selectTab(2).shortcut == nil)
    }

    // MARK: Behaviour

    @Test("hovering a call's bar keeps it compact; clicking opens the call panel")
    func meetingHoverStaysCompact() {
        let m = IslandStateMachine()
        m.setActivity(.meeting(Meeting(app: .zoom, title: "Zoom")))
        m.send(.activityStarted)
        #expect(m.send(.hoverEntered) == .compact)
        #expect(m.send(.clicked) == .expanded)
    }

    @Test("settings saved before a feature existed turn the new feature on")
    func featureMigration() throws {
        let legacy = #"{"enabled":["music","battery"]}"#
        let decoded = try JSONDecoder().decode(FeatureSettings.self, from: Data(legacy.utf8))
        #expect(decoded.isEnabled(.appDetails))
        #expect(!decoded.isEnabled(.calendar))

        var current = FeatureSettings()
        current.setEnabled(.appDetails, enabled: false)
        let data = try JSONEncoder().encode(current)
        #expect(!(try JSONDecoder().decode(FeatureSettings.self, from: data)).isEnabled(.appDetails))
    }
}
