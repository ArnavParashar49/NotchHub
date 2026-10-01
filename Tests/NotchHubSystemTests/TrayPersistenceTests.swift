import Foundation
import Testing
@testable import NotchHubCore
@testable import NotchHubSystem

@Suite("Tray persistence", .serialized)
struct TrayPersistenceTests {

    /// The real store paths, saved and restored around each test so a run can
    /// never disturb the Tray of whoever is running it.
    private func withCleanTray(_ body: (URL, URL) throws -> Void) rethrows {
        let file = TrayPersistence.fileURL()
        let images = TrayPersistence.baseDirectory().appendingPathComponent("TrayImages", isDirectory: true)
        let backup = file.appendingPathExtension("test-backup")
        let fm = FileManager.default
        let hadFile = fm.fileExists(atPath: file.path)
        if hadFile { try? fm.moveItem(at: file, to: backup) }
        defer {
            try? fm.removeItem(at: file)
            try? fm.removeItem(at: images)
            if hadFile { try? fm.moveItem(at: backup, to: file) }
        }
        try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try body(file, images)
    }

    @Test("a Tray written by this build round-trips")
    func roundTrip() throws {
        try withCleanTray { _, _ in
            let store = TrayStore()
            store.add(TrayClip(kind: .text, text: "hello"))
            store.add(TrayClip(kind: .link, text: "https://example.com", pinned: true))
            TrayPersistence.save(store)

            let loaded = TrayPersistence.load()
            #expect(loaded.clips.count == 2)
            #expect(loaded.clips.contains { $0.text == "hello" })
            #expect(loaded.clips.first { $0.kind == .link }?.pinned == true)
        }
    }

    @Test("a Tray from before the text-only change is discarded, images and all")
    func legacyTrayIsWiped() throws {
        try withCleanTray { file, images in
            let fm = FileManager.default
            // Exactly what the old build wrote: a bare array, with clips
            // referring to images kept in their own directory.
            let legacy = """
            [{"id":"\(UUID().uuidString)","kind":"screenshot","filePaths":[],\
            "imagePath":"\(images.path)/old.png","pinned":false,\
            "createdAt":752000000}]
            """
            try legacy.write(to: file, atomically: true, encoding: .utf8)
            try fm.createDirectory(at: images, withIntermediateDirectories: true)
            try Data("not really a png".utf8).write(to: images.appendingPathComponent("old.png"))
            #expect(fm.fileExists(atPath: images.path))

            let loaded = TrayPersistence.load()

            // Started clean…
            #expect(loaded.clips.isEmpty)
            // …and left nothing behind on disk from a feature that is gone.
            #expect(!fm.fileExists(atPath: images.path), "the old image directory survived")
            #expect(!fm.fileExists(atPath: file.path), "the old tray file survived")
        }
    }

    @Test("a corrupt or truncated Tray starts clean instead of failing")
    func corruptTrayIsSafe() throws {
        try withCleanTray { file, _ in
            try Data("{ this is not json".utf8).write(to: file)
            #expect(TrayPersistence.load().clips.isEmpty)
        }
    }

    @Test("no Tray on disk is simply an empty Tray")
    func missingTray() throws {
        try withCleanTray { file, _ in
            try? FileManager.default.removeItem(at: file)
            #expect(TrayPersistence.load().clips.isEmpty)
        }
    }

    @Test("the saved file is readable by its owner only")
    func filePermissions() throws {
        try withCleanTray { file, _ in
            let store = TrayStore()
            store.add(TrayClip(kind: .text, text: "something private"))
            TrayPersistence.save(store)
            let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
            #expect(mode?.int16Value == 0o600, "clipboard contents were world-readable")
        }
    }
}
