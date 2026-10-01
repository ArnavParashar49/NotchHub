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
