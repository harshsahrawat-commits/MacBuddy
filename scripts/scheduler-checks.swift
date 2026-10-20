import Foundation
import MacBuddyCore

// Compiled with the real MonitorModel.swift. All data goes to disposable fixtures;
// this never constructs MonitorModel, requests notifications or opens a window.
@main
enum SchedulerAcceptance {
    final class Provider: MetricProviding {
        private let lock = NSLock()
        private var reads = 0
        private var resets = 0
        func sample(at date: Date) -> Snapshot {
            Snapshot(at: date, readings: [.cpu: Reading(25, at: date, source: "Scheduler acceptance fixture", unit: "%")], thermal: .nominal, pressure: .normal)
        }
        func processes() -> [ProcessReading] { lock.lock(); reads += 1; lock.unlock(); return [] }
        func reset() { lock.lock(); resets += 1; lock.unlock() }
        var counts: (processes: Int, resets: Int) { lock.lock(); defer { lock.unlock() }; return (reads, resets) }
    }
    static func pump(_ seconds: Double) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline { RunLoop.main.run(until: min(deadline, Date().addingTimeInterval(0.05))) }
    }
    static func check(_ condition: @autoclosure () -> Bool, _ text: String) throws {
        guard condition() else { throw NSError(domain: "SchedulerAcceptance", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
    }
    static func cadence(_ dates: ArraySlice<Date>, expected: Double) throws {
        try check(dates.count >= 2, "Insufficient samples to verify cadence")
        for (a, b) in zip(dates, dates.dropFirst()) {
            try check(abs(b.timeIntervalSince(a) - expected) < 0.6, "Unexpected cadence: \(b.timeIntervalSince(a)) instead of \(expected)")
        }
    }
    static func history(_ service: SamplingService) throws -> HistoryResult {
        var result: Result<HistoryResult, Error>?
        service.loadHistory(from: .distantPast, to: .distantFuture) { result = $0 }
        pump(0.3)
        guard let result else { throw NSError(domain: "SchedulerAcceptance", code: 2, userInfo: [NSLocalizedDescriptionKey: "History callback not delivered"]) }
        return try result.get()
    }
    static func run() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MacBuddy-scheduler-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let provider = Provider()
        let service = SamplingService(provider: provider, historyURL: root.appendingPathComponent("history.sqlite"))
        var dates: [Date] = []
        var recentCount = 0
        var allCallbacksOnMain = true
        var errors: [String] = []
        service.onSample = { sample, _, _, points, _, error, notices in
            dates.append(sample.timestamp); recentCount = points.count
            allCallbacksOnMain = allCallbacksOnMain && Thread.isMainThread
            if let error { errors.append(error) }
            if !notices.isEmpty { errors.append("Nominal fixture produced notification") }
        }
        service.start()
        defer { service.stop() }
        service.configure(details: false, samplingMode: "Eco", notifications: false, snooze: .distantPast)
        pump(11.2)
        try cadence(dates.suffix(3), expected: 5)
        try check(recentCount == 0, "Collapsed mode published chart samples")
        try check(provider.counts.processes >= 3, "Eco process refresh stopped")
        service.configure(details: true, samplingMode: "Eco", notifications: false, snooze: .distantPast)
        pump(5.3)
        try cadence(dates.suffix(2), expected: 5)
        try check(recentCount >= 3, "Opening details did not expose retained samples")
        print("PASS Eco stays at 5s with details open; collapsed callbacks omit chart data")

        var start = dates.count
        service.configure(details: true, samplingMode: "Steady", notifications: false, snooze: .distantPast)
        pump(4.4)
        try cadence(dates.dropFirst(start), expected: 2)
        start = dates.count
        service.configure(details: true, samplingMode: "Adaptive", notifications: false, snooze: .distantPast)
        pump(3.4)
        try cadence(dates.dropFirst(start), expected: 1)
        print("PASS Steady uses 2s even in details; Adaptive returns to 1s")

        service.sleep(); pump(0.3)
        let sleepingSamples = dates.count, sleepingProcesses = provider.counts.processes
        service.configure(details: false, samplingMode: "Eco", notifications: false, snooze: .distantPast)
        pump(5.3)
        try check(dates.count == sleepingSamples && provider.counts.processes == sleepingProcesses, "Reconfiguration restarted a sleeping timer")
        let resets = provider.counts.resets
        service.wake(); pump(5.4)
        try cadence(dates.dropFirst(sleepingSamples), expected: 5)
        try check(provider.counts.resets > resets, "Wake did not reset source counters")
        try check(recentCount == 0, "Hidden details published chart data")
        let resumedHistory = try history(service)
        try check(resumedHistory.summaries.reduce(0) { $0 + $1.coverage } > 0, "Hidden/closed details stopped persistence")
        print("PASS mode change during sleep stays suspended; wake respects Eco and persistence continues")

        var cleared = false
        var clearIssue: String?
        service.clearHistory { clearIssue = $0; cleared = true }
        pump(0.3)
        try check(cleared && clearIssue == nil, "Isolated history clear failed")
        let empty = try history(service)
        try check(empty.summaries.isEmpty, "Clear left old summaries")
        service.configure(details: true, samplingMode: "Eco", notifications: false, snooze: .distantPast)
        pump(5.3)
        try check(recentCount > 0 && recentCount <= 2, "Clear retained old chart samples")
        try check(allCallbacksOnMain && errors.isEmpty, "Callback thread or sampling error: \(errors)")
        service.stop(); pump(0.3)
        let stoppedSamples = dates.count, stoppedProcesses = provider.counts.processes
        pump(5.3)
        try check(dates.count == stoppedSamples && provider.counts.processes == stoppedProcesses, "Stop left a timer running")
        print("PASS isolated clear resets archive/charts; main-thread callbacks and timer shutdown")

        let blocker = root.appendingPathComponent("blocked")
        try Data("test-only blocking file".utf8).write(to: blocker)
        let recovering = SamplingService(provider: Provider(), historyURL: blocker.appendingPathComponent("history.sqlite"))
        var latestError: String?
        var callbacks = 0
        recovering.onSample = { _, _, _, _, _, error, _ in callbacks += 1; latestError = error }
        recovering.start()
        defer { recovering.stop() }
        pump(2.3)
        try check(callbacks >= 2 && latestError != nil, "Archive failure was not reported while monitoring continued")
        try FileManager.default.removeItem(at: blocker)
        recovering.retryHistory(); pump(2.3)
        try check(latestError == nil, "Retry did not clear archive error")
        _ = try history(recovering)
        print("PASS archive failure preserves monitoring; retry recovers after the obstacle is removed")
    }
    static func main() {
        do { try run() } catch { fputs("FAIL scheduler acceptance: \(error.localizedDescription)\n", stderr); exit(1) }
    }
}
