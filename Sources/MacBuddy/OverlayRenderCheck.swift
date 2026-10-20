import AppKit
import SwiftUI
import MacBuddyCore

// Offscreen render: does not start monitoring, request permissions, or change preferences.
@MainActor func renderOverlayCheck(to url: URL, expanded: Bool = true, reduceTransparency: Bool = false, scene: String = "normal") throws {
    _ = NSApplication.shared
    let defaults = UserDefaults(suiteName: "app.macbuddy.render-" + UUID().uuidString)!
    defaults.register(defaults: ["notifications": false, "samplingMode": "Adaptive"])
    let model = MonitorModel(defaults: defaults, persistOverlayPreferences: false)
    model.overlayPreferences = OverlayPreferences()
    guard ["normal","cpu","memory","recovering","recovered","unavailable","processes","avatar","vertical","dashboard","settings"].contains(scene) else { throw HistoryError.database("Unknown render scene") }
    let date = Date(timeIntervalSince1970: 1_790_000_000)
    var engine = AdviceEngine()
    for second in stride(from: 0, through: scene == "recovered" ? 242 : scene == "recovering" ? 180 : 120, by: 2) {
    let time = date.addingTimeInterval(Double(second))
    let busy = scene == "cpu" || (["recovering","recovered"].contains(scene) && second <= 120)
    model.sample = Snapshot(at: time, readings: [
        .cpu: Reading(scene == "unavailable" ? nil : busy ? 95 : 12, at: time, source: "Fixture", unit: "%"),
        .gpu: Reading(scene == "unavailable" ? nil : 6, at: time, source: "Fixture", unit: "%"),
        .cpuTemperature: Reading(41.8, at: date, source: "Fixture", unit: "°C"),
        .gpuTemperature: Reading(36.4, at: date, source: "Fixture", unit: "°C"),
        .memoryUsed: Reading(scene == "unavailable" ? nil : 10 * 1_073_741_824, at: time, source: "Fixture", unit: "B"),
        .memoryTotal: Reading(16 * 1_073_741_824, at: time, source: "Fixture", unit: "B"),
        .compressed: Reading(0, at: time, source: "Fixture", unit: "B"),
        .swapRate: Reading(0, at: time, source: "Fixture", unit: "B/s"),
        .battery: Reading(27, at: date, source: "Fixture", unit: "%")
    ], thermal: .nominal, pressure: scene == "memory" ? .warning : .normal, batteryInfo: .init(powerSource: "Battery Power"))
    model.advice = engine.update(model.sample).active
    model.updateCompanion(model.sample, advice: model.advice)
    model.recent.append(model.sample)
    }
    if scene == "processes" {
        var tracker = ProcessTracker()
        let before = (0..<4).map { ProcessCounter(pid: Int32($0+10), birth: 1, name: ["Xcode","Safari","WindowServer","Terminal"][$0], cpuNanoseconds: 0, footprint: UInt64(100+$0*100)*1_048_576) }
        _ = tracker.update(before, time: 0)
        let after = before.enumerated().map { index, p in ProcessCounter(pid: p.pid, birth: p.birth, name: p.name, cpuNanoseconds: UInt64(4-index)*100_000_000, footprint: p.footprint) }
        model.processes = tracker.update(after, time: 1)
    }
    model.expanded = expanded
    if scene == "avatar" { model.overlayPreferences.style = .avatar; model.floatingLayout = .avatar; model.expanded = false }
    if scene == "vertical" { model.overlayPreferences.dockedEdge = .left; model.floatingLayout = .vertical; model.expanded = false }
    let content: AnyView
    let size: CGSize
    if scene == "dashboard" { content = AnyView(DashboardView(model: model)); size = CGSize(width: 960, height: 790) }
    else if scene == "settings" { content = AnyView(SettingsView(model: model)); size = CGSize(width: 680, height: 760) }
    else {
        content = AnyView(OverlayView(model: model, forceOpaque: reduceTransparency, initialTab: scene == "processes" ? "Processes" : "Overview"))
        size = model.expanded ? OverlayGeometry.expandedSize : OverlayGeometry.size(for: model.floatingLayout)
    }
    let view = NSHostingView(rootView: content.environment(\.controlActiveState, .inactive))
    view.frame = NSRect(origin: .zero, size: size)
    view.layoutSubtreeIfNeeded()
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw HistoryError.database("Could not allocate overlay render") }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    guard let data = bitmap.representation(using: .png, properties: [:]) else { throw HistoryError.database("Could not encode overlay PNG") }
    try data.write(to: url, options: .atomic)
}
