import AppKit
import NotchHubCore
import NotchHubSystem
import SwiftUI

/// NEO's panel: its whole chat, expanding down from the notch.
///
/// `NeoPanelModel` decides whether it is open (it opens when NEO needs the
/// user or a card opens, on a click on the island while NEO is active, folds
/// 5 s after NEO is quiet, and follows Esc); `applyNeoPanel` makes the
/// island match it. The model takes NEO's state from the presence's own
/// hold, so the pet and the panel can never disagree about what NEO is doing. The panel exists only
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
            log("neo: closing — open=\(neoPanel.isOpen) waiting=\(neoPanel.isWaitingForCore) feature=\(featureSettings.isEnabled(.neo)) ui=\(hasNeoUI)")
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
            // The page asks to be seen whenever a question comes up on its
            // card. A confirmation is the island's own Allow / Cancel now:
            // while one waits the chat stays folded.
            guard neoConfirm.pageAsksToShow(at: now) else {
                log("neo: the page asked to show — declined, the buttons are up")
                break
            }
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

    /// While NEO is active (the pet is NEO, and it is busy) a click ANYWHERE
    /// on the island — the pet included — opens NEO's chat: the island is
    /// NEO's door. With NEO idle, clicks keep the island's own meaning (the
    /// pet's own panel among them). See `NeoIslandClick`. Returns whether
    /// the click was NEO's.
    func neoIslandClickHit(at point: NSPoint) -> Bool {
        guard hasNeoUI else { return false }
        let now = Date()
        let outcome = NeoIslandClick.outcome(
            neoActive: neoActive(at: now), panelOpen: panel == .neo, otherPanel: panel != .none && panel != .neo
        )
        guard outcome == .open else { return false }
        neoConfirm.userOpenedChat()
        neoPanel.show(at: now)
        applyNeoPanel()
        neoEngageKeyboard()
        scheduleNeoWake(neoNextWake(at: now))
        log("neo: island clicked → open")
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

    // MARK: - Debug snapshots

    /// The folder `NOTCHHUB_NEO_SNAPSHOTS` names, when it does.
    static let neoSnapshotVariable = "NOTCHHUB_NEO_SNAPSHOTS"

    /// With `NOTCHHUB_NEO_SNAPSHOTS=<dir>` in the environment, SIGUSR1 writes
    /// the page as it is in the open panel to `<dir>/neo-panel-<time>.png`
    /// (the web view's own snapshot, at the page's size, in points × scale).
    /// Nothing is read or written otherwise, and the signal is left alone.
    func installNeoSnapshotSignal() {
        guard let dir = ProcessInfo.processInfo.environment[Self.neoSnapshotVariable], !dir.isEmpty else { return }
        signal(SIGUSR1, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        source.setEventHandler { [weak self] in self?.snapshotNeoPanel(into: URL(fileURLWithPath: dir, isDirectory: true)) }
        source.resume()
        neoSnapshotSignal = source
        log("neo: SIGUSR1 snapshots the panel's page into \(dir)")
    }

    func snapshotNeoPanel(into folder: URL) {
        guard panel == .neo, let host = neoWeb else {
            log("neo: snapshot asked, but the panel is not open")
            return
        }
        let size = neoPageSize
        if let w = host.webView.window {
            log("neo: window visible=\(w.isVisible) occluded=\(!w.occlusionState.contains(.visible)) key=\(w.isKeyWindow) sharing=\(w.sharingType.rawValue) alpha=\(w.alphaValue) level=\(w.level.rawValue) hiddenView=\(host.webView.isHiddenOrHasHiddenAncestor) frame=\(host.webView.frame) winFrame=\(w.frame)")
        } else {
            log("neo: the web view has no window")
        }
        // What the page holds beside the picture: its layout, the log's rows and scroll, and
        // whether WebKit counts it visible (it must: see NeoWebHost's occlusion note).
        host.webView.evaluateJavaScript("""
            (() => { const l = document.querySelector('.log'); const c = document.querySelector('.card');
              return JSON.stringify({ card: c && c.className, vis: document.visibilityState, rows: l ? l.children.length : -1,
                scroll: l ? [l.scrollTop, l.scrollHeight, l.clientHeight] : null, text: (l ? l.innerText : document.body.innerText).slice(0, 120) }); })()
            """) { [weak self] value, _ in self?.log("neo: page \(value.map { String(describing: $0) } ?? "?")") }
        host.webView.takeSnapshot(with: nil) { [weak self] image, error in
            guard let image, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else {
                self?.log("neo: snapshot failed: \(error?.localizedDescription ?? "no image")")
                return
            }
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let file = folder.appendingPathComponent("neo-panel-\(stamp).png")
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try png.write(to: file)
                self?.log("neo: snapshot \(Int(size.width))×\(Int(size.height)) → \(file.path)")
            } catch {
                self?.log("neo: snapshot not written: \(error.localizedDescription)")
            }
        }
    }

    /// The earliest of NEO's presence, panel and legacy pulse model.
    func neoNextWake(at now: Date) -> Date? {
        [neoPresence.nextWake(at: now), neoPanel.nextWake(at: now), neoListening.nextWake(at: now)].compactMap { $0 }.min()
    }
}
