import Foundation
import Testing
import WebKit
import NotchHubCore
@testable import NotchHubSystem

@Suite("NeoListener parsing")
struct NeoListenerParsingTests {

    @Test("a hello yields NEO's state and nothing from the replay")
    func hello() {
        let text = #"{"type":"hello","data":{"state":"listening","recent":[{"type":"transcript","data":{"role":"assistant","text":"old","final":true},"ts":1}],"confirm":null,"problems":[]},"ts":2}"#
        #expect(NeoListener.facts(in: text) == [.state(.listening)])
    }

    @Test("state, transcript, note and error are facts; the rest is not")
    func messages() {
        #expect(NeoListener.facts(in: #"{"type":"state","data":{"state":"speaking","job":"j1"},"ts":1}"#) == [.state(.speaking)])
        #expect(NeoListener.facts(in: #"{"type":"transcript","data":{"role":"user","text":"hi","final":false,"job":""},"ts":1}"#)
            == [.transcript(role: .user, text: "hi", final: false)])
        #expect(NeoListener.facts(in: #"{"type":"note","data":{"text":"n"},"ts":1}"#) == [.note("n")])
        #expect(NeoListener.facts(in: #"{"type":"error","data":{"message":"m"},"ts":1}"#) == [.error("m")])
        for other in ["browser_state", "camera_state", "song_state", "tool_start", "tool_end", "turn", "confirm", "problems", "erased", "ui_host"] {
            #expect(NeoListener.facts(in: #"{"type":"\#(other)","data":{"state":"speaking"},"ts":1}"#).isEmpty, "\(other)")
        }
    }

    @Test("a card's opening and closing are facts for the panel")
    func cards() {
        #expect(NeoListener.facts(in: #"{"type":"browser_open","data":{"sid":"s","job":"j"},"ts":1}"#) == [.card(.browser, open: true)])
        #expect(NeoListener.facts(in: #"{"type":"browser_close","data":{"sid":"s","reason":"done"},"ts":1}"#) == [.card(.browser, open: false)])
        #expect(NeoListener.facts(in: #"{"type":"camera_open","data":{"sid":"c"},"ts":1}"#) == [.card(.camera, open: true)])
        #expect(NeoListener.facts(in: #"{"type":"camera_close","data":{"sid":"c","reason":"stopped"},"ts":1}"#) == [.card(.camera, open: false)])
        #expect(NeoListener.facts(in: #"{"type":"song_open","data":{"sid":"m"},"ts":1}"#) == [.card(.song, open: true)])
        #expect(NeoListener.facts(in: #"{"type":"song_close","data":{"sid":"m"},"ts":1}"#) == [.card(.song, open: false)])
    }

    @Test("NEO summoned by hand (the hotkey, the tray) is a fact for the panel")
    func woke() {
        #expect(NeoListener.facts(in: #"{"type":"woke","data":{"source":"ui"},"ts":1}"#) == [.woke])
        #expect(NeoListener.facts(in: #"{"type":"woke","data":{},"ts":1}"#) == [.woke])
    }

    @Test("garbage and unknown states yield nothing rather than a crash")
    func garbage() {
        #expect(NeoListener.facts(in: "not json").isEmpty)
        #expect(NeoListener.facts(in: "[1,2]").isEmpty)
        #expect(NeoListener.facts(in: #"{"type":"state","data":{"state":"dancing"}}"#).isEmpty)
        #expect(NeoListener.facts(in: #"{"type":"transcript","data":{"role":"robot","text":"x"}}"#).isEmpty)
    }

    @Test("the token is read from the one file, trimmed, and must look like one")
    func token() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("notchhub-neo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("ws-token")
        #expect(NeoListener.readToken(at: file) == nil)
        let token = String(repeating: "ab", count: 32)
        try "\(token)\n".write(to: file, atomically: true, encoding: .utf8)
        #expect(NeoListener.readToken(at: file) == token)
        try "short".write(to: file, atomically: true, encoding: .utf8)
        #expect(NeoListener.readToken(at: file) == nil)
        try "\(token)&x=y".write(to: file, atomically: true, encoding: .utf8)
        #expect(NeoListener.readToken(at: file) == nil)
        let url = NeoListener.socketURL(base: NeoListener.defaultURL, token: token)
        #expect(url?.absoluteString == "ws://127.0.0.1:8765/?token=\(token)")
    }
}

/// Runs the listener against `Fixtures/neo_stub.py`, a stand-in for NEO's
/// core served by the `websockets` package in NEO's own virtualenv. Never the
/// real core: a scratch port and a scratch token file in a temp folder.
@Suite("NeoListener against a stub core", .serialized)
struct NeoListenerStubTests {

    static let python = URL(fileURLWithPath: "/Users/arnav/Documents/Neo 2.0/NEO/.venv/bin/python")
    static let stub = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/neo_stub.py")

    /// Whether the stub can run here at all (the venv with `websockets`).
    static let available: Bool = {
        guard FileManager.default.isExecutableFile(atPath: python.path) else { return false }
        let probe = Process()
        probe.executableURL = python
        probe.arguments = ["-c", "import websockets"]
        probe.standardOutput = FileHandle.nullDevice
        probe.standardError = FileHandle.nullDevice
        do { try probe.run() } catch { return false }
        probe.waitUntilExit()
        return probe.terminationStatus == 0
    }()

    /// Collects facts from whatever thread the listener emits on.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var facts: [NeoFact] = []
        func record(_ event: SystemEvent) {
            guard case let .neo(fact) = event.payload else { return }
            lock.lock()
            facts.append(fact)
            lock.unlock()
        }
        var snapshot: [NeoFact] {
            lock.lock()
            defer { lock.unlock() }
            return facts
        }
    }

    /// The stub process and what it printed.
    private final class Stub: @unchecked Sendable {
        let process = Process()
        private let lock = NSLock()
        private var text = ""
        let port: Int
        let token = String(repeating: "7f", count: 32)
        let folder: URL
        var tokenFile: URL { folder.appendingPathComponent("ws-token") }

        init(drop: Bool) throws {
            port = Int.random(in: 20_000...60_000)
            folder = FileManager.default.temporaryDirectory.appendingPathComponent("notchhub-neo-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try token.write(to: tokenFile, atomically: true, encoding: .utf8)
            process.executableURL = NeoListenerStubTests.python
            process.arguments = [NeoListenerStubTests.stub.path, "\(port)", token] + (drop ? ["drop"] : [])
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                guard let self, let chunk = String(data: handle.availableData, encoding: .utf8), !chunk.isEmpty else { return }
                self.lock.lock()
                self.text += chunk
                self.lock.unlock()
            }
            try process.run()
        }

        var lines: [String] {
            lock.lock()
            defer { lock.unlock() }
            return text.split(separator: "\n").map(String.init)
        }

        func stop() {
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
            try? FileManager.default.removeItem(at: folder)
        }
    }

    private func waitFor(_ condition: @escaping () -> Bool, timeout: TimeInterval = 6) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        return condition()
    }

    @Test("connects with the token, sends only camera_view off, and relays the island's facts", .enabled(if: NeoListenerStubTests.available))
    func connectAndRelay() async throws {
        let stub = try Stub(drop: false)
        defer { stub.stop() }
        #expect(await waitFor { stub.lines.contains("READY") })

        let recorder = Recorder()
        let listener = NeoListener(url: URL(string: "ws://127.0.0.1:\(stub.port)/")!, tokenFile: stub.tokenFile, reconnectDelay: 0.2) { recorder.record($0) }
        listener.start()
        defer { listener.stop() }

        #expect(await waitFor { recorder.snapshot.contains(.state(.idle)) })
        let facts = recorder.snapshot
        #expect(facts == [
            .connected(true),
            .state(.listening), // from the hello — and nothing from its replay
            .transcript(role: .user, text: "hello neo", final: false),
            .state(.thinking),
            .card(.browser, open: true), // the card's own state in between is not ours
            .card(.browser, open: false),
            .transcript(role: .assistant, text: "Hi there", final: true),
            .note("quiet result"),
            .error("boom"),
            .state(.idle),
        ])

        // The stub refuses any Origin but NEO's own, so a connection proves
        // URLSession sent none — and the one command is the camera opt-out.
        #expect(await waitFor { stub.lines.contains { $0.hasPrefix("CMD ") } })
        let commands = stub.lines.filter { $0.hasPrefix("CMD ") }
        #expect(commands == ["CMD " + NeoListener.cameraOffCommand])
        #expect(stub.lines.contains("ORIGIN -"))
        #expect(!stub.lines.contains { $0.hasPrefix("REJECT") })
    }

    @Test("hosting NEO's UI it says so on connecting, and hands the UI back as it stops", .enabled(if: NeoListenerStubTests.available))
    func hostsUI() async throws {
        let stub = try Stub(drop: false)
        defer { stub.stop() }
        #expect(await waitFor { stub.lines.contains("READY") })

        let recorder = Recorder()
        let listener = NeoListener(url: URL(string: "ws://127.0.0.1:\(stub.port)/")!, tokenFile: stub.tokenFile, reconnectDelay: 0.2, hostsUI: true) { recorder.record($0) }
        listener.start()
        #expect(await waitFor { stub.lines.filter { $0.hasPrefix("CMD ") }.count == 2 })
        #expect(stub.lines.filter { $0.hasPrefix("CMD ") } == ["CMD " + NeoListener.cameraOffCommand, "CMD " + NeoListener.hostNotchCommand])

        let began = Date()
        listener.stop() // waits, briefly, for the hand-back to leave
        #expect(Date().timeIntervalSince(began) < 1)
        #expect(await waitFor { stub.lines.contains("CMD " + NeoListener.hostWindowCommand) })
        #expect(recorder.snapshot.last == .connected(false))
    }

    /// NEO's page, served by `NeoSchemeHandler` from a temp folder into a
    /// real `WKWebView` with the host script injected, opens a websocket to
    /// the stub: the Origin it sends is exactly `neo://app` (what NEO's core
    /// admits), the token it uses is the injected one, and its message to
    /// the host comes back through the `neo` handler.
    @Test("a page from neo://app reaches the core with that origin and the injected token", .enabled(if: NeoListenerStubTests.available))
    @MainActor
    func pageOrigin() async throws {
        let stub = try Stub(drop: false)
        defer { stub.stop() }
        #expect(await waitFor { stub.lines.contains("READY") })

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("notchhub-neo-page-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let page = """
        <!doctype html><html><body><script>
        const port = new URLSearchParams(location.search).get("port");
        const ws = new WebSocket("ws://127.0.0.1:" + port + "/?token=" + encodeURIComponent(window.__NEO_WS_TOKEN__));
        ws.onopen = () => { ws.send(JSON.stringify({cmd: "page", host: window.__NEO_HOST__, area: window.__NEO_HOST_AREA__}));
          window.webkit.messageHandlers.neo.postMessage({type: "size", w: 420, h: 520}); };
        </script></body></html>
        """
        try page.write(to: folder.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)

        final class Messages: NSObject, WKScriptMessageHandler, @unchecked Sendable {
            var bodies: [Any] = []
            func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) { bodies.append(message.body) }
        }
        let messages = Messages()
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(NeoSchemeHandler(folder: folder), forURLScheme: NeoSchemeHandler.scheme)
        configuration.userContentController.addUserScript(WKUserScript(
            source: NeoHostScript.source(token: stub.token, maxPage: CGSize(width: 760, height: 640)), injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.userContentController.add(messages, name: "neo")
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 420, height: 520), configuration: configuration)
        web.load(URLRequest(url: URL(string: "neo://app/index.html?port=\(stub.port)")!))

        #expect(await waitFor { stub.lines.contains { $0.hasPrefix("CMD {\"cmd\":\"page\"") } })
        #expect(stub.lines.contains("ORIGIN \(NeoSchemeHandler.origin)"))
        #expect(!stub.lines.contains { $0.hasPrefix("REJECT") })
        let command = stub.lines.first { $0.hasPrefix("CMD {\"cmd\":\"page\"") } ?? ""
        #expect(command.contains(#""host":"notch""#) && command.contains(#""area":{"w":760,"h":640}"#))
        #expect(await waitFor { !messages.bodies.isEmpty })
        #expect(messages.bodies.first.flatMap(NeoHostMessage.parse) == .size(CGSize(width: 420, height: 520)))
        web.stopLoading()
    }

    @Test("a dropped core is reported, and the listener comes back on its own", .enabled(if: NeoListenerStubTests.available))
    func reconnect() async throws {
        let stub = try Stub(drop: true)
        defer { stub.stop() }
        #expect(await waitFor { stub.lines.contains("READY") })

        let recorder = Recorder()
        let listener = NeoListener(url: URL(string: "ws://127.0.0.1:\(stub.port)/")!, tokenFile: stub.tokenFile, reconnectDelay: 0.2) { recorder.record($0) }
        listener.start()
        defer { listener.stop() }

        // First connection: scripted, then closed by the server.
        #expect(await waitFor { recorder.snapshot.contains(.connected(false)) })
        // Second connection on its own, with a fresh hello.
        #expect(await waitFor { stub.lines.contains("OPEN 2") })
        #expect(await waitFor { recorder.snapshot.filter { $0 == .connected(true) }.count == 2 })
        #expect(await waitFor { recorder.snapshot.filter { $0 == .state(.listening) }.count == 2 })
        let connections = recorder.snapshot.filter {
            if case .connected = $0 { return true } else { return false }
        }
        #expect(connections == [.connected(true), .connected(false), .connected(true)])
    }

    @Test("with no token file nothing is reported, and it connects once one appears", .enabled(if: NeoListenerStubTests.available))
    func waitsForToken() async throws {
        let stub = try Stub(drop: false)
        defer { stub.stop() }
        #expect(await waitFor { stub.lines.contains("READY") })
        let token = stub.token
        try FileManager.default.removeItem(at: stub.tokenFile)

        let recorder = Recorder()
        let listener = NeoListener(url: URL(string: "ws://127.0.0.1:\(stub.port)/")!, tokenFile: stub.tokenFile, reconnectDelay: 0.2) { recorder.record($0) }
        listener.start()
        defer { listener.stop() }
        try await Task.sleep(nanoseconds: 600_000_000)
        #expect(recorder.snapshot.isEmpty)
        #expect(!stub.lines.contains { $0.hasPrefix("OPEN") })

        try token.write(to: stub.tokenFile, atomically: true, encoding: .utf8)
        #expect(await waitFor { recorder.snapshot.contains(.connected(true)) })
    }

    @Test("with no core at the port the listener stays quiet and never crashes", .enabled(if: NeoListenerStubTests.available))
    func noCore() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("notchhub-neo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("ws-token")
        try String(repeating: "0a", count: 32).write(to: file, atomically: true, encoding: .utf8)

        let recorder = Recorder()
        // A port nobody listens on.
        let listener = NeoListener(url: URL(string: "ws://127.0.0.1:1/")!, tokenFile: file, reconnectDelay: 0.1) { recorder.record($0) }
        listener.start()
        try await Task.sleep(nanoseconds: 700_000_000)
        listener.stop()
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(recorder.snapshot.isEmpty)
    }
}
