import Foundation

/// What a clipboard entry actually is.
///
/// Classified once at capture time so the Tray can filter and search without
/// re-inspecting a payload it may no longer be able to read.
public enum ClipKind: String, CaseIterable, Codable, Equatable {
    case text
    case link
    case color
    case image
    case screenshot
    case file

    public var symbol: String {
        switch self {
        case .text: return "text.alignleft"
        case .link: return "link"
        case .color: return "paintpalette.fill"
        case .image: return "photo.fill"
        case .screenshot: return "camera.viewfinder"
        case .file: return "doc.fill"
        }
    }
}

/// One entry in the Tray.
///
/// Image payloads live on disk and are referenced by path — the Tray holds
/// sixty of these, so bytes never sit in memory.
public struct TrayClip: Identifiable, Equatable, Codable {
    public let id: UUID
    public var kind: ClipKind
    /// The text payload: the string itself for `.text`, the URL for `.link`,
    /// the hex value for `.color`.
    public var text: String?
    /// On-disk path for `.image` / `.screenshot` payloads.
    public var imagePath: String?
    /// Paths for `.file` clips.
    public var filePaths: [String]
    /// Text recovered from an image by OCR, when OCR ran.
    public var ocrText: String?
    /// Pinned clips are never evicted.
    public var pinned: Bool
    public let createdAt: Date
    /// Payload size in bytes, when known.
    public var byteSize: Int?
    /// The app the clip was copied from, when it can be determined.
    public var sourceApp: String?

    public init(
        id: UUID = UUID(),
        kind: ClipKind,
        text: String? = nil,
        imagePath: String? = nil,
        filePaths: [String] = [],
        ocrText: String? = nil,
        pinned: Bool = false,
        createdAt: Date = Date(),
        byteSize: Int? = nil,
        sourceApp: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.imagePath = imagePath
        self.filePaths = filePaths
        self.ocrText = ocrText
        self.pinned = pinned
        self.createdAt = createdAt
        self.byteSize = byteSize
        self.sourceApp = sourceApp
    }

    /// The line the Tray shows. OCR text stands in for images so a screenshot
    /// is recognisable without being rendered.
    public var displayTitle: String {
        switch kind {
        case .text:
            return Self.summarize(text) ?? "Text"
        case .link:
            return text ?? "Link"
        case .color:
            return text ?? "Color"
        case .image, .screenshot:
            if let ocr = Self.summarize(ocrText) { return ocr }
            return kind == .screenshot ? "Screenshot" : "Image"
        case .file:
            let names = filePaths.map { ($0 as NSString).lastPathComponent }
            if names.isEmpty { return "File" }
            return names.joined(separator: ", ")
        }
    }

    /// The quiet second line: where it came from and how big it is.
    public var displaySubtitle: String? {
        var parts: [String] = []
        if let sourceApp, !sourceApp.isEmpty { parts.append(sourceApp) }
        if let byteSize { parts.append(Self.byteLabel(byteSize)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Whether this clip's content (or its OCR text) contains `query`.
    ///
    /// Case- and diacritic-insensitive so "cafe" finds "Café".
    public func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        if let text, text.range(of: needle, options: options) != nil { return true }
        if let ocrText, ocrText.range(of: needle, options: options) != nil { return true }
        for path in filePaths where (path as NSString).lastPathComponent.range(of: needle, options: options) != nil {
            return true
        }
        return false
    }

    /// First meaningful line of a blob, collapsed to one line and clipped.
    private static func summarize(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let collapsed = raw
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard let collapsed, !collapsed.isEmpty else { return nil }
        return collapsed.count > 120 ? String(collapsed.prefix(120)) + "…" : collapsed
    }

    /// `1.2 MB`, `24 KB`, `812 B`.
    public static func byteLabel(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        if bytes < 1000 { return "\(bytes) B" }
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

/// The Tray's filter row.
public enum TrayFilter: String, CaseIterable, Equatable {
    case all
    case texts
    case links
    case images
    case screenshots
    case colors
    case files

    public var label: String {
        switch self {
        case .all: return "All"
        case .texts: return "Texts"
        case .links: return "Links"
        case .images: return "Images"
        case .screenshots: return "Screenshots"
        case .colors: return "Colors"
        case .files: return "Files"
        }
    }

    public func includes(_ clip: TrayClip) -> Bool {
        switch self {
        case .all: return true
        case .texts: return clip.kind == .text
        case .links: return clip.kind == .link
        case .images: return clip.kind == .image
        case .screenshots: return clip.kind == .screenshot
        case .colors: return clip.kind == .color
        case .files: return clip.kind == .file
        }
    }
}

/// The clipboard history: newest first, pinned clips kept forever, unpinned
/// capped at `capacity`.
///
/// Pure: it never touches `NSPasteboard` or the disk. The system layer feeds
/// it clips; the UI reads them back.
public final class TrayStore {
    /// How many unpinned clips are kept. Matches the product's "last 60 clips".
    public static let capacity = 60

    public private(set) var clips: [TrayClip] = []

    public init(clips: [TrayClip] = []) {
        self.clips = clips
        evict()
    }

    /// Adds a clip to the front, collapsing an immediately-repeated copy.
    ///
    /// Re-copying the same thing should refresh it, not add a twin.
    public func add(_ clip: TrayClip) {
        if let first = clips.first, sameCopy(first, clip) {
            clips.removeFirst()
        }
        clips.insert(clip, at: 0)
        evict()
    }

    /// Pins or unpins a clip. Pinned clips survive eviction and `clear()`.
    public func setPinned(id: UUID, pinned: Bool) {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        clips[index].pinned = pinned
    }

    public func setOCRText(id: UUID, text: String) {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        clips[index].ocrText = text
    }

    public func remove(id: UUID) {
        clips.removeAll { $0.id == id }
    }

    /// Empties the history of everything unpinned.
    public func clear() {
        clips.removeAll { !$0.pinned }
    }

    /// Brings a clip back to the front without duplicating it.
    public func moveToFront(id: UUID) {
        guard let index = clips.firstIndex(where: { $0.id == id }), index != 0 else { return }
        let clip = clips.remove(at: index)
        clips.insert(clip, at: 0)
    }

    /// Clips matching `query` within `filter`, newest first.
    ///
    /// Pinned clips sort ahead of unpinned ones of the same standing, so a clip
    /// you deliberately kept is always easy to find again.
    public func search(query: String = "", filter: TrayFilter = .all) -> [TrayClip] {
        clips
            .filter { filter.includes($0) && $0.matches(query) }
            .sorted { lhs, rhs in
                if lhs.pinned != rhs.pinned { return lhs.pinned }
                return lhs.createdAt > rhs.createdAt
            }
    }

    public var pinnedCount: Int { clips.filter(\.pinned).count }
    public var unpinnedCount: Int { clips.filter { !$0.pinned }.count }
    public var isEmpty: Bool { clips.isEmpty }

    // MARK: - Private

    private func sameCopy(_ lhs: TrayClip, _ rhs: TrayClip) -> Bool {
        guard lhs.kind == rhs.kind else { return false }
        switch rhs.kind {
        case .image, .screenshot:
            return lhs.imagePath != nil && lhs.imagePath == rhs.imagePath
        case .file:
            return !rhs.filePaths.isEmpty && lhs.filePaths == rhs.filePaths
        default:
            return lhs.text != nil && lhs.text == rhs.text
        }
    }

    /// Drops the oldest unpinned clips past `capacity`. Pinned clips are free.
    private func evict() {
        guard unpinnedCount > Self.capacity else { return }
        var toDrop = unpinnedCount - Self.capacity
        var kept: [TrayClip] = []
        for clip in clips.reversed() {
            if !clip.pinned && toDrop > 0 {
                toDrop -= 1
                continue
            }
            kept.append(clip)
        }
        clips = kept.reversed()
    }
}

// MARK: - Clipboard privacy

/// Decides which copies must never enter the Tray.
///
/// Password managers mark their copies with the nspasteboard.org marker types
/// precisely so clipboard histories skip them. Ignoring those markers would
/// write passwords and one-time codes to disk in plain text.
public enum ClipboardPrivacy {

    /// Pasteboard types that flag a copy as concealed, transient, or
    /// machine-generated.
    public static let privateTypes: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType",
        "com.agilebits.onepassword",
        "de.petermaurer.TransientPasteboardType",
        "Pasteboard generator type",
    ]

    /// Apps whose copies are always private, even when they forget the marker.
    public static let privateSourceBundleIDs: Set<String> = [
        "com.apple.keychainaccess",
        "com.apple.Passwords",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.lastpass.LastPass",
        "com.dashlane.dashlanephonefinal",
    ]

    public static func shouldIgnore(types: [String], sourceBundleID: String?) -> Bool {
        if types.contains(where: privateTypes.contains) { return true }
        if let sourceBundleID, privateSourceBundleIDs.contains(sourceBundleID) { return true }
        return false
    }
}
