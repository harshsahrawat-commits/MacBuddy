import AppKit
import SwiftUI
import MacBuddyCore

// An offscreen export needs a real backing scale. Otherwise SwiftUI text can
// arrive as a one-pixel-per-point layer inside a larger bitmap and look blurred.
private final class RenderCheckWindow: NSWindow {
    static let pixelScale: CGFloat = 3
    override var backingScaleFactor: CGFloat { Self.pixelScale }
}

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
        let names = ["Xcode", "Safari", "WindowServer", "Terminal"]
        let before: [ProcessCounter] = names.enumerated().map { index, name in
            let pid = Int32(index + 10)
            let footprint = UInt64(100 + index * 100) * UInt64(1_048_576)
            return ProcessCounter(pid: pid, birth: 1, name: name, cpuNanoseconds: 0, footprint: footprint)
        }
        _ = tracker.update(before, time: 0)
        let after: [ProcessCounter] = before.enumerated().map { index, process in
            let cpuNanoseconds = UInt64(4 - index) * UInt64(100_000_000)
            return ProcessCounter(pid: process.pid, birth: process.birth, name: process.name, cpuNanoseconds: cpuNanoseconds, footprint: process.footprint)
        }
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
    let scale = RenderCheckWindow.pixelScale
    let view = NSHostingView(rootView: content.environment(\.displayScale, scale).environment(\.controlActiveState, .inactive))
    let window = RenderCheckWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = view
    defer { window.contentView = nil; window.close() }
    view.frame = NSRect(origin: .zero, size: size)
    view.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
    // Let pending SwiftUI text/layout work settle without showing a window.
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    view.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { throw HistoryError.database("Could not allocate overlay render") }
    bitmap.bitmapData?.initialize(repeating: 0, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    bitmap.size = size
    view.cacheDisplay(in: view.bounds, to: bitmap)
    guard let data = bitmap.representation(using: .png, properties: [:]) else { throw HistoryError.database("Could not encode overlay PNG") }
    try data.write(to: url, options: .atomic)
}
