import AppKit
import CoreGraphics

public enum PDFReport {
    public static func write(to url: URL, from: Date, to: Date, summaries: [Summary], events: [HistoryEvent]) throws {
        guard to > from else { throw HistoryError.database("The report end must follow its start.") }
        let document = PDFWriter()
        let total = summaries.reduce(into: Summary(start: from, duration: to.timeIntervalSince(from))) { $0.merge($1) }
        let span = to.timeIntervalSince(from)
        let coverage = min(span, total.coverage)
        let formatter = DateFormatter(); formatter.dateFormat = "dd MMM yyyy"; formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let range = "\(formatter.string(from: from)) - \(formatter.string(from: to.addingTimeInterval(-1))) (UTC)"
        document.heading("Mac Buddy", size: 29)
        document.text("Your Mac, in perspective", size: 15, color: .darkGray)
        document.text(range, size: 11, color: .darkGray)
        document.space(14)
        document.heading("Observed coverage")
        document.text(String(format: "%.1f hours monitored  /  %.1f hours in selected range  /  %.1f%% coverage", coverage / 3600, span / 3600, coverage / span * 100), size: 12)
        document.text(String(format: "%.1f hours were not observed. Gaps include sleep, app downtime, missing samples, and pauses in recording. Missing observations are not zero utilization.", max(0, span - coverage) / 3600))
        if summaries.isEmpty { document.text("There is no recorded history in this range. Leave Mac Buddy running to collect local observations.") }
        document.space(10)
        document.heading("Resource trends and peaks")
        document.text("Averages are weighted by observed time. Peaks are sampled peaks, not continuous maximums. Sensor values are available only where the adapter returned validated data.", size: 10, color: .darkGray)
        for metric in [Metric.cpu, .gpu, .cpuTemperature, .gpuTemperature, .memoryUsed, .compressed, .swapUsed, .swapRate, .diskFree, .battery] {
            document.ensureSpace(46)
            let stat = total.metrics[metric]
            let label = metric == .diskFree ? "Minimum" : "Peak"
            document.row(metric.title, "Average \(metric.format(stat?.mean))  |  \(label) \(metric.format(metric == .diskFree ? stat?.minimum : stat?.peak))")
            let available = stat?.seconds ?? 0
            document.text(String(format: "Source coverage: %.1f h", available / 3600), size: 9, color: .darkGray, spacing: 3)
        }
        document.space(10)
        document.ensureSpace(245)
        document.heading("Thermal conditions and memory pressure")
        for thermal in Thermal.allCases {
            document.row("Thermal: \(thermal.name)", minutes(total.thermalSeconds[thermal.rawValue] ?? 0))
        }
        for pressure in [Pressure.normal, .warning, .critical, .unknown] {
            document.row("Memory: \(pressure.name)", minutes(total.pressureSeconds[pressure.rawValue] ?? 0))
        }
        document.text("Thermal states come from ProcessInfo.thermalState. Internal Celsius readings do not determine these categories. Apple's 10-35 C operating specification describes ambient air, not CPU or GPU temperature.", size: 10, color: .darkGray)
        document.space(12)
        document.heading("Practical recommendations")
        var recommendations: [String] = []
        if (total.thermalSeconds[Thermal.fair.rawValue] ?? 0) + (total.thermalSeconds[Thermal.serious.rawValue] ?? 0) + (total.thermalSeconds[Thermal.critical.rawValue] ?? 0) > 0 {
            recommendations.append("Thermal pressure was observed. During demanding sessions, reduce concurrent builds and use a hard, ventilated surface.")
        }
        if (total.pressureSeconds[Pressure.warning.rawValue] ?? 0) + (total.pressureSeconds[Pressure.critical.rawValue] ?? 0) > 0 {
            recommendations.append("Elevated memory pressure was observed. Review Activity Monitor when responsiveness drops; reduce simultaneous resource-heavy sessions.")
        }
        if (total.metrics[.cpu]?.mean ?? 0) > 80 || (total.metrics[.gpu]?.mean ?? 0) > 80 {
            recommendations.append("Average utilization was high during monitored periods. Stagger heavy tasks if interactive work slows down.")
        }
        if let free = total.metrics[.diskFree]?.minimum, free < max(20 * 1_073_741_824, (total.metrics[.diskTotal]?.mean ?? 0) * 0.1) {
            recommendations.append("Available storage dipped below Mac Buddy's low-space heuristic. Review System Settings > Storage.")
        }
        if recommendations.isEmpty { recommendations.append("No additional recommendation follows from the available summaries. Continue monitoring during your normal coding sessions.") }
        for (i, text) in recommendations.enumerated() { document.text("\(i+1). \(text)") }
        document.text("These are responsiveness heuristics, not a diagnosis of hardware damage. Existing swap, high RAM use, and long uptime alone do not imply poor health. Mac Buddy never stops workloads automatically.", size: 10, color: .darkGray)
        document.space(12)
        document.heading("Daily observations")
        document.text("UTC day boundaries. Recent minute summaries are combined for this table; older records are daily archives. Days without observations are absent. Source-specific gaps are excluded from each average.", size: 10, color: .darkGray)
        var daily: [Int64: Summary] = [:]
        for row in summaries {
            let key = Int64(floor(row.start.timeIntervalSince1970 / 86400) * 86400)
            if daily[key] == nil { daily[key] = Summary(start: Date(timeIntervalSince1970: Double(key)), duration: 86400) }
            daily[key]!.merge(row)
        }
        for key in daily.keys.sorted() {
            document.ensureSpace(56)
            let day = daily[key]!
            document.row(formatter.string(from: day.start), String(format: "%.2f h observed", day.coverage / 3600))
            document.text("CPU avg \(Metric.cpu.format(day.metrics[.cpu]?.mean)), peak \(Metric.cpu.format(day.metrics[.cpu]?.peak)); GPU avg \(Metric.gpu.format(day.metrics[.gpu]?.mean)); memory peak \(Metric.memoryUsed.format(day.metrics[.memoryUsed]?.peak)).", size: 10)
        }
        if !events.isEmpty {
            document.space(12); document.heading("Recent lifecycle observations")
            let eventFormatter = DateFormatter(); eventFormatter.dateFormat = "dd MMM HH:mm:ss 'UTC'"; eventFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            for event in events { document.row(eventFormatter.string(from: event.timestamp), event.kind) }
        }
        document.space(12); document.heading("About this record")
        document.text("Stored locally by Mac Buddy. Process names and identifiers are never included in history. Recent history has one-minute resolution; after 30 days it is aggregated to whole UTC days. App lifecycle timestamps are retained for 30 days. One unfinished minute may be lost after an unexpected app termination.", size: 10)
        document.text("Sources: Mach CPU/VM statistics; sysctl memory/swap; ProcessInfo thermal state; IOPowerSources; startup volume capacity. CPU/GPU temperatures use an isolated read-only M4 AppleSMC adapter, and GPU utilization uses AGX IORegistry data. Those undocumented sources can become unavailable after OS updates.", size: 10)
        document.text("Apple thermal guidance: developer.apple.com/documentation/foundation/processinfo/thermalstate\nM4 MacBook Air specifications: support.apple.com/en-us/122209\nTemperature guidance: support.apple.com/en-us/102336", size: 9, color: .darkGray)
        try document.finish(to: url)
    }
    private static func minutes(_ seconds: Double) -> String { String(format: "%.1f minutes", seconds / 60) }
}

private final class PDFWriter {
    private let data = NSMutableData()
    private let context: CGContext
    private var y: CGFloat = 0
    private var page = 0
    private let width: CGFloat = 595.28
    private let height: CGFloat = 841.89
    private let margin: CGFloat = 48
    private var previousContext: NSGraphicsContext?
    init() {
        var box = CGRect(x: 0, y: 0, width: width, height: height)
        let consumer = CGDataConsumer(data: data as CFMutableData)!
        context = CGContext(consumer: consumer, mediaBox: &box, [kCGPDFContextTitle: "Mac Buddy activity report", kCGPDFContextCreator: "Mac Buddy"] as CFDictionary)!
        previousContext = NSGraphicsContext.current
        nextPage()
    }
    private func nextPage() {
        if page > 0 { endPage() }
        context.beginPDFPage(nil); context.saveGState()
        context.translateBy(x: 0, y: height); context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        page += 1; y = margin
        if page > 1 { text("MAC BUDDY  /  ACTIVITY REPORT", size: 9, color: .darkGray); space(10) }
    }
    private func endPage() {
        let footer = "Mac Buddy  |  Local report                                              \(page)"
        (footer as NSString).draw(at: CGPoint(x: margin, y: height - 34), withAttributes: [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.darkGray])
        context.restoreGState(); context.endPDFPage()
    }
    func space(_ amount: CGFloat) { y += amount }
    func ensureSpace(_ amount: CGFloat) { if y + amount > height - margin { nextPage() } }
    func heading(_ value: String, size: CGFloat = 16) {
        if y + 65 > height - margin { nextPage() }
        text(value, size: size, weight: .semibold, spacing: 10)
    }
    func text(_ value: String, size: CGFloat = 11, weight: NSFont.Weight = .regular, color: NSColor = .black, spacing: CGFloat = 8) {
        let style = NSMutableParagraphStyle(); style.lineSpacing = 3
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style]
        let bounds = (value as NSString).boundingRect(with: CGSize(width: width - margin * 2, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs)
        let textHeight = ceil(bounds.height) + 2
        if y + textHeight > height - margin { nextPage() }
        (value as NSString).draw(with: CGRect(x: margin, y: y, width: width - margin * 2, height: textHeight), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs)
        y += textHeight + spacing
    }
    func row(_ title: String, _ value: String) {
        text(title + "  |  " + value, size: 10, spacing: 5)
    }
    func finish(to url: URL) throws {
        endPage(); context.closePDF(); NSGraphicsContext.current = previousContext
        try (data as Data).write(to: url, options: .atomic)
    }
}
