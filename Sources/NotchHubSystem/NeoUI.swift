import Foundation
import NotchHubCore
import WebKit

/// NEO's built UI — the page NEO.app shows in its own window — as installed
/// for the notch.
///
/// NEO.app embeds its page in its binary, where nothing else can read it, so
/// NEO's `scripts/install-app.sh` also puts a copy of `ui/dist` beside NEO's
/// runtime: `~/Library/Application Support/NEO/ui/`. That folder is the whole
/// of what NotchHub needs to show NEO; without it the lane still works and
/// the panel simply does not exist.
public enum NeoUIBundle {
    /// Where NEO's install script puts the page.
    public static let installFolder = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Application Support/NEO/ui", isDirectory: true)
    /// `NOTCHHUB_NEO_DIST=<folder>` serves that build of NEO's page instead
    /// (a `ui/dist` under work, before it is installed): a debug aid, read
    /// once at launch, never written.
    public static let overrideVariable = "NOTCHHUB_NEO_DIST"
    /// The folder NotchHub looks in: the override when set, else the install.
    public static let defaultFolder: URL = overriddenFolder(ProcessInfo.processInfo.environment) ?? installFolder

    static func overriddenFolder(_ environment: [String: String]) -> URL? {
        guard let path = environment[overrideVariable], !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    /// The folder holding NEO's page, or `nil` when it is not installed — or
    /// when the page failed to load this run (`disableForThisRun`).
    public static func installedFolder(_ folder: URL = defaultFolder) -> URL? {
        guard !isDisabledForThisRun else { return nil }
        return FileManager.default.isReadableFile(atPath: folder.appendingPathComponent("index.html").path) ? folder : nil
    }

    /// Whether the page is off for the rest of this run: it failed to load,
    /// so NotchHub behaves as if it were not installed — the lane alone, and
    /// NEO's own window handed back — rather than showing an empty panel.
    public private(set) static var isDisabledForThisRun = false

    public static func disableForThisRun() {
        isDisabledForThisRun = true
    }
}

/// Serves NEO's page to a `WKWebView` from a folder, as `neo://app/…`.
///
/// A custom scheme rather than `file://`: a file URL has a null origin, and
/// NEO's core admits websocket clients by Origin. A page at `neo://app/` has
/// the origin `neo://app`, which the core's allowlist names — exactly that,
/// so nothing else served from the scheme (there is nothing else) gets in.
/// Only files under the folder are served: a path that climbs out of it is
/// refused, as is anything but a plain GET.
public final class NeoSchemeHandler: NSObject, WKURLSchemeHandler {
    public static let scheme = "neo"
    public static let host = "app"
    /// The page's own origin, as the core's allowlist knows it.
    public static let origin = "\(scheme)://\(host)"
    /// Where the page starts.
    public static let indexURL = URL(string: "\(origin)/index.html")!

    private let folder: URL

    public init(folder: URL) {
        self.folder = folder.standardizedFileURL
    }

    /// The file a request maps to, or `nil` for one that must be refused.
    public func fileURL(for url: URL) -> URL? {
        guard url.scheme == Self.scheme, url.host == Self.host else { return nil }
        var path = url.path
        if path.isEmpty || path == "/" { path = "/index.html" }
        // No climbing out, no hidden files, no empty segments.
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard !parts.isEmpty, parts.allSatisfy({ $0 != ".." && !$0.hasPrefix(".") }) else { return nil }
        let file = folder.appendingPathComponent(parts.joined(separator: "/")).standardizedFileURL
        guard file.path.hasPrefix(folder.path + "/") else { return nil }
        return file
    }

    /// The content type for a served file.
    public static func mimeType(for file: URL) -> String {
        switch file.pathExtension.lowercased() {
        case "html", "htm": return "text/html"
        case "js", "mjs": return "text/javascript"
        case "css": return "text/css"
        case "json", "map": return "application/json"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "ico": return "image/x-icon"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "ttf": return "font/ttf"
        case "wasm": return "application/wasm"
        case "txt": return "text/plain"
        default: return "application/octet-stream"
        }
    }

    public func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, task.request.httpMethod ?? "GET" == "GET",
              let file = fileURL(for: url), let data = FileManager.default.contents(atPath: file.path) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": Self.mimeType(for: file), "Content-Length": "\(data.count)", "Cache-Control": "no-store"]
        )!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    public func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        // Every response is delivered whole before `start` returns: nothing to stop.
    }
}

/// What the host tells NEO's page before any of its scripts run — see
/// `ui/src/host.ts` in NEO: the host's name, the core's token, and the most
/// room the panel can give the page.
public enum NeoHostScript {
    /// The script, with every value JSON-encoded so a token can never break
    /// out of its string.
    public static func source(token: String, maxPage: CGSize) -> String {
        """
        window.__NEO_HOST__ = "notch";
        window.__NEO_WS_TOKEN__ = \(json(token));
        window.__NEO_HOST_AREA__ = { w: \(Int(maxPage.width)), h: \(Int(maxPage.height)) };
        """
    }

    /// The JavaScript that hands the page a host event (`neo://wake`…).
    public static func emit(_ event: String) -> String {
        "window.__neoHostEmit && window.__neoHostEmit(\(json(event)));"
    }

    static func json(_ string: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [string])
        let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        return String(text.dropFirst().dropLast())
    }
}
