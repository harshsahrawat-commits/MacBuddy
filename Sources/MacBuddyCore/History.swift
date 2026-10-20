import Foundation
import CSQLite

public struct MetricSummary: Codable, Sendable {
    public var weightedSum = 0.0
    public var seconds = 0.0
    public var minimum: Double?
    public var peak: Double?
    public var mean: Double? { seconds > 0 ? weightedSum / seconds : nil }
    mutating func add(_ value: Double, seconds duration: Double) {
        weightedSum += value * duration; seconds += duration
        minimum = min(minimum ?? value, value); peak = max(peak ?? value, value)
    }
    mutating func merge(_ other: MetricSummary) {
        weightedSum += other.weightedSum; seconds += other.seconds
        if let value = other.minimum { minimum = min(minimum ?? value, value) }
        if let value = other.peak { peak = max(peak ?? value, value) }
    }
}
public struct Summary: Codable, Identifiable, Sendable {
    public var start: Date
    public var duration: TimeInterval
    public var coverage = 0.0
    public var metrics: [Metric: MetricSummary] = [:]
    public var thermalSeconds: [Int: Double] = [:]
    public var pressureSeconds: [Int: Double] = [:]
    public var id: Date { start }
    public init(start: Date, duration: TimeInterval = 60) { self.start = start; self.duration = duration }
    public mutating func add(_ snapshot: Snapshot, seconds: Double) {
        coverage += seconds
        for (key, reading) in snapshot.readings {
            if let value = reading.value { metrics[key, default: MetricSummary()].add(value, seconds: seconds) }
        }
        thermalSeconds[snapshot.thermal.rawValue, default: 0] += seconds
        pressureSeconds[snapshot.pressure.rawValue, default: 0] += seconds
    }
    public mutating func merge(_ other: Summary) {
        coverage += other.coverage
        for (key, value) in other.metrics { metrics[key, default: MetricSummary()].merge(value) }
        for (key, value) in other.thermalSeconds { thermalSeconds[key, default: 0] += value }
        for (key, value) in other.pressureSeconds { pressureSeconds[key, default: 0] += value }
    }
}
public struct HistoryEvent: Codable, Identifiable, Sendable {
    public var timestamp: Date
    public var kind: String
    public var id: String { "\(timestamp.timeIntervalSince1970)-\(kind)" }
}
public struct HistoryResult: Sendable {
    public var summaries: [Summary]
    public var events: [HistoryEvent]
    public var bytes: Int64
    public var pausedReason: String?
    public init(summaries: [Summary] = [], events: [HistoryEvent] = [], bytes: Int64 = 0, pausedReason: String? = nil) {
        self.summaries = summaries; self.events = events; self.bytes = bytes; self.pausedReason = pausedReason
    }
}
public enum HistoryError: Error, LocalizedError {
    case database(String)
    public var errorDescription: String? { switch self { case .database(let text): return text } }
}

/// Owned by the serial sampling queue. Only summaries and lifecycle events are persisted.
public final class HistoryStore {
    private var db: OpaquePointer?
    public let url: URL
    public let budget: Int64
    public private(set) var pausedReason: String?
    private var pending: [Int64: Summary] = [:]
    private var previous: Snapshot?
    private var latestTimestamp: Date?
    private var lastMaintenance = Date.distantPast
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    public init(url: URL, budget: Int64 = 100 * 1_048_576) throws {
        self.url = url; self.budget = budget
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Could not open history database."
            sqlite3_close(db); db = nil; throw HistoryError.database(message)
        }
        do {
            sqlite3_busy_timeout(db, 1000)
            let versionQuery = try statement("PRAGMA user_version")
            let versionStatus = sqlite3_step(versionQuery)
            let version = sqlite3_column_int(versionQuery, 0)
            sqlite3_finalize(versionQuery)
            guard versionStatus == SQLITE_ROW else { throw error() }
            guard version <= 2 else { throw HistoryError.database("History was created by a newer Mac Buddy version (schema \(version)). Existing data is preserved; use a compatible app version.") }
            try execute("PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL; PRAGMA wal_autocheckpoint=32; PRAGMA journal_size_limit=1048576;")
            try execute("CREATE TABLE IF NOT EXISTS summaries (bucket INTEGER NOT NULL, resolution INTEGER NOT NULL, payload BLOB NOT NULL, PRIMARY KEY(bucket,resolution)); CREATE TABLE IF NOT EXISTS events (time REAL NOT NULL, kind TEXT NOT NULL, PRIMARY KEY(time,kind)); CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value REAL NOT NULL); PRAGMA user_version=2;")
            let cursor = try statement("SELECT value FROM metadata WHERE key='last_sample'")
            defer { sqlite3_finalize(cursor) }
            let state = sqlite3_step(cursor)
            if state == SQLITE_ROW { latestTimestamp = Date(timeIntervalSince1970: sqlite3_column_double(cursor, 0)) }
            else if state != SQLITE_DONE { throw error() }
        } catch { sqlite3_close(db); db = nil; throw error }
    }
    deinit { sqlite3_close(db) }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw error() }
    }
    private func error() -> HistoryError { .database(db.map { String(cString: sqlite3_errmsg($0)) } ?? "History database is closed.") }
    private func statement(_ sql: String) throws -> OpaquePointer {
        var result: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &result, nil) == SQLITE_OK, let result else { throw error() }
        return result
    }
    private func transaction(_ operation: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do { try operation(); try execute("COMMIT") }
        catch { try? execute("ROLLBACK"); throw error }
    }
    public var diskUsage: Int64 {
        [url.path, url.path + "-wal", url.path + "-shm", url.path + "-journal"].reduce(0) { result, path in
            result + ((try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? 0)
        }
    }
    public func resetContinuity() { previous = nil }
    public func record(_ sample: Snapshot) throws {
        guard pausedReason == nil else { previous = nil; return }
        // Never count a wall-clock interval twice, including across app restarts.
        guard latestTimestamp.map({ sample.timestamp > $0 }) ?? true else { previous = nil; return }
        latestTimestamp = sample.timestamp
        defer { previous = sample }
        if let old = previous {
            let interval = sample.timestamp.timeIntervalSince(old.timestamp)
            if interval > 0 && interval <= 15 {
                var cursor = old.timestamp.timeIntervalSince1970
                let end = sample.timestamp.timeIntervalSince1970
                while cursor < end {
                    let bucket = Int64(floor(cursor / 60) * 60)
                    let boundary = min(end, Double(bucket + 60))
                    if pending[bucket] == nil { pending[bucket] = try fetch(bucket: bucket, resolution: 60) ?? Summary(start: Date(timeIntervalSince1970: Double(bucket))) }
                    pending[bucket]!.add(old, seconds: boundary - cursor)
                    cursor = boundary
                }
            }
        }
        let bucket = Int64(floor(sample.timestamp.timeIntervalSince1970 / 60) * 60)
        if pending[bucket] == nil { pending[bucket] = try fetch(bucket: bucket, resolution: 60) ?? Summary(start: Date(timeIntervalSince1970: Double(bucket))) }
        // A final sample still contributes its peak, even when export/quit precedes the next tick.
        pending[bucket]!.add(sample, seconds: 0)
        if pending.keys.contains(where: { $0 < bucket }) { try flush() }
        if sample.timestamp.timeIntervalSince(lastMaintenance) >= 3600 {
            try maintain(now: sample.timestamp); lastMaintenance = sample.timestamp
        }
    }
    public func flush() throws {
        guard pausedReason == nil, !pending.isEmpty else { return }
        // Leave headroom for one small transaction, then measure actual journal usage.
        if diskUsage + 65536 >= budget { try reclaim(); if diskUsage + 65536 >= budget { pause(); return } }
        try transaction {
            for row in pending.values { try save(row) }
            if let latestTimestamp {
                let stmt = try statement("INSERT INTO metadata(key,value) VALUES('last_sample',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value")
                defer { sqlite3_finalize(stmt) }
                sqlite3_bind_double(stmt, 1, latestTimestamp.timeIntervalSince1970)
                guard sqlite3_step(stmt) == SQLITE_DONE else { throw error() }
            }
        }
        pending.removeAll()
        if diskUsage > budget { try reclaim(); if diskUsage > budget { pause() } }
    }
    private func pause() { pausedReason = "History storage reached its \(budget / 1_048_576) MiB budget. Recording is paused; existing history is preserved. Clear history or free disk space, then retry."; pending.removeAll() }
    public func pauseAfterError(_ error: Error) { pausedReason = "History recording paused: \(error.localizedDescription). Existing history is preserved."; pending.removeAll() }
    public func retry(now: Date = Date()) throws { pausedReason = nil; previous = nil; try maintain(now: now) }
    private func save(_ summary: Summary) throws {
        let data = try encoder.encode(summary)
        let stmt = try statement("INSERT INTO summaries(bucket,resolution,payload) VALUES(?,?,?) ON CONFLICT(bucket,resolution) DO UPDATE SET payload=excluded.payload")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(summary.start.timeIntervalSince1970)); sqlite3_bind_int64(stmt, 2, Int64(summary.duration))
        try data.withUnsafeBytes { bytes in
            sqlite3_bind_blob(stmt, 3, bytes.baseAddress, Int32(bytes.count), nil)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw error() }
        }
    }
    private func fetch(bucket: Int64, resolution: Int64) throws -> Summary? {
        let stmt = try statement("SELECT payload FROM summaries WHERE bucket=? AND resolution=?")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, bucket); sqlite3_bind_int64(stmt, 2, resolution)
        let result = sqlite3_step(stmt)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW else { throw error() }
        return try decode(stmt)
    }
    private func decode(_ stmt: OpaquePointer) throws -> Summary {
        guard let bytes = sqlite3_column_blob(stmt, 0) else { throw HistoryError.database("History row is empty.") }
        return try decoder.decode(Summary.self, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 0))))
    }
    public func query(from: Date, to: Date, includeDaily: Bool = true) throws -> [Summary] {
        let stmt = try statement("SELECT payload FROM summaries WHERE bucket>=? AND bucket<? AND (resolution=60 OR ?=1) ORDER BY bucket")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, from.timeIntervalSince1970); sqlite3_bind_double(stmt, 2, to.timeIntervalSince1970); sqlite3_bind_int(stmt, 3, includeDaily ? 1 : 0)
        var rows: [Summary] = []
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw error() }
            rows.append(try decode(stmt))
        }
        return rows
    }
    public func event(_ kind: String, at date: Date = Date()) throws {
        guard pausedReason == nil else { return }
        if diskUsage + 65536 >= budget { try reclaim(); if diskUsage + 65536 >= budget { pause(); return } }
        let stmt = try statement("INSERT OR IGNORE INTO events(time,kind) VALUES(?,?)")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, date.timeIntervalSince1970)
        try kind.withCString { string in
            sqlite3_bind_text(stmt, 2, string, -1, nil)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw error() }
        }
    }
    public func events(from: Date, to: Date) throws -> [HistoryEvent] {
        let stmt = try statement("SELECT time,kind FROM events WHERE time>=? AND time<? ORDER BY time")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, from.timeIntervalSince1970); sqlite3_bind_double(stmt, 2, to.timeIntervalSince1970)
        var events: [HistoryEvent] = []
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW, let text = sqlite3_column_text(stmt, 1) else { throw error() }
            events.append(HistoryEvent(timestamp: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 0)), kind: String(cString: text)))
        }
        return events
    }
    public func maintain(now: Date = Date()) throws {
        // Archive only whole UTC days; this prevents overlaps with minute history at the boundary.
        let cutoff = Int64(floor(now.addingTimeInterval(-30 * 86400).timeIntervalSince1970 / 86400) * 86400)
        let days = try statement("SELECT DISTINCT (bucket/86400)*86400 FROM summaries WHERE resolution=60 AND bucket<? ORDER BY bucket")
        sqlite3_bind_int64(days, 1, cutoff)
        var buckets: [Int64] = []
        while true {
            let result = sqlite3_step(days)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { sqlite3_finalize(days); throw error() }
            buckets.append(sqlite3_column_int64(days, 0))
        }
        sqlite3_finalize(days)
        for day in buckets {
            try transaction {
                var aggregate = try fetch(bucket: day, resolution: 86400) ?? Summary(start: Date(timeIntervalSince1970: Double(day)), duration: 86400)
                for row in try query(from: aggregate.start, to: aggregate.start.addingTimeInterval(86400), includeDaily: false) { aggregate.merge(row) }
                try save(aggregate)
                try execute("DELETE FROM summaries WHERE resolution=60 AND bucket>=\(day) AND bucket<\(day+86400)")
            }
        }
        // Old gaps remain encoded in daily coverage; detailed lifecycle events are bounded to 30 days.
        try execute("DELETE FROM events WHERE time<\(cutoff)")
        if !buckets.isEmpty || diskUsage > budget - 65536 { try reclaim() }
        if diskUsage > budget - 65536 { pause() }
    }
    private func reclaim() throws { try execute("PRAGMA wal_checkpoint(TRUNCATE); VACUUM; PRAGMA wal_checkpoint(TRUNCATE);") }
    public func clear() throws {
        try transaction { try execute("DELETE FROM summaries; DELETE FROM events; DELETE FROM metadata;") }
        pending.removeAll(); previous = nil; latestTimestamp = nil; pausedReason = nil
        try reclaim()
    }
}
