import Foundation
import MacBuddyCore

/// Integration check for the actual sampling scheduler, using synthetic data and an isolated database.
/// It never posts system sleep notifications or changes the user's app, preferences, or history.
func runRuntimeChecks() throws {
    final class FixtureProvider: MetricProviding {
        let lock = NSLock()
        private var resets = 0
        private var processReads = 0
        func sample(at date: Date) -> Snapshot {
            Snapshot(at: date, readings: [.cpu: Reading(25, at: date, source: "Runtime fixture", unit: "%")], thermal: .nominal, pressure: .normal)
        }
        func processes() -> [ProcessReading] { lock.lock(); processReads += 1; lock.unlock(); return [] }
        func reset() { lock.lock(); resets += 1; lock.unlock() }
        var counters: (Int, Int) { lock.lock(); defer { lock.unlock() }; return (resets, processReads) }
    }
    func verify(_ condition: Bool, _ message: String) throws { if !condition { throw HistoryError.database(message) } }
    func pump(_ seconds: Double) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { RunLoop.main.run(until: min(end, Date().addingTimeInterval(0.05))) }
    }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("MacBuddy-runtime-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let provider = FixtureProvider()
    let service = SamplingService(provider: provider, historyURL: root.appendingPathComponent("history.sqlite"))
    var samples: [Snapshot] = []
    var errors: [String] = []
    service.onSample = { sample, _, _, _, _, error, notices in
        samples.append(sample)
        if let error { errors.append(error) }
        if !notices.isEmpty { errors.append("Unexpected notification from nominal fixture") }
    }
    service.start()
    defer { service.stop() }
    pump(6.4)
    try verify(samples.count >= 3 && samples.count <= 4, "Collapsed cadence was not approximately two seconds")
    try verify(provider.counters.1 == 2, "Processes were not sampled independently every five seconds")
    let slow = samples.count
    service.configure(details: true, samplingMode: "Adaptive", notifications: false, snooze: .distantPast)
    pump(3.3)
    try verify(samples.count - slow >= 3, "Opening details did not switch to one-second sampling")
    service.sleep(); pump(0.3)
    let sleepingCount = samples.count
    let processCount = provider.counters.1
    pump(2.3)
    try verify(samples.count == sleepingCount && provider.counters.1 == processCount, "Sampling continued during simulated sleep")
    service.wake(); pump(2.3)
    try verify(samples.count > sleepingCount && provider.counters.0 >= 2, "Wake did not reset rates and resume sampling")
    var result: Result<HistoryResult, Error>?
    service.loadHistory(from: .distantPast, to: .distantFuture) { result = $0 }
    pump(0.3)
    guard let result else { throw HistoryError.database("History completion did not reach the main run loop") }
    let history = try result.get()
    try verify(history.events.contains(where: { $0.kind == "Sleep observed" }) && history.events.contains(where: { $0.kind == "Wake observed" }), "Sleep/wake events missing from history")
    try verify(history.summaries.reduce(0) { $0 + $1.coverage } <= 12, "Simulated sleep was counted as observed coverage")
    try verify(errors.isEmpty, errors.joined(separator: "; "))
    print("PASS live scheduler integration: 2s collapsed, 1s detail, independent 5s processes, suspended timers during simulated sleep, rate reset/resume and persisted wake gap")
}
