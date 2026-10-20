import Foundation
import MacBuddyCore

final class ReliabilityTests: CheckSuite {
    func testPermissionDenialAndStaleCallbacks() {
        var state = NotificationPermissionState()
        let enable = state.begin(enabled: true)
        expectTrue(!state.canDeliver)
        expectTrue(state.complete(enable, authorization: .denied))
        expectTrue(!state.canDeliver)
        let retry = state.begin(enabled: true)
        _ = state.begin(enabled: false)
        expectTrue(!state.complete(retry, authorization: .allowed))
        expectTrue(!state.canDeliver)
        let newRequest = state.begin(enabled: true)
        expectTrue(state.complete(newRequest, authorization: .allowed))
        expectTrue(state.canDeliver)
        expectTrue(!state.complete(enable, authorization: .denied))
        expectTrue(state.canDeliver)
    }
    func testCalendarDaysAcrossDSTAndToday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        func date(_ year: Int, _ month: Int, _ day: Int) -> Date { calendar.date(from: DateComponents(year: year, month: month, day: day))! }
        let spring = date(2026,3,8), fall = date(2026,11,1), future = date(2027,1,1)
        expectEqual(HistoryRange.throughDay(spring, calendar: calendar, now: future).timeIntervalSince(spring), 23 * 3600)
        expectEqual(HistoryRange.throughDay(fall, calendar: calendar, now: future).timeIntervalSince(fall), 25 * 3600)
        let now = spring.addingTimeInterval(3600)
        expectEqual(HistoryRange.throughDay(spring, calendar: calendar, now: now), now)
    }
    func testHistoryClockRollbackAndRestart() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("clock.sqlite")
        let start = Date(timeIntervalSince1970: 1_780_012_800)
        func sample(_ seconds: Double, cpu: Double = 40) -> Snapshot {
            let date = start.addingTimeInterval(seconds)
            return Snapshot(at: date, readings: [.cpu: Reading(cpu, at: date, source: "Clock fixture", unit: "%")])
        }
        var store: HistoryStore? = try HistoryStore(url: url)
        for value in [0.0, 2, 4, 6, 2, 4, 6, 8, 10] { try store!.record(sample(value)) }
        try store!.flush()
        var rows = try store!.query(from: start, to: start.addingTimeInterval(60))
        expectEqual(rows.reduce(0) { $0 + $1.coverage }, 8)
        store = nil; store = try HistoryStore(url: url)
        for value in [0.0, 2, 4, 6, 8, 10, 12, 14] { try store!.record(sample(value)) }
        try store!.flush()
        rows = try store!.query(from: start, to: start.addingTimeInterval(60))
        expectEqual(rows.reduce(0) { $0 + $1.coverage }, 10)
    }
    func testLastSamplePeakSurvivesOrderlyFlush() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try HistoryStore(url: folder.appendingPathComponent("peaks.sqlite"))
        let start = Date(timeIntervalSince1970: 1_780_012_800)
        var sample = Snapshot(at: start, readings: [.cpu: Reading(20, at: start, source: "Peak fixture", unit: "%")])
        try store.record(sample)
        sample.timestamp = start.addingTimeInterval(2); sample.readings[.cpu]?.value = 99
        try store.record(sample); try store.flush()
        let row = try requireValue(store.query(from: start, to: start.addingTimeInterval(60)).first)
        expectEqual(row.metrics[.cpu]?.peak, 99)
        expectEqual(row.metrics[.cpu]?.mean, 20)
        expectEqual(row.coverage, 2)
    }
    func testPressureAndThermalRecoveryAfterSleep() {
        var engine = AdviceEngine()
        let epoch = Date(timeIntervalSince1970: 1_780_000_000)
        func sample(_ time: Double, _ state: Thermal) -> Snapshot { Snapshot(at: epoch.addingTimeInterval(time), thermal: state, pressure: .normal) }
        expectEqual(engine.update(sample(0, .critical)).notifications.count, 1)
        _ = engine.update(sample(2, .nominal))
        engine.resetContinuity()
        expectEqual(engine.update(sample(10000, .nominal)).active.count, 1)
        for time in stride(from: 10002.0, to: 10120, by: 2) { expectEqual(engine.update(sample(time, .nominal)).active.count, 1) }
        expectTrue(engine.update(sample(10120, .nominal)).active.isEmpty)
    }
}
