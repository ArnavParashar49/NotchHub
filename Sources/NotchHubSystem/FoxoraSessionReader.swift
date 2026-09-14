import Foundation
import NotchHubCore
import SQLite3

/// Follows Foxora Studio's most recent session from the app's own IndexedDB
/// event log (`~/Library/WebKit/ai.foxora.desktop/…/IndexedDB.sqlite3`),
/// opened read-only and read incrementally by row. Not thread-safe: use from
/// one queue.
final class FoxoraSessionReader {

    /// A session with no events for longer than this is not "current".
    var maxAge: TimeInterval = 30 * 60
    /// How many recent records are scanned when a session is first seen.
    let backfillLimit = 8_000

    private var db: OpaquePointer?
    private var storeID: Int64?
    private var sessionID: String?
    private var lastRowID: Int64 = 0
    private var parser = FoxoraSessionParser()

    deinit {
        if let db { sqlite3_close(db) }
    }

    func currentSession(now: Date = Date()) -> AgentSession? {
        guard openIfNeeded(), let storeID else { return nil }
        guard let newest = records(storeID: storeID, sql: "SELECT rowid, value FROM Records WHERE objectStoreID = ? ORDER BY rowid DESC LIMIT 1", bind: []).first,
              let session = newest.record["sessionId"] as? String else { return nil }

        if session != sessionID {
            sessionID = session
            parser = FoxoraSessionParser()
            let recent = records(
                storeID: storeID,
                sql: "SELECT rowid, value FROM Records WHERE objectStoreID = ? AND rowid <= ? ORDER BY rowid DESC LIMIT ?",
                bind: [newest.rowID, Int64(backfillLimit)]
            )
            for item in recent.reversed() where item.record["sessionId"] as? String == session {
                parser.consume(item.record)
            }
            lastRowID = newest.rowID
        } else if newest.rowID > lastRowID {
            let fresh = records(
                storeID: storeID,
                sql: "SELECT rowid, value FROM Records WHERE objectStoreID = ? AND rowid > ? ORDER BY rowid ASC LIMIT 5000",
                bind: [lastRowID]
            )
            for item in fresh {
                if item.record["sessionId"] as? String == session { parser.consume(item.record) }
                lastRowID = max(lastRowID, item.rowID)
            }
        }

        let result = parser.session(now: now)
        guard let last = result.lastActivity, now.timeIntervalSince(last) < maxAge else { return nil }
        return result
    }

    // MARK: - SQLite

    private func openIfNeeded() -> Bool {
        if db != nil, storeID != nil { return true }
        guard let path = Self.databasePath() else { return false }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            return false
        }
        sqlite3_busy_timeout(handle, 200)
        db = handle
        storeID = eventsStoreID()
        if storeID == nil {
            sqlite3_close(handle)
            db = nil
        }
        return storeID != nil
    }

    private func eventsStoreID() -> Int64? {
        guard let db else { return nil }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT id FROM ObjectStoreInfo WHERE name = 'events'", -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW ? sqlite3_column_int64(statement, 0) : nil
    }

    private func records(storeID: Int64, sql: String, bind: [Int64]) -> [(rowID: Int64, record: [String: Any])] {
        guard let db else { return [] }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            // The app may have replaced its database: reopen next time.
            sqlite3_close(db)
            self.db = nil
            self.storeID = nil
            return []
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, storeID)
        for (i, value) in bind.enumerated() {
            sqlite3_bind_int64(statement, Int32(i + 2), value)
        }
        var result: [(rowID: Int64, record: [String: Any])] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let rowID = sqlite3_column_int64(statement, 0)
            let count = Int(sqlite3_column_bytes(statement, 1))
            guard count > 0, let blob = sqlite3_column_blob(statement, 1) else { continue }
            let data = Data(bytes: blob, count: count)
            guard let record = (try? WebKitValueDecoder.decode(data)) as? [String: Any] else { continue }
            result.append((rowID, record))
        }
        return result
    }

    /// The largest IndexedDB database in Foxora's WebKit data — its event log.
    static func databasePath() -> String? {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/WebKit/ai.foxora.desktop/WebsiteData/Default", isDirectory: true)
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return nil
        }
        var best: (path: String, size: Int)?
        for case let url as URL in enumerator where url.lastPathComponent == "IndexedDB.sqlite3" {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if best == nil || size > best!.size { best = (url.path, size) }
        }
        return best?.path
    }
}
