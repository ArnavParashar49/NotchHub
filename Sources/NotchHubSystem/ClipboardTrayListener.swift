import AppKit
import NotchHubCore

/// Watches the pasteboard and turns new copies into `TrayClip`s.
///
/// Emits one `clipboardCaptured` event per new copy. Image clips are OCR'd in
/// the background and re-emitted with the recovered text, so the Tray can show
/// what a screenshot says without ever blocking the pasteboard poll.
final class ClipboardTrayListener: SystemListener {

    private let emit: (SystemEvent) -> Void
    private var timer: Timer?
    private var lastChangeCount: Int
    private let ocrQueue = DispatchQueue(label: "notchhub.tray.ocr")

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

    private func poll() {
        let pasteboard = NSPasteboard.general
        let change = pasteboard.changeCount
        guard change != lastChangeCount else { return }
        lastChangeCount = change
        let types = (pasteboard.types ?? []).map(\.rawValue)
        let source = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard !ClipboardPrivacy.shouldIgnore(types: types, sourceBundleID: source) else {
            // A password manager's copy: never recorded, never written to disk.
            return
        }
        guard let clip = classify(pasteboard) else { return }
        emit(SystemEvent(source: .clipboard, payload: .clipboardCaptured(clip)))

        // Image clips get OCR'd off the hot path; the result arrives as a
        // second event carrying the same id, which the store merges in place.
        if clip.kind == .image || clip.kind == .screenshot, let path = clip.imagePath {
            ocrQueue.async { [weak self] in
                guard let self, let image = NSImage(contentsOfFile: path) else { return }
                let text = TrayOCR.recognizeText(in: image)
                guard !text.isEmpty else { return }
                var updated = clip
                updated.ocrText = text
                self.emit(SystemEvent(source: .clipboard, payload: .clipboardCaptured(updated)))
            }
        }
    }

    // MARK: - Classification

    private func classify(_ pasteboard: NSPasteboard) -> TrayClip? {
        let sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName

        // Image payloads win: they are the richest and rarest.
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            guard let path = TrayPersistence.saveImage(data) else { return nil }
            let isScreenshot = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.screencapture"
            return TrayClip(
                kind: isScreenshot ? .screenshot : .image,
                imagePath: path,
                byteSize: data.count,
                sourceApp: sourceApp
            )
        }

        // File URLs (Finder copies).
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            let paths = urls.map(\.path)
            let size = (try? FileManager.default.attributesOfItem(atPath: paths[0])[.size] as? Int) ?? nil
            return TrayClip(kind: .file, filePaths: paths, byteSize: size, sourceApp: sourceApp)
        }

        // Plain text.
        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let kind = Self.classifyText(trimmed)
            return TrayClip(kind: kind, text: trimmed, byteSize: string.utf8.count, sourceApp: sourceApp)
        }

        return nil
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
