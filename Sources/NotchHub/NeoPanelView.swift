import AppKit
import NotchHubCore
import NotchHubSystem
import SwiftUI
import WebKit

/// NEO's page in a `WKWebView`: the one NEO.app shows in its own window,
/// served from `neo://app/` (`NeoSchemeHandler`) with the host's values
/// injected before its scripts run (`NeoHostScript`). The page opens its own
/// websocket to NEO's core — with the token the host handed it, from the
/// origin `neo://app` the core admits — so the chat, the confirm buttons and
/// the browser, camera and song cards work exactly as in NEO's window; the
/// island's own listener stays what it was, the lane's source.
///
/// Created once and kept while the app runs, so the chat keeps its scroll
/// and the page its socket between openings; the panel merely shows or
/// hides it. The page talks to the host through `neo` messages
/// (`NeoHostMessage`) and hears from it through `emit`.
@MainActor
final class NeoWebHost: NSObject, WKNavigationDelegate, WKUIDelegate {

    let webView: WKWebView
    /// A message from the page, already parsed.
    var onMessage: ((NeoHostMessage) -> Void)?

    init(folder: URL, token: String, maxPage: CGSize) {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(NeoSchemeHandler(folder: folder), forURLScheme: NeoSchemeHandler.scheme)
        let content = WKUserContentController()
        content.addUserScript(WKUserScript(
            source: NeoHostScript.source(token: token, maxPage: maxPage),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        configuration.userContentController = content
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        // The content controller holds its handlers strongly: a proxy keeps
        // the host from retaining itself through its own web view.
        content.add(MessageProxy(host: self), name: "neo")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        // Black before the page paints, so the panel never flashes white.
        webView.underPageBackgroundColor = .black
        webView.setValue(false, forKey: "drawsBackground")
        webView.load(URLRequest(url: NeoSchemeHandler.indexURL))
    }

    /// Hands the page a host event (`neo://wake` …).
    func emit(_ event: String) {
        webView.evaluateJavaScript(NeoHostScript.emit(event)) { _, _ in }
    }

    fileprivate func received(_ body: Any) {
        guard let message = NeoHostMessage.parse(body) else {
            NotchLog.debug("neo: unparsable message from the page")
            return
        }
        onMessage?(message)
    }

    /// The page never navigates away: a link it did not route through the
    /// host (there are none) is dropped rather than loaded in the island.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, url.scheme == NeoSchemeHandler.scheme else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    /// `window.open` from the page: nothing to open it in.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        nil
    }

    private final class MessageProxy: NSObject, WKScriptMessageHandler {
        weak var host: NeoWebHost?
        init(host: NeoWebHost) { self.host = host }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            MainActor.assumeIsolated { host?.received(message.body) }
        }
    }
}

/// NEO's panel: the web view filling the island below the notch strip.
struct NeoPanelView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)
        return container
    }

    func updateNSView(_ view: NSView, context: Context) {
        if webView.superview !== view {
            webView.removeFromSuperview()
            webView.frame = view.bounds
            webView.autoresizingMask = [.width, .height]
            view.addSubview(webView)
        }
    }
}
