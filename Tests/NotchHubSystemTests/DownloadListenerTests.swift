import Foundation
import Testing
import NotchHubCore
@testable import NotchHubSystem

@Suite("DownloadListener")
struct DownloadListenerTests {

    /// Collects events from whatever thread the listener emits on.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var events: [(payload: SystemEvent.Payload, onMain: Bool)] = []

        func record(_ event: SystemEvent) {
            lock.lock()
            events.append((event.payload, Thread.isMainThread))
            lock.unlock()
        }

        var snapshot: [(payload: SystemEvent.Payload, onMain: Bool)] {
            lock.lock()
            defer { lock.unlock() }
            return events
        }
    }

    private func waitFor(_ condition: () -> Bool, timeout: TimeInterval = 5) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
    }

    @Test("the folder is read off the main thread, and a download still starts and finishes")
    func readsOffMain() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("notchhub-downloads-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let recorder = Recorder()
        let listener = DownloadListener(directory: folder.path) { recorder.record($0) }
        listener.start()
        defer { listener.stop() }
        // Give the listener's own queue a moment to seed and start watching.
        try await Task.sleep(nanoseconds: 300_000_000)

        let partial = folder.appendingPathComponent("report.pdf.crdownload")
        try Data(repeating: 1, count: 128).write(to: partial)
        #expect(await waitFor { recorder.snapshot.contains { $0.payload == .downloadStarted(name: "report.pdf") } })

        try FileManager.default.moveItem(at: partial, to: folder.appendingPathComponent("report.pdf"))
        #expect(await waitFor { recorder.snapshot.contains { $0.payload == .downloadFinished(name: "report.pdf") } })

        // Every scan ran on the listener's queue, never the main thread — the
        // first listing of ~/Downloads can wait on a privacy prompt.
        #expect(!recorder.snapshot.isEmpty)
        #expect(recorder.snapshot.allSatisfy { !$0.onMain })
    }
}
