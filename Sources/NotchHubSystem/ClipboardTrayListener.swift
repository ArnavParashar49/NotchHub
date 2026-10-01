import AppKit
import NotchHubCore

/// Watches the pasteboard and turns new copies into `TrayClip`s.
///
/// Emits one `clipboardCaptured` event per new copy.
///
/// TEXT ONLY, deliberately. The Tray is clipboard storage and nothing else: a
/// copy that is not a string is ignored outright, so nothing is written to disk
/// but the text you copied, and no image is ever read, recognised or kept.
///
/// The main thread only compares `changeCount`. Reading a copy's CONTENTS can
/// wait on the system: macOS 15.4+ asks "Allow Paste?" before an app reads the
/// clipboard (a new Mac starts at "ask"), and sizing a copied file can raise a
/// Files & Folders prompt. So contents are read on `readQueue`, never on main.
final class ClipboardTrayListener: SystemListener {

    private let emit: (SystemEvent) -> Void
    private var timer: Timer?
    private var lastChangeCount: Int
    private let readQueue = DispatchQueue(label: "notchhub.tray.read", qos: .userInitiated)

    init(emit: @escaping (SystemEvent) -> Void) {
        self.emit = emit
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    var name: String { "ClipboardTray" }

    func start() {
        stop()
        lastChangeCount = NSPasteboard.general.changeCount
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Poll

    /// Main thread, every 0.5 s: only the cheap change counter.
    private func poll() {
        let change = NSPasteboard.general.changeCount
        guard change != lastChangeCount else { return }
        lastChangeCount = change
        let frontmost = NSWorkspace.shared.frontmostApplication
        let sourceID = frontmost?.bundleIdentifier
        let sourceName = frontmost?.localizedName
        readQueue.async { [weak self] in
            self?.capture(change: change, sourceID: sourceID, sourceName: sourceName)
        }
    }

    /// `readQueue`: reads and records one copy.
    private func capture(change: Int, sourceID: String?, sourceName: String?) {
        let pasteboard = NSPasteboard.general
        // A newer copy already replaced this one; its own poll reads it.
        guard pasteboard.changeCount == change else { return }
        if #available(macOS 15.4, *), pasteboard.accessBehavior == .alwaysDeny { return }
        let types = (pasteboard.types ?? []).map(\.rawValue)
        guard !ClipboardPrivacy.shouldIgnore(types: types, sourceBundleID: sourceID) else {
            // A password manager's copy: never recorded, never written to disk.
            return
        }
        guard let clip = classify(pasteboard, sourceID: sourceID, sourceName: sourceName) else { return }
        emit(SystemEvent(source: .clipboard, payload: .clipboardCaptured(clip)))
    }

    // MARK: - Classification

    /// A copied string, or nothing at all.
    ///
    /// An image or a file copy is not stored — not as a thumbnail, not as a
    /// path, not at all. Reading one would mean writing it somewhere, and the
    /// Tray keeps only text.
    private func classify(_ pasteboard: NSPasteboard, sourceID: String?, sourceName: String?) -> TrayClip? {
        guard let string = pasteboard.string(forType: .string), !string.isEmpty else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return TrayClip(
            kind: Self.classifyText(trimmed),
            text: trimmed,
            byteSize: string.utf8.count,
            sourceApp: sourceName
        )
    }

    /// Decides whether a string is a link, a color, or plain text.
    private static func classifyText(_ string: String) -> ClipKind {
        if string.range(of: #"^https?://"#, options: .regularExpression) != nil
            || string.hasPrefix("www.")
            || string.range(of: #"^#?([0-9a-fA-F]{6}|[0-9a-fA-F]{3})$"#, options: .regularExpression) != nil {
            if string.range(of: #"^#?([0-9a-fA-F]{6}|[0-9a-fA-F]{3})$"#, options: .regularExpression) != nil {
                return .color
            }
            return .link
        }
        return .text
    }
}
