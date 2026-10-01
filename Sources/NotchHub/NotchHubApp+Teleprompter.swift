import AppKit
import NotchHubCore
import SwiftUI
import UniformTypeIdentifiers

/// The teleprompter: a script that scrolls itself past the notch while you read.
///
/// Two modes, and they want opposite things from the window. COMPOSING has a
/// real text editor, so the island takes key focus like the settings panel.
/// READING must never take focus — you are presenting from another app — so its
/// controls are drawn and the window hit-tests them, exactly like the
/// dashboard's. `applyTeleprompterFocus` is the single place that switches
/// between the two, so the two modes can never disagree about it.
extension NotchHubApp {

    // MARK: - Opening and closing

    /// Opens the teleprompter, or closes it if it is already showing.
    func toggleTeleprompter() {
        if panel == .teleprompter {
            closeTeleprompter()
            return
        }
        guard featureSettings.isEnabled(.teleprompter) else {
            log("teleprompter: disabled by settings")
            return
        }
        // A script from an earlier session is kept, so re-opening picks up where
        // it was left — but it always opens paused, never mid-scroll.
        teleprompter.pause()
        teleprompter.mode = teleprompter.hasScript ? .running : .compose
        takePanel(.teleprompter)
        applyTeleprompterFocus()
        log("teleprompter: open (\(teleprompter.mode == .compose ? "compose" : "read"))")
        refreshPanel()
    }

    func closeTeleprompter() {
        guard panel == .teleprompter else { return }
        // Stop scrolling, but keep the script and the position: closing is not
        // the same as discarding, and re-opening should resume the same take.
        teleprompter.pause()
        pendingTeleprompterRefresh?.cancel()
        pendingTeleprompterRefresh = nil
        closePanel()
        log("teleprompter: closed")
    }

    /// Gives the window key focus only while the editor needs it.
    func applyTeleprompterFocus() {
        window.needsInteraction = panel == .teleprompter && teleprompter.mode == .compose
    }

    /// The shape the teleprompter takes right now.
    var teleprompterState: IslandState {
        teleprompter.mode == .compose ? .teleprompterCompose : .teleprompter
    }

    // MARK: - Content

    func teleprompterContent() -> AnyView {
        switch teleprompter.mode {
        case .compose:
            return AnyView(TeleprompterComposeView(
                script: Binding(
                    get: { [weak self] in self?.teleprompter.script ?? "" },
                    set: { [weak self] text in
                        guard let self else { return }
                        // `load` rewinds; typing must not. Only the text changes.
                        self.teleprompter.script = text
                        self.refreshPanel()
                    }
                ),
                onStart: { [weak self] in self?.startTeleprompter() },
                onOpenFile: { [weak self] in self?.openTeleprompterFile() },
                onPaste: { [weak self] in self?.pasteTeleprompterScript() },
                onClose: { [weak self] in self?.closeTeleprompter() }
            ))
        case .running:
            let size = window.localFrame(for: .teleprompter, content: .default).size
            return AnyView(TeleprompterView(
                state: teleprompter,
                notchInset: window.notchHeight,
                size: size,
                onMeasure: { [weak self] distance in
                    self?.recordTeleprompterDistance(distance)
                }
            ))
        }
    }

    /// The view measured the script: how far it can scroll before its last line
    /// reaches the focus band.
    ///
    /// The view holds a SNAPSHOT of the state, so the measurement has to be fed
    /// back through a render or the prompter would keep the stale distance —
    /// scrolling past the end of the script for ever and reporting no progress.
    /// Two things keep that from looping: the value is only taken when it has
    /// really changed (a re-render measures the same text and reports the same
    /// number, which stops here), and the render is deferred off the layout pass
    /// that produced it rather than re-entering SwiftUI from inside itself.
    func recordTeleprompterDistance(_ distance: Double) {
        guard abs(teleprompter.scrollDistance - distance) > 0.5 else { return }
        teleprompter.scrollDistance = distance
        guard panel == .teleprompter, teleprompter.mode == .running else { return }
        pendingTeleprompterRefresh?.cancel()
        pendingTeleprompterRefresh = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self, self.panel == .teleprompter else { return }
            self.pendingTeleprompterRefresh = nil
            self.refreshPanel()
        }
    }

    // MARK: - Transport

    /// Leaves compose mode and starts reading.
    func startTeleprompter() {
        guard teleprompter.hasScript else { return }
        teleprompter.mode = .running
        teleprompter.restart()
        teleprompter.play()
        applyTeleprompterFocus()
        log("teleprompter: start")
        refreshPanel()
    }

    /// Handles a click on the reading controls. A miss falls through to the
    /// island click.
    func teleprompterControlHit(at point: NSPoint) -> Bool {
        guard panel == .teleprompter, teleprompter.mode == .running else { return false }
        let frame = window.localFrame(for: .teleprompter, content: .default)
        guard let action = TeleprompterLayout.action(at: point, in: frame) else { return false }
        log("teleprompter: \(action)")
        switch action {
        case .playPause:
            teleprompter.togglePlaying()
        case .restart:
            teleprompter.restart()
        case .slower:
            teleprompter.slower()
        case .faster:
            teleprompter.faster()
        case .edit:
            teleprompter.edit()
            applyTeleprompterFocus()
        case .close:
            closeTeleprompter()
            return true
        }
        refreshPanel()
        return true
    }

    // MARK: - Loading a script

    /// Types a plain-text or Markdown file can be read from.
    static let teleprompterFileTypes: [UTType] = [.plainText, .utf8PlainText, .text, .rtf]

    /// Opens a script from disk.
    ///
    /// An `NSOpenPanel` rather than a drop target: the island's drop zone
    /// already belongs to file sharing, and quietly changing what a dropped file
    /// does depending on which panel happens to be open would be worse than one
    /// honest button.
    func openTeleprompterFile() {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.allowedContentTypes = Self.teleprompterFileTypes
        openPanel.prompt = "Open Script"
        openPanel.message = "Choose a text file to read from."
        // The island is already key while composing, so the sheet has a parent.
        openPanel.begin { [weak self] response in
            guard let self, response == .OK, let url = openPanel.url else { return }
            self.loadTeleprompterScript(from: url)
        }
    }

    func loadTeleprompterScript(from url: URL) {
        guard let text = Self.readScript(at: url) else {
            log("teleprompter: could not read \(url.lastPathComponent)")
            return
        }
        teleprompter.load(text)
        log("teleprompter: loaded \(url.lastPathComponent) (\(text.count) characters)")
        refreshPanel()
    }

    /// Reads a script file as text, falling back through the encodings a plain
    /// text file is realistically saved in. An RTF file is unwrapped to its
    /// words — pasting a formatted script is common, and its markup is not
    /// something anyone wants to read aloud.
    static func readScript(at url: URL) -> String? {
        if url.pathExtension.lowercased() == "rtf",
           let attributed = try? NSAttributedString(
               url: url,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil
           ) {
            return attributed.string
        }
        if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        var encoding = String.Encoding.utf8
        return try? String(contentsOf: url, usedEncoding: &encoding)
    }

    /// Takes the script straight off the clipboard — the fastest way in, and the
    /// one people reach for first.
    func pasteTeleprompterScript() {
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            log("teleprompter: nothing on the clipboard")
            return
        }
        teleprompter.load(text)
        log("teleprompter: pasted \(text.count) characters")
        refreshPanel()
    }
}
