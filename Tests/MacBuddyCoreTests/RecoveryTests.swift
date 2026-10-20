import Foundation
import Darwin
import MacBuddyCore

func writeCrashFixture(_ path: String) throws -> Never {
    let store = try HistoryStore(url: URL(fileURLWithPath: path))
    let date = Date(timeIntervalSince1970: 1_780_012_800)
    let sample = Snapshot(at: date, readings: [.cpu: Reading(42, at: date, source: "Crash test", unit: "%")], thermal: .nominal, pressure: .normal)
    try store.record(sample)
    var next = sample; next.timestamp = date.addingTimeInterval(2)
    try store.record(next); try store.flush()
    next.timestamp = date.addingTimeInterval(4); next.readings[.cpu]?.value = 99
    try store.record(next) // Deliberately uncommitted interval.
    withExtendedLifetime(store) { _exit(0) } // Simulate loss without destructors / SQLite close.
}
final class RecoveryTests: CheckSuite {
    var folder: URL!
    override func setUpWithError() throws { folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }
    func testUnexpectedProcessExitRecoversCommittedWAL() throws {
        let url = folder.appendingPathComponent("crash.sqlite")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = ["--crash-fixture", url.path]
        try process.run(); process.waitUntilExit()
        expectEqual(process.terminationStatus, 0)
        expectTrue(FileManager.default.fileExists(atPath: url.path + "-wal"))
        let store = try HistoryStore(url: url)
        let date = Date(timeIntervalSince1970: 1_780_012_800)
        let row = try requireValue(store.query(from: date, to: date.addingTimeInterval(60)).first)
        expectEqual(row.coverage, 2)
        expectEqual(row.metrics[.cpu]?.peak, 42)
    }
    func testMalformedDatabaseIsPreserved() throws {
        let url = folder.appendingPathComponent("invalid.sqlite")
        let bytes = Data("This is not a SQLite database. Preserve it.".utf8)
        try bytes.write(to: url)
        expectThrows(try HistoryStore(url: url))
        expectEqual(try Data(contentsOf: url), bytes)
    }
    func testNewerSchemaIsRejectedWithoutDowngrade() throws {
        let url = folder.appendingPathComponent("future.sqlite")
        let tool = Process(); tool.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        tool.arguments = [url.path, "CREATE TABLE sentinel(value TEXT); INSERT INTO sentinel VALUES('preserve'); PRAGMA user_version=99;"]
        try tool.run(); tool.waitUntilExit(); expectEqual(tool.terminationStatus, 0)
        let before = try Data(contentsOf: url)
        expectThrows(try HistoryStore(url: url))
        expectEqual(try Data(contentsOf: url), before)
    }
}
