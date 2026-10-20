import AppKit
import MacBuddyCore

if let index = CommandLine.arguments.firstIndex(of: "--render-overlay"), CommandLine.arguments.count > index + 1 {
    let sceneIndex = CommandLine.arguments.firstIndex(of: "--render-scene")
    if let sceneIndex, CommandLine.arguments.count <= sceneIndex + 1 { fputs("Missing render scene.\n", stderr); exit(2) }
    let scene = sceneIndex.map { CommandLine.arguments[$0 + 1] } ?? "normal"
    do { try MainActor.assumeIsolated { try renderOverlayCheck(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]), expanded: !CommandLine.arguments.contains("--collapsed"), reduceTransparency: CommandLine.arguments.contains("--reduce-transparency"), scene: scene) }; exit(0) } catch { fputs("FAIL overlay render: \(error)\n", stderr); exit(1) }
} else if CommandLine.arguments.contains("--runtime-checks") {
    do { try runRuntimeChecks(); exit(0) } catch { fputs("FAIL runtime checks: \(error)\n", stderr); exit(1) }
} else if CommandLine.arguments.contains("--diagnose") {
    let provider = TelemetryProvider()
    for _ in 0..<3 {
        let sample = provider.sample()
        print("Thermal: \(sample.thermal.name); memory pressure: \(sample.pressure.name)")
        for metric in Metric.allCases { print("\(metric.title): \(metric.format(sample[metric])) [\(sample.readings[metric]?.source ?? "unavailable")]") }
        let processes = provider.processes()
        print("Observable processes: \(processes.count)")
        for process in processes.filter({ $0.cpuPercent != nil }).sorted(by: { $0.cpuPercent! > $1.cpuPercent! }).prefix(5) {
            print("CPU consumer: \(process.name) (PID \(process.pid)), \(Metric.cpu.format(process.cpuPercent)) of one core")
        }
        Thread.sleep(forTimeInterval: 1)
    }
    provider.reset()
} else if let index = CommandLine.arguments.firstIndex(of: "--report-fixture"), CommandLine.arguments.count > index + 1 {
    let start = Date(timeIntervalSince1970: floor(1_770_000_000 / 86400.0) * 86400)
    var summaries: [Summary] = []
    for day in 0..<45 {
        let date = start.addingTimeInterval(Double(day) * 86400)
        var sample = Snapshot(at: date, thermal: day % 6 == 0 ? .fair : .nominal, pressure: day % 7 == 0 ? .warning : .normal)
        for (metric, value) in [(Metric.cpu, Double(10 + day)), (.gpu, Double(day % 15)), (.cpuTemperature, 48.5), (.memoryUsed, 11 * 1_073_741_824.0), (.diskFree, 95 * 1_073_741_824.0)] {
            sample.readings[metric] = Reading(value, at: date, source: "Synthetic report layout fixture", unit: metric.unit)
        }
        var summary = Summary(start: date, duration: 86400); summary.add(sample, seconds: Double(2 + day % 6) * 3600); summaries.append(summary)
    }
    do { try PDFReport.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]), from: start, to: start.addingTimeInterval(45 * 86400), summaries: summaries, events: []); print("Synthetic PDF fixture generated.") } catch { fputs("\(error)\n", stderr); exit(1) }
} else if CommandLine.arguments.dropFirst().contains(where: { $0.hasPrefix("--") }) {
    fputs("Unknown or incomplete option. Use --diagnose, --runtime-checks, --report-fixture PATH, or --render-overlay PATH.\n", stderr)
    exit(2)
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
