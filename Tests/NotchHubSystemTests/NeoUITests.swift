import Foundation
import Testing
import WebKit
import NotchHubCore
@testable import NotchHubSystem

/// A `WKURLSchemeTask` that only records what it was given.
private final class RecordingTask: NSObject, WKURLSchemeTask {
    let request: URLRequest
    var response: URLResponse?
    var data = Data()
    var finished = false
    var error: Error?
    init(_ url: String, method: String = "GET") {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = method
        self.request = request
    }
    func didReceive(_ response: URLResponse) { self.response = response }
    func didReceive(_ data: Data) { self.data.append(data) }
    func didFinish() { finished = true }
    func didFailWithError(_ error: Error) { self.error = error }
}

@Suite("NEO page: the scheme handler and the host script")
struct NeoUITests {

    static func folder(_ files: [String: String]) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("notchhub-neo-ui-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("assets"), withIntermediateDirectories: true)
        for (name, text) in files {
            try text.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        return folder
    }

    @Test("serves a file from the folder as neo://app/…, with its type")
    @MainActor
    func serves() throws {
        let folder = try Self.folder(["index.html": "<html>neo</html>", "assets/app.js": "console.log(1)", "assets/app.css": "body{}"])
        defer { try? FileManager.default.removeItem(at: folder) }
        let handler = NeoSchemeHandler(folder: folder)
        let web = WKWebView(frame: .zero)

        let index = RecordingTask("neo://app/index.html")
        handler.webView(web, start: index)
        #expect(index.finished && index.error == nil)
        #expect(String(data: index.data, encoding: .utf8) == "<html>neo</html>")
        #expect((index.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") == "text/html")

        let root = RecordingTask("neo://app/")
        handler.webView(web, start: root)
        #expect(String(data: root.data, encoding: .utf8) == "<html>neo</html>")

        let script = RecordingTask("neo://app/assets/app.js")
        handler.webView(web, start: script)
        #expect((script.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") == "text/javascript")
        let style = RecordingTask("neo://app/assets/app.css?v=1")
        handler.webView(web, start: style)
        #expect(String(data: style.data, encoding: .utf8) == "body{}")
    }

    @Test("refuses what is not under the folder, hidden files, other hosts, and anything but GET")
    @MainActor
    func refuses() throws {
        let folder = try Self.folder(["index.html": "x", ".secret": "y"])
        defer { try? FileManager.default.removeItem(at: folder) }
        let handler = NeoSchemeHandler(folder: folder)
        #expect(handler.fileURL(for: URL(string: "neo://app/../ws-token")!) == nil)
        #expect(handler.fileURL(for: URL(string: "neo://app/assets/../../ws-token")!) == nil)
        #expect(handler.fileURL(for: URL(string: "neo://app/.secret")!) == nil)
        #expect(handler.fileURL(for: URL(string: "neo://evil/index.html")!) == nil)
        #expect(handler.fileURL(for: URL(string: "https://app/index.html")!) == nil)
        #expect(handler.fileURL(for: URL(string: "neo://app/index.html")!) == folder.standardizedFileURL.appendingPathComponent("index.html"))

        let web = WKWebView(frame: .zero)
        let missing = RecordingTask("neo://app/nope.js")
        handler.webView(web, start: missing)
        #expect(missing.error != nil && !missing.finished)
        let post = RecordingTask("neo://app/index.html", method: "POST")
        handler.webView(web, start: post)
        #expect(post.error != nil && !post.finished)
    }

    @Test("the installed page is found by its index.html, and nothing else counts")
    func bundle() throws {
        let folder = try Self.folder([:])
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(NeoUIBundle.installedFolder(folder) == nil)
        try "x".write(to: folder.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        #expect(NeoUIBundle.installedFolder(folder) == folder)
        #expect(NeoUIBundle.defaultFolder.path.hasSuffix("/Library/Application Support/NEO/ui"))
    }

    @Test("the host script injects the host, the token and the area; a token cannot escape its string")
    func script() {
        let source = NeoHostScript.source(token: "abc\"; alert(1); //", maxPage: CGSize(width: 1000, height: 960))
        #expect(source.contains(#"window.__NEO_HOST__ = "notch";"#))
        #expect(source.contains(#"window.__NEO_WS_TOKEN__ = "abc\"; alert(1); \/\/";"#) || source.contains(#"window.__NEO_WS_TOKEN__ = "abc\"; alert(1); //";"#))
        #expect(source.contains("window.__NEO_HOST_AREA__ = { w: 1000, h: 960 };"))
        #expect(NeoHostScript.emit("neo://wake") == #"window.__neoHostEmit && window.__neoHostEmit("neo:\/\/wake");"# || NeoHostScript.emit("neo://wake") == #"window.__neoHostEmit && window.__neoHostEmit("neo://wake");"#)
        #expect(NeoSchemeHandler.origin == "neo://app")
        #expect(NeoSchemeHandler.indexURL.absoluteString == "neo://app/index.html")
    }
}

/// NEO's REAL built page (`ui/dist`, pointed at by `NOTCHHUB_NEO_DIST`)
/// booting under the scheme handler with the host script: the bundle's
/// module scripts load from `neo://app/assets/…`, the page takes the notch
/// host and theme, renders its chat (never its pill), and raises no script
/// error. `WebSocket` is stubbed before the page runs, so the test never
/// reaches a core — least of all the real one on 8765.
enum NeoBuiltPage {
    static let dist: URL? = {
        guard let path = ProcessInfo.processInfo.environment["NOTCHHUB_NEO_DIST"] else { return nil }
        return NeoUIBundle.installedFolder(URL(fileURLWithPath: path, isDirectory: true))
    }()
}

@Suite("NEO's built page in the notch", .enabled(if: NeoBuiltPage.dist != nil))
struct NeoBuiltPageTests {

    @Test("boots from neo://app/, in notch mode, with no errors and no socket")
    @MainActor
    func boots() async throws {
        let folder = try #require(NeoBuiltPage.dist)
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(NeoSchemeHandler(folder: folder), forURLScheme: NeoSchemeHandler.scheme)
        configuration.userContentController.addUserScript(WKUserScript(
            source: NeoHostScript.source(token: String(repeating: "ab", count: 32), maxPage: CGSize(width: 760, height: 640)),
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.userContentController.addUserScript(WKUserScript(source: """
            window.__errors = []; window.__sockets = [];
            window.addEventListener("error", (e) => window.__errors.push(String(e.message)));
            window.addEventListener("unhandledrejection", (e) => window.__errors.push("rejection: " + String(e.reason)));
            window.WebSocket = class { constructor(url) { window.__sockets.push(url); this.readyState = 0; } send() {} close() {} };
            window.WebSocket.OPEN = 1;
            """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 420, height: 520), configuration: configuration)
        web.load(URLRequest(url: NeoSchemeHandler.indexURL))

        func js(_ source: String) async -> Any? {
            await withCheckedContinuation { continuation in
                web.evaluateJavaScript(source) { value, _ in continuation.resume(returning: value) }
            }
        }
        let deadline = Date().addingTimeInterval(8)
        var rendered = false
        while Date() < deadline, !rendered {
            try await Task.sleep(nanoseconds: 100_000_000)
            rendered = (await js("!!document.querySelector('#root .card')") as? Bool) ?? false
        }
        #expect(rendered, "the chat card rendered")
        #expect(await js("document.documentElement.dataset.host") as? String == "notch")
        #expect(await js("!!document.querySelector('.pill')") as? Bool == false)
        #expect(await js("!!document.querySelector('.input-row input')") as? Bool == true)
        #expect(await js("document.documentElement.dataset.sim") as? String == nil)
        #expect(await js("JSON.stringify(window.__errors)") as? String == "[]")
        // It reached for its socket with the injected token, and for nothing else.
        let sockets = await js("JSON.stringify(window.__sockets)") as? String ?? ""
        #expect(sockets.contains("ws://127.0.0.1:8765/?token=\(String(repeating: "ab", count: 32))"), Comment(rawValue: sockets))
        web.stopLoading()
    }
}
