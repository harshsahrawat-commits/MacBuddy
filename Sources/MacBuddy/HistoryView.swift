import SwiftUI
import Charts
import UniformTypeIdentifiers
import MacBuddyCore

struct HistoryView: View {
    @ObservedObject var model: MonitorModel
    @ViewState private var range = 7
    @ViewState private var from = Calendar.current.startOfDay(for: Date().addingTimeInterval(-7 * 86400))
    @ViewState private var to = Date()
    @ViewState private var reportFrom = Date().addingTimeInterval(-7 * 86400)
    @ViewState private var reportTo = Date()
    @ViewState private var result = HistoryResult()
    @ViewState private var error: String?
    @ViewState private var loading = false
    @ViewState private var exporting = false
    @ViewState private var exported: URL?
    @ViewState private var generation = UUID()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Your recent history").font(ForestStyle.font(23, .semibold))
                    Spacer()
                    Picker("Range", selection: $range) { Text("7 days").tag(7); Text("14 days").tag(14); Text("30 days").tag(30); Text("Custom").tag(0) }.frame(width: 180)
                    Button("Refresh") { load() }.disabled(loading)
                }
                if range == 0 {
                    HStack {
                        DatePicker("From", selection: $from, in: Date().addingTimeInterval(-30 * 86400)...Date(), displayedComponents: .date)
                        DatePicker("Through", selection: $to, in: from...Date(), displayedComponents: .date)
                        Button("Apply") { load() }.disabled(loading)
                    }
                }
                if loading { ProgressView("Loading local history…") }
                if let error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(ForestStyle.warning) }
                if let issue = result.pausedReason { Label(issue, systemImage: "exclamationmark.triangle").foregroundStyle(ForestStyle.warning) }
                if result.summaries.isEmpty && !loading && error == nil {
                    ContentUnavailableView("A fresh start", systemImage: "chart.xyaxis.line", description: Text("History builds as Mac Buddy runs. The first minute will appear shortly."))
                } else if !result.summaries.isEmpty {
                    Text(String(format: "%.2f hours monitored in this range", result.summaries.reduce(0) { $0 + $1.coverage } / 3600)).font(ForestStyle.font(14, .semibold))
                    Text("Charts show hourly averages. Partially observed hours are isolated points; missing hours stay blank. Sampled peaks and pressure durations remain in the archive and reports.").font(ForestStyle.font(11)).foregroundStyle(ForestStyle.secondary)
                    HistoryChart(rows: result.summaries).frame(height: 215)
                    let total = result.summaries.reduce(into: Summary(start: from)) { $0.merge($1) }
                    HStack(spacing: 24) {
                        summary("Peak CPU", Metric.cpu.format(total.metrics[.cpu]?.peak))
                        summary("Peak memory", Metric.memoryUsed.format(total.metrics[.memoryUsed]?.peak))
                        summary("Elevated memory pressure", String(format: "%.1f min", ((total.pressureSeconds[2] ?? 0) + (total.pressureSeconds[4] ?? 0)) / 60))
                    }
                }
                Divider()
                Text("Keep a report").font(ForestStyle.font(19, .semibold))
                Text("Export any recorded period, including older daily archives. Report dates use UTC days; today includes observations up to the export time.").font(ForestStyle.font(13)).foregroundStyle(ForestStyle.secondary)
                HStack {
                    DatePicker("From", selection: $reportFrom, in: ...Date(), displayedComponents: .date)
                    DatePicker("Through", selection: $reportTo, in: reportFrom...Date(), displayedComponents: .date)
                    Button(exporting ? "Exporting…" : "Export PDF…") { export() }.disabled(exporting)
                }.environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
                if let exported { HStack { Label("Report saved", systemImage: "checkmark.circle"); Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([exported]) } } }
                Divider()
                Text("Observed sleep and wake").font(ForestStyle.font(14, .semibold))
                if result.events.isEmpty && !loading && error == nil { Text("No lifecycle observations in this range.").foregroundStyle(ForestStyle.secondary) }
                ForEach(result.events.suffix(20).reversed()) { event in
                    HStack { Text(event.kind); Spacer(); Text(event.timestamp.formatted()).foregroundStyle(ForestStyle.secondary) }.font(ForestStyle.font(13))
                }
                Text("One-minute summaries stay for 30 days; older data becomes daily summaries. The archive budget is 100 MiB including SQLite journal files. Process information is never saved.").font(ForestStyle.font(11)).foregroundStyle(ForestStyle.secondary)
            }.padding(24)
        }.onAppear { load() }.onChange(of: range) { _, _ in load() }
            .onChange(of: model.historyRevision) { _, _ in load() }
            .onChange(of: from) { _, date in if to < date { to = date } }
            .onChange(of: reportFrom) { _, date in if reportTo < date { reportTo = date } }
    }
    private func summary(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(title).font(ForestStyle.font(11)).foregroundStyle(ForestStyle.secondary); Text(value).font(ForestStyle.font(19, .semibold)).monospacedDigit() }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func load() {
        loading = true; error = nil; result = HistoryResult()
        let id = UUID(); generation = id
        let end = range == 0 ? HistoryRange.throughDay(to, calendar: .current, now: Date()) : Date()
        let start = range == 0 ? max(Calendar.current.startOfDay(for: from), Date().addingTimeInterval(-30 * 86400)) : Date().addingTimeInterval(Double(-range) * 86400)
        model.service.loadHistory(from: start, to: end) { response in
            guard generation == id else { return }; loading = false
            switch response { case .success(let value): result = value; case .failure(let failure): error = failure.localizedDescription }
        }
    }
    private func export() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.pdf]; panel.nameFieldStringValue = "Mac-Buddy-report.pdf"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let start = calendar.startOfDay(for: reportFrom)
            let end = HistoryRange.throughDay(reportTo, calendar: calendar, now: Date())
            exporting = true; error = nil; exported = nil
            model.service.loadHistory(from: start, to: end) { response in
                switch response {
                case .failure(let failure): error = failure.localizedDescription; exporting = false
                case .success(let history):
                    DispatchQueue.global(qos: .userInitiated).async {
                        let outcome = Result { try PDFReport.write(to: url, from: start, to: end, summaries: history.summaries, events: history.events) }
                        DispatchQueue.main.async { exporting = false; switch outcome { case .success: exported = url; case .failure(let failure): error = failure.localizedDescription } }
                    }
                }
            }
        }
    }
}
struct HistoryChart: View {
    var rows: [Summary]
    var body: some View {
        Chart(UtilizationChartData.history(rows)) { point in
            LineMark(x: .value("Time", point.date), y: .value("Utilization", point.value), series: .value("Segment", point.series)).foregroundStyle(by: .value("Resource", point.metric.title))
            PointMark(x: .value("Time", point.date), y: .value("Utilization", point.value)).foregroundStyle(by: .value("Resource", point.metric.title)).symbolSize(12)
                .accessibilityLabel("\(point.metric.title), \(point.date.formatted())")
                .accessibilityValue("\(point.metric.format(point.value)), \(Int((point.observedSeconds ?? 0).rounded())) of \(Int((point.intervalSeconds ?? 3600).rounded())) seconds observed")
        }.chartYScale(domain: 0...100).chartForegroundStyleScale(["CPU": ForestStyle.accent, "GPU": ForestStyle.gpu])
    }
}
