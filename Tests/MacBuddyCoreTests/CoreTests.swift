import Foundation
import PDFKit
import MacBuddyCore

final class AdviceTests: CheckSuite {
    let epoch = Date(timeIntervalSince1970: 1_780_000_000)
    func sample(_ seconds: Double, thermal: Thermal = .nominal, pressure: Pressure = .normal, cpu: Double? = 20, gpu: Double? = 10, memory: Double = 50, compressed: Double = 0, swapRate: Double = 0, disk: Double = 100) -> Snapshot {
        let date = epoch.addingTimeInterval(seconds)
        var values: [Metric: Reading] = [:]
        for (key, value) in [(Metric.cpu, cpu), (.gpu, gpu), (.memoryUsed, memory), (.memoryTotal, 100), (.compressed, compressed), (.swapRate, swapRate), (.swapUsed, 8 * 1_073_741_824), (.cpuTemperature, 100), (.diskFree, disk * 1_073_741_824), (.diskTotal, 500 * 1_073_741_824)] {
            values[key] = Reading(value, at: date, source: "test", unit: key.unit)
        }
        return Snapshot(at: date, readings: values, thermal: thermal, pressure: pressure)
    }
    func testHighCelsiusRAMAndExistingSwapDoNotInventWarning() {
        var engine = AdviceEngine()
        for time in stride(from: 0.0, through: 180, by: 2) {
            expectTrue(engine.update(sample(time, memory: 95)).active.isEmpty)
        }
    }
    func testThermalDurationsAndImmediateCritical() {
        var engine = AdviceEngine()
        for time in stride(from: 0.0, to: 30, by: 2) { expectTrue(engine.update(sample(time, thermal: .fair)).notifications.isEmpty) }
        expectEqual(engine.update(sample(30, thermal: .fair)).notifications.first?.severity, 1)
        for time in stride(from: 32.0, to: 42, by: 2) { expectTrue(engine.update(sample(time, thermal: .serious)).notifications.isEmpty) }
        expectEqual(engine.update(sample(42, thermal: .serious)).notifications.first?.severity, 2)
        expectEqual(engine.update(sample(44, thermal: .critical)).notifications.first?.severity, 3)
    }
    func testTransientLoadAndSleepResetDuration() {
        var engine = AdviceEngine()
        for time in stride(from: 0.0, through: 90, by: 2) { expectTrue(engine.update(sample(time, cpu: 98)).active.isEmpty) }
        expectTrue(engine.update(sample(92, cpu: 20)).active.isEmpty)
        for time in stride(from: 94.0, through: 200, by: 2) { expectTrue(engine.update(sample(time, cpu: 98)).active.isEmpty) }
        expectTrue(engine.update(sample(1000, cpu: 98)).active.isEmpty)
        for time in stride(from: 1002.0, to: 1120, by: 2) { expectTrue(engine.update(sample(time, cpu: 98)).active.isEmpty) }
        expectEqual(engine.update(sample(1120, cpu: 98)).active.first?.category, .capacity)
    }
    func testMemoryPressureImmediateAndUnknownIsNotRecovery() {
        var engine = AdviceEngine()
        expectEqual(engine.update(sample(0, pressure: .warning)).notifications.first?.category, .memory)
        for time in stride(from: 2.0, through: 140, by: 2) { expectEqual(engine.update(sample(time, pressure: .unknown)).active.count, 1) }
        for time in stride(from: 142.0, to: 262, by: 2) { expectEqual(engine.update(sample(time)).active.count, 1) }
        expectTrue(engine.update(sample(262)).active.isEmpty)
    }
    func testCompressionNeedsSustainedGrowth() {
        var engine = AdviceEngine()
        for time in stride(from: 0.0, to: 120, by: 2) { expectTrue(engine.update(sample(time, memory: 90, compressed: time * 1_048_576)).active.isEmpty) }
        expectEqual(engine.update(sample(120, memory: 90, compressed: 120 * 1_048_576)).active.first?.category, .memory)
        var spike = AdviceEngine()
        for time in stride(from: 0.0, through: 140, by: 2) { expectTrue(spike.update(sample(time, memory: 90, compressed: time > 20 ? 100 * 1_048_576 : 0)).active.isEmpty) }
    }
    func testCapacityIsDistinctFromThermal() {
        var engine = AdviceEngine()
        var result = engine.update(sample(0))
        for time in stride(from: 0.0, through: 120, by: 2) { result = engine.update(sample(time, gpu: 95)) }
        expectEqual(result.active.map(\.category), [.capacity])
    }
    func testStorageThresholdsAndDurations() {
        var engine = AdviceEngine()
        for time in stride(from: 0.0, to: 300, by: 2) { expectTrue(engine.update(sample(time, disk: 40)).active.isEmpty) }
        expectEqual(engine.update(sample(300, disk: 40)).active.first?.severity, 1)
        for time in stride(from: 302.0, to: 362, by: 2) { _ = engine.update(sample(time, disk: 4)) }
        expectEqual(engine.update(sample(362, disk: 4)).notifications.first?.severity, 2)
    }
    func testCooldownSnoozeAndEscalation() {
        var engine = AdviceEngine()
        expectTrue(engine.update(sample(0, pressure: .warning), notificationsAllowed: false).notifications.isEmpty)
        expectEqual(engine.update(sample(2, pressure: .warning)).notifications.count, 1)
        expectTrue(engine.update(sample(4, pressure: .warning)).notifications.isEmpty)
        expectEqual(engine.update(sample(6, pressure: .critical)).notifications.count, 1)
        for time in stride(from: 8.0, to: 906, by: 2) { expectTrue(engine.update(sample(time, pressure: .critical)).notifications.isEmpty) }
        expectEqual(engine.update(sample(906, pressure: .critical)).notifications.count, 1)
    }
    func testMissingSensorCannotTriggerCapacity() {
        var engine = AdviceEngine()
        for time in stride(from: 0.0, through: 180, by: 2) { expectTrue(engine.update(sample(time, cpu: nil, gpu: nil)).active.isEmpty) }
    }
    func testStaleDiskCannotTriggerStorage() {
        var engine = AdviceEngine()
        for time in stride(from: 0.0, through: 360, by: 2) {
            var s = sample(time, disk: 1); s.readings[.diskFree]?.timestamp = epoch.addingTimeInterval(-1000)
            expectTrue(engine.update(s).active.isEmpty)
        }
    }
    func testMemoryRecoveryDoesNotRequireLowRAM() {
        var engine = AdviceEngine()
        _ = engine.update(sample(0, pressure: .warning, memory: 95))
        for time in stride(from: 2.0, to: 122, by: 2) { expectEqual(engine.update(sample(time, memory: 95)).active.count, 1) }
        expectTrue(engine.update(sample(122, memory: 95)).active.isEmpty)
    }
    func testClockRollbackResetsContinuity() {
        var engine = AdviceEngine()
        _ = engine.update(sample(100, thermal: .fair)); _ = engine.update(sample(110, thermal: .fair))
        expectTrue(engine.update(sample(90, thermal: .fair)).active.isEmpty)
    }
}
final class ProcessTests: CheckSuite {
    func testExitPIDReuseAndRateReset() {
        var tracker = ProcessTracker()
        func counter(_ birth: UInt64, _ cpu: UInt64) -> ProcessCounter { ProcessCounter(pid: 42, birth: birth, name: "Build", cpuNanoseconds: cpu, footprint: 100) }
        expectNil(tracker.update([counter(1, 0)], time: 0).first?.cpuPercent)
        expectEqual(tracker.update([counter(1, 5_000_000_000)], time: 5).first?.cpuPercent, 100)
        expectNil(tracker.update([counter(2, 6_000_000_000)], time: 10).first?.cpuPercent)
        expectTrue(tracker.update([], time: 15).isEmpty)
        expectNil(tracker.update([counter(2, 7_000_000_000)], time: 20).first?.cpuPercent)
        tracker.reset()
        expectNil(tracker.update([counter(2, 9_000_000_000)], time: 25).first?.cpuPercent)
    }
    func testInvalidReadingRemainsUnavailable() {
        let reading = Reading(.nan, at: Date(), source: "Test", unit: "%")
        expectNil(reading.value); expectNotNil(reading.unavailableReason)
        expectEqual(Metric.cpu.format(nil), "Unavailable")
    }
}
final class HistoryTests: CheckSuite {
    var directory: URL!
    let epoch = Date(timeIntervalSince1970: 1_780_012_800) // UTC midnight
    override func setUpWithError() throws { directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    func sample(_ time: Double, cpu: Double? = 40) -> Snapshot {
        let date = epoch.addingTimeInterval(time)
        return Snapshot(at: date, readings: [.cpu: Reading(cpu, at: date, source: "Test", unit: "%")], thermal: .fair, pressure: .warning)
    }
    func testMinuteBoundaryCoverageAndGap() throws {
        let store = try HistoryStore(url: directory.appendingPathComponent("test.sqlite"))
        for time in stride(from: 0.0, through: 120, by: 2) { try store.record(sample(time)) }
        try store.record(sample(600)); try store.record(sample(602, cpu: nil)); try store.record(sample(604, cpu: nil)); try store.flush()
        let rows = try store.query(from: epoch, to: epoch.addingTimeInterval(1000))
        expectEqual(rows.reduce(0) { $0 + $1.coverage }, 124, accuracy: 0.001)
        expectEqual(rows.reduce(0) { $0 + ($1.metrics[.cpu]?.seconds ?? 0) }, 122, accuracy: 0.001)
        expectEqual(rows.reduce(0) { $0 + ($1.pressureSeconds[2] ?? 0) }, 124, accuracy: 0.001)
        expectTrue(rows.allSatisfy { $0.coverage <= 60 })
    }
    func testRestartAndDailyArchiveAreIdempotent() throws {
        let url = directory.appendingPathComponent("test.sqlite")
        var store: HistoryStore? = try HistoryStore(url: url)
        for time in stride(from: 0.0, through: 120, by: 2) { try store!.record(sample(time)) }
        try store!.flush(); store = nil
        store = try HistoryStore(url: url)
        try store!.maintain(now: epoch.addingTimeInterval(45 * 86400))
        try store!.maintain(now: epoch.addingTimeInterval(45 * 86400))
        let rows = try store!.query(from: epoch, to: epoch.addingTimeInterval(86400))
        expectEqual(rows.count, 1); expectEqual(rows.first?.duration, 86400)
        expectEqual(rows.first?.coverage, 120); expectEqual(rows.first?.metrics[.cpu]?.peak, 40)
    }
    func testExistingMinuteMergesAfterRestart() throws {
        let url = directory.appendingPathComponent("test.sqlite")
        var store: HistoryStore? = try HistoryStore(url: url)
        try store!.record(sample(0)); try store!.record(sample(2)); try store!.flush(); store = nil
        store = try HistoryStore(url: url)
        try store!.record(sample(4, cpu: 80)); try store!.record(sample(6)); try store!.flush()
        let row = try requireValue(store!.query(from: epoch, to: epoch.addingTimeInterval(60)).first)
        expectEqual(row.coverage, 4); expectEqual(row.metrics[.cpu]?.peak, 80)
        expectEqual(row.metrics[.cpu]?.mean, 60)
    }
    func testBudgetPausesWithoutDeletingHistoryAndClearRecovers() throws {
        let url = directory.appendingPathComponent("test.sqlite")
        var store: HistoryStore? = try HistoryStore(url: url)
        try store!.record(sample(0)); try store!.record(sample(2)); try store!.flush(); store = nil
        store = try HistoryStore(url: url, budget: 8192)
        try store!.maintain(now: epoch.addingTimeInterval(4))
        expectNotNil(store!.pausedReason)
        try store!.record(sample(4)); try store!.record(sample(6)); try store!.flush()
        expectEqual(try store!.query(from: epoch, to: epoch.addingTimeInterval(60)).first?.coverage, 2)
        try store!.clear(); expectNil(store!.pausedReason)
        expectTrue(try store!.query(from: epoch, to: epoch.addingTimeInterval(60)).isEmpty)
    }
    func testSleepEventsAndContinuity() throws {
        let store = try HistoryStore(url: directory.appendingPathComponent("test.sqlite"))
        try store.record(sample(0)); try store.record(sample(2)); try store.flush()
        try store.event("Sleep observed", at: epoch.addingTimeInterval(2)); store.resetContinuity()
        try store.event("Wake observed", at: epoch.addingTimeInterval(10))
        try store.record(sample(10)); try store.record(sample(12)); try store.flush()
        expectEqual(try store.query(from: epoch, to: epoch.addingTimeInterval(60)).first?.coverage, 4)
        expectEqual(try store.events(from: epoch, to: epoch.addingTimeInterval(60)).count, 2)
    }
    func testReadOnlyFailureIsReported() throws {
        expectThrows(try HistoryStore(url: URL(fileURLWithPath: "/dev/null/history.sqlite")))
    }
    func testPDFEmptyAndPagination() throws {
        let empty = directory.appendingPathComponent("empty.pdf")
        try PDFReport.write(to: empty, from: epoch, to: epoch.addingTimeInterval(86400), summaries: [], events: [])
        let pdf = try requireValue(PDFDocument(url: empty))
        expectTrue(pdf.string?.contains("no recorded history") == true)
        var rows: [Summary] = []
        for day in 0..<90 { var row = Summary(start: epoch.addingTimeInterval(Double(day) * 86400), duration: 86400); row.add(sample(Double(day) * 86400), seconds: 3600); rows.append(row) }
        let report = directory.appendingPathComponent("large.pdf")
        try PDFReport.write(to: report, from: epoch, to: epoch.addingTimeInterval(90 * 86400), summaries: rows, events: [])
        let large = try requireValue(PDFDocument(url: report))
        expectGreaterThan(large.pageCount, 4)
        expectTrue(large.string?.contains("About this record") == true)
        expectTrue(large.string?.contains("ProcessInfo.thermalState") == true)
    }
}
