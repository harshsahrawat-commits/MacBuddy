import SwiftUI
import Charts
import MacBuddyCore

struct DashboardView: View {
    @ObservedObject var model: MonitorModel
    @ViewState private var tab = "Now"
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                CompanionBadge(model: model)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Mac Buddy").font(ForestStyle.font(23, .semibold))
                    Text("A little clarity for your Mac.").font(ForestStyle.font(13)).foregroundStyle(ForestStyle.secondary)
                }
                Spacer()
                ForestSegments(title: "Dashboard view", options: [("Right now", "Now"), ("History & reports", "History")], selection: $tab)
                Button { model.openSettings?() } label: { Image(systemName: "gearshape") }.help("Settings").accessibilityLabel("Settings")
            }.padding(24)
            Divider()
            if tab == "Now" { overview } else { HistoryView(model: model) }
        }.frame(minWidth: 780, minHeight: 620).modifier(ForestWindowStyle())
    }
    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.companion.heading).font(ForestStyle.font(29, .semibold))
                        Label("macOS thermal state: \(model.sample.thermal.name)", systemImage: "thermometer.medium").font(ForestStyle.font(13)).foregroundStyle(ForestStyle.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 5) {
                        Text("LIVE · \(model.sample.timestamp.formatted(date: .omitted, time: .standard))").font(ForestStyle.font(11)).monospacedDigit().foregroundStyle(ForestStyle.secondary)
                        Text("\(model.sample.batteryInfo.powerSource) · \(Metric.battery.format(model.sample[.battery]))").font(ForestStyle.font(11)).foregroundStyle(ForestStyle.secondary)
                    }
                }
                HStack(spacing: 12) {
                    MetricTile(metric: .cpu, sample: model.sample, subtitle: "\(Metric.cpuTemperature.format(model.sample[.cpuTemperature])) · sensor mean")
                    MetricTile(metric: .gpu, sample: model.sample, subtitle: "\(Metric.gpuTemperature.format(model.sample[.gpuTemperature])) · sensor mean")
                    MetricTile(metric: .memoryUsed, sample: model.sample, subtitle: "\(Metric.memoryUsed.format(model.sample[.memoryUsed])) of \(Metric.memoryTotal.format(model.sample[.memoryTotal])) · \(model.sample.pressure.name) pressure", title: "RAM", usesMemoryPercent: true)
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Text("Recent activity").font(ForestStyle.font(14, .semibold)); Spacer(); Text("Last hour · missing data stays a gap").font(ForestStyle.font(11)).foregroundStyle(ForestStyle.secondary) }
                    LiveChart(snapshots: model.recent).frame(height: 145)
                }
                VStack(alignment: .leading, spacing: 10) { AdviceList(model: model) }
                HStack {
                    Button("Open Activity Monitor", action: model.openActivityMonitor)
                    Button("Review storage", action: model.openStorageSettings)
                    Spacer()
                    Text("Advice only. You stay in control.").font(ForestStyle.font(11)).foregroundStyle(ForestStyle.secondary)
                }
                Divider()
                ProcessList(model: model)
                Divider()
                Grid(alignment: .leading, horizontalSpacing: 32, verticalSpacing: 10) {
                    GridRow { detail("Compressed", Metric.compressed.format(model.sample[.compressed])); detail("Swap used", Metric.swapUsed.format(model.sample[.swapUsed])); detail("Swap-out activity", Metric.swapRate.format(model.sample[.swapRate])) }
                    GridRow { detail("Storage available", Metric.diskFree.format(model.sample[.diskFree])); detail("Uptime", Metric.uptime.format(model.sample[.uptime])); detail("Battery condition", model.sample.batteryInfo.condition ?? "Unavailable") }
                    GridRow { detail("Battery cycles", model.sample.batteryInfo.cycleCount.map(String.init) ?? "Unavailable"); detail("Maximum capacity", model.sample.batteryInfo.maximumCapacityPercent.map { String(format: "%.0f%%", $0) } ?? "Not reported"); detail("Archive", String(format: "%.2f MiB / 100 MiB", Double(model.archiveBytes) / 1_048_576)) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if let issue = model.historyIssue { Label(issue, systemImage: "exclamationmark.triangle").foregroundStyle(ForestStyle.warning).font(ForestStyle.font(13)) }
                Text("Internal temperature readings are informational. Thermal wording follows macOS; it does not use invented Celsius bands. High RAM use, existing swap, or long uptime alone do not mean your Mac is unhealthy.").font(ForestStyle.font(11)).foregroundStyle(ForestStyle.secondary)
            }.padding(24)
        }
    }
    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(label).font(ForestStyle.font(11)).foregroundStyle(ForestStyle.secondary); Text(value).font(ForestStyle.font(13)).monospacedDigit() }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct LiveChart: View {
    var snapshots: [Snapshot]
    var body: some View {
        let points = UtilizationChartData.live(snapshots)
        if points.isEmpty {
            ContentUnavailableView("Collecting activity", systemImage: "waveform.path", description: Text("Live readings appear after a few samples."))
        } else {
            Chart(points) { point in
                LineMark(x: .value("Time", point.date), y: .value("Utilization", point.value), series: .value("Continuous segment", point.series))
                    .foregroundStyle(by: .value("Resource", point.metric.title)).lineStyle(StrokeStyle(lineWidth: 1.5))
                if point.isolated {
                    PointMark(x: .value("Time", point.date), y: .value("Utilization", point.value))
                        .foregroundStyle(by: .value("Resource", point.metric.title)).symbolSize(12)
                }
            }.chartYScale(domain: 0...100).chartForegroundStyleScale(["CPU": ForestStyle.accent, "GPU": ForestStyle.gpu])
                .chartYAxis { AxisMarks(values: [0, 50, 100]) { value in AxisGridLine(); AxisValueLabel { if let number = value.as(Int.self) { Text("\(number)%") } } } }
                .accessibilityLabel("CPU and GPU utilization for the last hour")
        }
    }
}
struct ProcessList: View {
    @ObservedObject var model: MonitorModel
    @ViewState private var sortByMemory = false
    private var top: [ProcessReading] {
        Array(model.processes.sorted { sortByMemory ? $0.memoryBytes > $1.memoryBytes : ($0.cpuPercent ?? -1) > ($1.cpuPercent ?? -1) }.prefix(7))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Largest observable processes").font(ForestStyle.font(14, .semibold))
                Spacer()
                ForestSegments(title: "Sort processes", options: [("CPU", false), ("Memory", true)], selection: $sortByMemory)
            }
            if top.isEmpty { Text("Process information is unavailable or still loading.").foregroundStyle(ForestStyle.secondary) }
            else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 7) {
                    GridRow { Text("Process").frame(maxWidth: .infinity, alignment: .leading); Text("PID"); Text("CPU¹").frame(width: 80, alignment: .trailing); Text("Memory").frame(width: 90, alignment: .trailing) }.font(ForestStyle.font(11)).foregroundStyle(ForestStyle.secondary)
                    ForEach(top) { process in
                        GridRow {
                            Text(process.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            Text(String(process.pid)).foregroundStyle(ForestStyle.secondary)
                            Text(Metric.cpu.format(process.cpuPercent)).frame(width: 80, alignment: .trailing)
                            Text(String(format: "%.0f MiB", Double(process.memoryBytes) / 1_048_576)).frame(width: 90, alignment: .trailing)
                        }.font(ForestStyle.font(12)).monospacedDigit()
                    }
                }
            }
            Text("¹ 100% equals one CPU core. Updated every 5 seconds. Names and resource counts stay in memory; commands and content are never read.").font(ForestStyle.font(11)).foregroundStyle(ForestStyle.secondary)
        }
    }
}
