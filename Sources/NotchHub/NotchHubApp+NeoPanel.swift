import AppKit
import NotchHubCore
import NotchHubSystem
import SwiftUI

/// NEO's panel: its whole chat, expanding down from the notch.
///
/// `NeoPanelModel` decides whether it is open (it opens as NEO starts
/// answering or a card opens, folds 5 s after NEO is quiet, and follows the
/// user's clicks and Esc); `applyNeoPanel` makes the island match it. The
/// model takes NEO's state from the lane's own hold, so the lane and the
/// panel can never disagree about what NEO is doing. The panel exists only
/// when NEO's page is installed (`NeoUIBundle`): without it the lane is all
/// there is, and the core is never told NEO's UI moved.
extension NotchHubApp {

    /// Where NEO's page is, or `nil` — then there is no panel.
    var neoUIFolder: URL? { NeoUIBundle.installedFolder() }
    var hasNeoUI: Bool { neoUIFolder != nil }

    /// The web view with NEO's page, made on first use and kept.
    func neoWebHost() -> NeoWebHost? {
        if let neoWeb { return neoWeb }
        guard let folder = neoUIFolder, let token = NeoListener.readToken(at: NeoListener.defaultTokenFile) else { return nil }
        let host = NeoWebHost(folder: folder, token: token, maxPage: NeoPanelLayout.maxPageSize(screen: window.screenSize))
        host.onMessage = { [weak self] message in self?.neoHostMessage(message) }
        neoWeb = host
        log("neo: page loaded from \(folder.path)")
        return host
    }

    /// Makes the island match the model: takes the island for the panel when
    /// it opened, gives it back when it closed.
    func applyNeoPanel() {
        let shouldOpen = neoPanel.isOpen && featureSettings.isEnabled(.neo) && hasNeoUI
        if shouldOpen, panel != .neo {
            guard neoWebHost() != nil else { return }
            takePanel(.neo)
            renderIsland()
            log("neo: panel open")
        } else if !shouldOpen, panel == .neo {
            closePanel()
            log("neo: panel closed")
        }
    }

    func neoPanelContent() -> AnyView {
        guard let host = neoWebHost() else { return AnyView(EmptyView()) }
        return AnyView(NeoPanelView(webView: host.webView))
    }

    /// The page size the panel gives right now.
    var neoPageSize: CGSize {
        NeoPanelLayout.pageSize(requested: neoPanelRequest, screen: window.screenSize)
    }

    // MARK: - From the page

    func neoHostMessage(_ message: NeoHostMessage) {
        let now = Date()
        switch message {
        case .show:
            neoPanel.show(at: now)
            applyNeoPanel()
        case .collapse:
            neoPanel.close(at: now)
            applyNeoPanel()
        case .focus:
            neoEngageKeyboard()
        case let .openURL(url):
            NSWorkspace.shared.open(url)
        case let .clipboard(text):
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        case let .size(size):
            guard size != neoPanelRequest else { return }
            neoPanelRequest = size
            if panel == .neo { renderIsland() }
        case let .pin(on):
            neoPanel.pin(on, at: now)
        }
        scheduleNeoWake(neoNextWake(at: now))
    }

    /// Gives the page the keyboard: the window becomes key (as for the
    /// settings panel) and the web view takes first responder, so typing
    /// lands in NEO's input. Only ever at the user's own hand — a click on
    /// the lane or into the panel, or the page asking on a click — never
    /// because NEO started talking, which must not steal what you are typing.
    func neoEngageKeyboard() {
        guard panel == .neo, let host = neoWeb else { return }
        window.needsInteraction = true
        window.makeFirstResponder(host.webView)
    }

    // MARK: - From the island

    /// The cursor entered or left the island while the panel is open.
    func neoPanelHover(_ inside: Bool) {
        guard panel == .neo || neoPanel.isHovered != inside else { return }
        let now = Date()
        neoPanel.hover(inside, at: now)
        scheduleNeoWake(neoNextWake(at: now))
    }

    /// A click on the lane (the orb and its line) toggles the panel; a click
    /// on the open panel's notch strip beside it does the same. Returns
    /// whether the click was the lane's.
    func neoLaneControlHit(at point: NSPoint) -> Bool {
        guard featureSettings.isEnabled(.neo), hasNeoUI else { return false }
        guard let rect = neoLaneRect(), rect.contains(point) else { return false }
        let now = Date()
        neoPanel.toggle(at: now)
        applyNeoPanel()
        if neoPanel.isOpen { neoEngageKeyboard() }
        scheduleNeoWake(neoNextWake(at: now))
        log("neo: lane clicked → \(neoPanel.isOpen ? "open" : "closed")")
        return true
    }

    /// The lane's rectangle in window coordinates, while it shows.
    func neoLaneRect() -> CGRect? {
        let content = islandModel.contentSize
        guard content.neoLead > 0 else { return nil }
        let notch = window.localFrame(for: .idle, content: .default)
        return CGRect(x: notch.minX - content.neoLead, y: notch.minY, width: content.neoLead, height: notch.height)
    }

    /// Esc with the panel open and the island itself first responder.
    func closeNeoPanel() {
        guard panel == .neo else { return }
        let now = Date()
        neoPanel.close(at: now)
        applyNeoPanel()
        scheduleNeoWake(neoNextWake(at: now))
    }

    /// The earlier of the lane's and the panel's next change.
    func neoNextWake(at now: Date) -> Date? {
        [neoLane.nextWake(at: now), neoPanel.nextWake(at: now)].compactMap { $0 }.min()
    }
}
