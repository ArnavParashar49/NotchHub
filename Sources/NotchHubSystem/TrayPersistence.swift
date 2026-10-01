import Foundation
import NotchHubCore

/// Keeps the Tray on disk so it survives a relaunch.
///
/// The Tray is the user's clipboard history; losing 60 clips on every restart
/// would make it useless. Pinned clips persist indefinitely. Because it is
/// clipboard content, it is written readable by the owner only.
///
/// TEXT ONLY: the file holds the strings that were copied and nothing else.
/// There is no image directory and nothing is written outside this one file.
public enum TrayPersistence {

    /// `~/Library/Application Support/NotchHub`.
    public static func baseDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("NotchHub", isDirectory: true)
    }

    /// `~/Library/Application Support/NotchHub/tray.json`.
    public static func fileURL() -> URL {
        baseDirectory().appendingPathComponent("tray.json")
    }

    /// Where copied images USED to be kept, before the Tray became text-only.
    /// Retained solely so `load` can delete it.
    private static func legacyImageDirectory() -> URL {
        baseDirectory().appendingPathComponent("TrayImages", isDirectory: true)
    }

    /// The format this build writes. A file written by any other version is not
    /// migrated — it is discarded (see `load`).
    static let schemaVersion = 2

    /// The stored file: a version, and the clips.
    private struct Stored: Codable {
        var version: Int
        var clips: [TrayClip]
    }

    /// Writes the store, creating its directory if needed.
    public static func save(_ store: TrayStore) {
        let url = fileURL()
        do {
            try ensureDirectory(url.deletingLastPathComponent())
            let data = try JSONEncoder().encode(Stored(version: schemaVersion, clips: store.clips))
            try data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            // Persistence is a convenience: a failure must never break the app.
        }
    }

    /// Reads the store back, or an empty one if nothing valid is on disk.
    ///
    /// A file from before the Tray became text-only is DISCARDED rather than
    /// converted: it is mostly references to images that no longer have a home,
    /// and salvaging the text out of it would leave a history half of whose
    /// entries had silently vanished. The old image directory goes with it, so
    /// nothing is left behind on disk from a feature that no longer exists.
    public static func load() -> TrayStore {
        let url = fileURL()
        guard let data = try? Data(contentsOf: url) else {
            discardLegacyImages()
            return TrayStore()
        }
        guard let stored = try? JSONDecoder().decode(Stored.self, from: data),
              stored.version == schemaVersion else {
            discardLegacy(at: url)
            return TrayStore()
        }
        return TrayStore(clips: stored.clips)
    }

    /// Removes a Tray written by an older build, and everything it referenced.
    private static func discardLegacy(at url: URL) {
        try? FileManager.default.removeItem(at: url)
        discardLegacyImages()
    }

    private static func discardLegacyImages() {
        let directory = legacyImageDirectory()
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    private static func ensureDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

}
