import Foundation
import NotchHubCore

/// Keeps the Tray on disk so it survives a relaunch.
///
/// The Tray is the user's clipboard history; losing 60 clips on every restart
/// would make it useless. Pinned clips persist indefinitely. Because it is
/// clipboard content, it is written readable by the owner only.
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

    /// Where copied images are kept. NOT the temp directory: macOS purges that,
    /// which silently dropped every image from the history.
    public static func imageDirectory() -> URL {
        baseDirectory().appendingPathComponent("TrayImages", isDirectory: true)
    }

    /// Writes the store, creating its directory if needed, and deletes image
    /// files no clip references any more (evicted or deleted clips).
    public static func save(_ store: TrayStore) {
        let url = fileURL()
        do {
            try ensureDirectory(url.deletingLastPathComponent())
            let data = try JSONEncoder().encode(store.clips)
            try data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            // Persistence is a convenience: a failure must never break the app.
        }
        pruneImages(keeping: store)
    }

    /// Reads the store back, or an empty one if nothing valid is on disk.
    public static func load() -> TrayStore {
        let url = fileURL()
        guard let data = try? Data(contentsOf: url),
              let clips = try? JSONDecoder().decode([TrayClip].self, from: data) else {
            return TrayStore()
        }
        // Drop image clips whose file no longer exists, so the Tray never
        // shows a broken thumbnail.
        let live = clips.filter { clip in
            guard let path = clip.imagePath else { return true }
            return FileManager.default.fileExists(atPath: path)
        }
        return TrayStore(clips: live)
    }

    /// Writes image bytes into the Tray's image directory and returns the path.
    public static func saveImage(_ data: Data) -> String? {
        let directory = imageDirectory()
        do {
            try ensureDirectory(directory)
            let url = directory.appendingPathComponent(UUID().uuidString + ".png")
            try data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return url.path
        } catch {
            return nil
        }
    }

    private static func ensureDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    private static func pruneImages(keeping store: TrayStore) {
        let directory = imageDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return
        }
        let referenced = Set(store.clips.compactMap { $0.imagePath.map { URL(fileURLWithPath: $0).standardizedFileURL.path } })
        for file in files where !referenced.contains(file.standardizedFileURL.path) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
