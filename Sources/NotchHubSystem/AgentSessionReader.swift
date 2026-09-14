import Foundation
import NotchHubCore

/// Follows the most recently active session log of one agent, reading only
/// what was appended since the last poll. Not thread-safe: use from one queue.
final class AgentSessionReader<Parser: AgentTranscriptParser> {

    /// A session untouched for longer than this is not "current".
    var maxAge: TimeInterval = 30 * 60
    /// How often the log directory is rescanned for a newer session.
    let rescanInterval: TimeInterval = 5

    private let findNewest: () -> URL?
    private var file: URL?
    private var offset: UInt64 = 0
    private var partial = Data()
    private var parser = Parser()
    private var lastScan = Date.distantPast
    private var latest: URL?

    init(findNewest: @escaping () -> URL?) {
        self.findNewest = findNewest
    }

    func currentSession(now: Date = Date()) -> AgentSession? {
        if now.timeIntervalSince(lastScan) >= rescanInterval {
            lastScan = now
            latest = findNewest()
        }
        guard let latest, let modified = AgentTranscripts.modified(latest),
              now.timeIntervalSince(modified) < maxAge else { return nil }

        if latest != file {
            file = latest
            reset()
        }
        readAppended(latest)
        return parser.agentSession(now: now)
    }

    private func reset() {
        offset = 0
        partial = Data()
        parser = Parser()
    }

    private func readAppended(_ url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return }
        if size < offset { reset() } // rewritten or truncated
        guard size > offset else { return }
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd() else { return }
        offset += UInt64(data.count)

        let buffer = partial + data
        var start = buffer.startIndex
        while let newline = buffer[start...].firstIndex(of: 0x0A) {
            if newline > start {
                parser.consume(Data(buffer[start..<newline]))
            }
            start = buffer.index(after: newline)
        }
        partial = Data(buffer[start...])
    }
}

/// Where each agent keeps its session logs.
enum AgentTranscripts {

    /// Claude Code: `~/.claude/projects/<project>/<session>.jsonl`.
    static func newestClaude() -> URL? {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
        return newest(in: subdirectories(of: root), extension: "jsonl")
    }

    /// Codex (CLI and app): `$CODEX_HOME/sessions/YYYY/MM/DD/rollout-*.jsonl`,
    /// `CODEX_HOME` defaulting to `~/.codex`. Only the three most recent day
    /// folders are scanned — a current session is never older than that.
    static func newestCodex() -> URL? {
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        let sessions = home.appendingPathComponent("sessions", isDirectory: true)
        var days: [URL] = []
        for year in subdirectories(of: sessions).sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
            for month in subdirectories(of: year).sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
                for day in subdirectories(of: month).sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
                    days.append(day)
                    if days.count == 3 { return newest(in: days, extension: "jsonl") }
                }
            }
        }
        return newest(in: days, extension: "jsonl")
    }

    static func modified(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private static func subdirectories(of url: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    private static func newest(in directories: [URL], extension ext: String) -> URL? {
        var best: (url: URL, modified: Date)?
        for directory in directories {
            let files = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for url in files where url.pathExtension == ext {
                guard let modified = modified(url) else { continue }
                if best == nil || modified > best!.modified { best = (url, modified) }
            }
        }
        return best?.url
    }
}
