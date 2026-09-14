import Foundation
import NotchHubCore

/// Watches the Downloads folder and reports transfers as they land.
///
/// A `DispatchSource` directory watcher notices files appearing, vanishing and
/// being renamed. Progress is read from the partial files browsers write while
/// a transfer is in flight (`.download`, `.crdownload`, `.part`, `.tmp`):
///
/// - Safari's `.download` is a bundle whose `Info.plist` records both the bytes
///   received and the total, so it yields a REAL fraction.
/// - Chrome's `.crdownload` and Firefox's `.part` carry no total, so they report
///   the bytes received and no percentage — the island never invents one.
///
/// A directory watcher does not fire when a file INSIDE the folder grows, so
/// while anything is in flight a one-second rescan keeps progress moving.
///
/// A finished download is normally the partial file being *renamed* to its
/// final name. The filesystem reports that as two events — the partial
/// vanishing, then the final appearing — so a vanished partial is held for one
/// grace scan before it is reported complete.
public final class DownloadListener: SystemListener {

    private let emit: (SystemEvent) -> Void
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1
    private var rescanTimer: Timer?
    private var known: Set<String> = []
    private let directory: String

    /// Downloads currently in flight, keyed by the FINAL file name, carrying the
    /// last observed byte count so progress only fires on real growth.
    private var active: [String: Int64] = [:]
    /// Finals whose partial has vanished but which may still be mid-rename.
    private var pendingFinish: Set<String> = []

    /// Suffixes that mark a file as still downloading.
    private static let partialSuffixes = [".download", ".crdownload", ".part", ".tmp"]

    public init(emit: @escaping (SystemEvent) -> Void) {
        self.emit = emit
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.directory = (home as NSString).appendingPathComponent("Downloads")
    }

    public func start() {
        guard source == nil else { return }
        guard FileManager.default.fileExists(atPath: directory) else { return }

        // Seed with what is already there so we only report new arrivals.
        known = Set(currentFiles())
        for name in partialFiles() {
            active[Self.finalName(for: name)] = progress(ofPartial: name).bytes
        }

        let descriptor = open(directory, O_EVTONLY)
        guard descriptor >= 0 else { return }
        fileDescriptor = descriptor

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.scan()
        }
        // Close the descriptor this source owns — never `self.fileDescriptor`,
        // which a restart may already have replaced by the time this runs.
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        self.source = source
        updateRescanTimer()
    }

    public func stop() {
        source?.cancel()
        source = nil
        fileDescriptor = -1
        rescanTimer?.invalidate()
        rescanTimer = nil
        active.removeAll()
        pendingFinish.removeAll()
    }

    private func scan() {
        let now = Set(currentFiles())
        let partials = Set(partialFiles())
        let partialFinals = Set(partials.map(Self.finalName(for:)))

        for name in partials {
            let final = Self.finalName(for: name)
            let reading = progress(ofPartial: name)
            if let previous = active[final] {
                // A partial that grew: report its progress.
                if reading.bytes > previous {
                    active[final] = reading.bytes
                    emit(SystemEvent(source: .downloads, payload: .downloadProgress(
                        name: final,
                        progress: reading.fraction,
                        bytes: reading.bytes
                    )))
                }
            } else {
                // A partial that just appeared: a download started.
                active[final] = reading.bytes
                pendingFinish.remove(final)
                emit(SystemEvent(source: .downloads, payload: .downloadStarted(name: final)))
            }
        }

        // Resolve in-flight downloads. Snapshot the keys: the loop mutates
        // `active` as downloads complete.
        for final in Array(active.keys) {
            if now.contains(final), !partialFinals.contains(final) {
                // The final file landed — the download completed.
                finish(final)
            } else if !partialFinals.contains(final) {
                // No partial and no final: either mid-rename (the final is about
                // to appear) or cancelled. Hold for one scan, then report.
                if pendingFinish.contains(final) {
                    finish(final)
                } else {
                    pendingFinish.insert(final)
                }
            }
        }

        // A brand-new non-partial file with no in-flight download behind it is
        // an instant completion (small files, direct saves).
        for name in now.subtracting(known) where !Self.isPartial(name) {
            guard active[name] == nil, !pendingFinish.contains(name) else { continue }
            emit(SystemEvent(source: .downloads, payload: .downloadFinished(name: name)))
        }

        known = now
        updateRescanTimer()
    }

    private func finish(_ final: String) {
        emit(SystemEvent(source: .downloads, payload: .downloadFinished(name: final)))
        active[final] = nil
        pendingFinish.remove(final)
    }

    /// Rescans every second while a transfer is in flight or a rename is
    /// pending, and stops as soon as the folder is quiet.
    private func updateRescanTimer() {
        let busy = !active.isEmpty || !pendingFinish.isEmpty
        if busy, rescanTimer == nil {
            let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.scan()
            }
            RunLoop.main.add(timer, forMode: .common)
            rescanTimer = timer
        } else if !busy {
            rescanTimer?.invalidate()
            rescanTimer = nil
        }
    }

    // MARK: - Files

    /// Files in Downloads, excluding dotfiles.
    private func currentFiles() -> [String] {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
            return []
        }
        return contents.filter { !$0.hasPrefix(".") }
    }

    /// The partial (in-progress) files currently present.
    private func partialFiles() -> [String] {
        currentFiles().filter(Self.isPartial)
    }

    private static func isPartial(_ name: String) -> Bool {
        partialSuffixes.contains { name.hasSuffix($0) }
    }

    /// The final name a partial file will become once the download lands.
    private static func finalName(for name: String) -> String {
        for suffix in partialSuffixes where name.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return name
    }

    /// How far a partial download has got: a real fraction when the total is
    /// recorded (Safari), otherwise only the bytes on disk.
    private func progress(ofPartial name: String) -> (fraction: Double?, bytes: Int64) {
        let path = (directory as NSString).appendingPathComponent(name)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return (nil, 0) }

        guard isDirectory.boolValue else {
            return (nil, Self.size(of: path))
        }

        // A Safari `.download` bundle.
        let plist = (path as NSString).appendingPathComponent("Info.plist")
        if let info = NSDictionary(contentsOfFile: plist) {
            let soFar = (info["DownloadEntryProgressBytesSoFar"] as? NSNumber)?.int64Value ?? 0
            let total = (info["DownloadEntryProgressTotalToLoad"] as? NSNumber)?.int64Value ?? 0
            if total > 0 {
                return (min(1, max(0, Double(soFar) / Double(total))), soFar)
            }
            if soFar > 0 { return (nil, soFar) }
        }
        // No usable plist: measure the bundle's contents.
        let files = (try? FileManager.default.subpathsOfDirectory(atPath: path)) ?? []
        let bytes = files.reduce(Int64(0)) { $0 + Self.size(of: (path as NSString).appendingPathComponent($1)) }
        return (nil, bytes)
    }

    private static func size(of path: String) -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              (attrs[.type] as? FileAttributeType) == .typeRegular else { return 0 }
        return (attrs[.size] as? NSNumber)?.int64Value ?? 0
    }
}
