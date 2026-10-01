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
        host.onFailure = { [weak self] reason in self?.neoPageFailed(reason) }
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
            // Straight back to the island's resting shape, as if the panel had
            // been an activity that ended — not a bare compact bar waiting for
            // the next tick to tuck it in.
            renderQueue()
            log("neo: panel closed")
        }
    }

    /// NEO's page could not load: for the rest of this run NotchHub behaves
    /// as if the page were not installed — the panel closes and never opens,
    /// the lane goes on, and the listener is restarted without the UI so it
    /// hands NEO its own window back (`ui_host window`). One log line.
    func neoPageFailed(_ reason: String) {
        log("neo: page \(reason) — the panel is off for this run")
        NeoUIBundle.disableForThisRun()
        neoWeb = nil
        neoPanel.close(at: Date())
        applyNeoPanel()
        monitor?.restart { $0 is NeoListener }
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
        // The page puts the keys in its input (`neo://show`: NEO's page
        // expands as it does in its own window, without a wake).
        host.emit("neo://show")
    }

    // MARK: - From the island

    /// The cursor entered or left the island while the panel is open.
    func neoPanelHover(_ inside: Bool) {
        guard panel == .neo || neoPanel.isHovered != inside else { return }
        let now = Date()
        neoPanel.hover(inside, at: now)
        scheduleNeoWake(neoNextWake(at: now))
    }

    /// While NEO is active (its orb out of the notch) a click ANYWHERE on
    /// the island opens NEO's chat — the island is NEO's door, not only the
    /// orb; with NEO tucked in, clicks keep the island's own meaning. With
    /// the panel open, a click on the lane in its strip closes it (the rest
    /// of the panel is the page's). See `NeoIslandClick`. Returns whether
    /// the click was NEO's.
    func neoIslandClickHit(at point: NSPoint) -> Bool {
        guard featureSettings.isEnabled(.neo), hasNeoUI else { return false }
        let content = islandModel.contentSize
        let island = window.localFrame(for: currentIslandState(), content: content)
        let lane = NeoLaneLayout.rect(in: island, width: content.neoLead, notchHeight: window.notchHeight)
        let outcome = NeoIslandClick.outcome(
            laneShown: content.neoLead > 0, panelOpen: panel == .neo, otherPanel: panel != .none && panel != .neo,
            point: point, laneRect: lane
        )
        let now = Date()
        switch outcome {
        case .none:
            return false
        case .open:
            neoPanel.show(at: now)
            applyNeoPanel()
            neoEngageKeyboard()
        case .close:
            neoPanel.close(at: now)
            applyNeoPanel()
        }
        scheduleNeoWake(neoNextWake(at: now))
        log("neo: island clicked → \(neoPanel.isOpen ? "open" : "closed")")
        return true
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
