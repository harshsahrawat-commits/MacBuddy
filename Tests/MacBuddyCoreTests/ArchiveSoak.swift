import Foundation
import MacBuddyCore

func runArchiveSoak() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("MacBuddy-archive-soak-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let start = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01 UTC
    let began = Date()
    let store = try HistoryStore(url: root.appendingPathComponent("history.sqlite"))
    for minute in 0..<(32 * 1440) {
        let date = start.addingTimeInterval(Double(minute) * 60)
        var readings: [Metric: Reading] = [:]
        for metric in Metric.allCases {
            let value: Double
            switch metric {
            case .cpu, .gpu: value = Double(minute % 100)
            case .cpuTemperature, .gpuTemperature: value = 40 + Double(minute % 30)
            case .memoryUsed: value = 10 * 1_073_741_824
            case .memoryTotal: value = 16 * 1_073_741_824
            case .diskFree: value = 100 * 1_073_741_824
            case .diskTotal: value = 500 * 1_073_741_824
            case .battery: value = 80
            case .uptime: value = Double(minute) * 60
            default: value = 1_073_741_824
            }
            readings[metric] = Reading(value, at: date, source: "Synthetic archive validation", unit: metric.unit)
        }
        var sample = Snapshot(at: date, readings: readings, thermal: minute % 10 == 0 ? .fair : .nominal, pressure: minute % 20 == 0 ? .warning : .normal)
        try store.record(sample)
        sample.timestamp = date.addingTimeInterval(2)
        try store.record(sample)
        if let reason = store.pausedReason { throw HistoryError.database("Archive paused during simulated day \(minute / 1440 + 1): \(reason)") }
        if minute % 1440 == 0 { print("Archive soak: day \(minute / 1440 + 1), \(store.diskUsage / 1_048_576) MiB"); fflush(stdout) }
    }
    try store.flush()
    let end = start.addingTimeInterval(32 * 86400)
    try store.maintain(now: end)
    let rows = try store.query(from: start, to: end)
    let daily = rows.filter { $0.duration == 86400 }
    let minutes = rows.filter { $0.duration == 60 }
    let coverage = rows.reduce(0) { $0 + $1.coverage }
    guard daily.count == 2, minutes.count == 30 * 1440, abs(coverage - 32 * 1440 * 2) < 0.001, store.diskUsage <= store.budget, store.pausedReason == nil else {
        throw HistoryError.database("Archive validation failed: \(daily.count) days / \(minutes.count) minutes / \(coverage) seconds / \(store.diskUsage) bytes")
    }
    try store.maintain(now: end)
    let repeated = try store.query(from: start, to: end)
    guard repeated.reduce(0, { $0 + $1.coverage }) == coverage else { throw HistoryError.database("Repeated maintenance duplicated coverage.") }
    print(String(format: "PASS 32-day archive simulation: %d daily + %d minute summaries, %.0f seconds coverage, %.2f MiB including journals, %.1fs elapsed", daily.count, minutes.count, coverage, Double(store.diskUsage) / 1_048_576, Date().timeIntervalSince(began)))
}
