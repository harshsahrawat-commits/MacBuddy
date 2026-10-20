import SwiftUI
import MacBuddyCore

struct OverlayView: View {
    @ObservedObject var model: MonitorModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    var forceOpaque = false
    @ViewState private var tab = "Overview"
    @ViewState private var sortMemory = false
    init(model: MonitorModel, forceOpaque: Bool = false, initialTab: String = "Overview") {
        self.model = model; self.forceOpaque = forceOpaque
        _tab = ViewState(initialValue: initialTab)
    }
    private var opacity: Double { reduceTransparency || contrast == .increased || forceOpaque ? 1 : model.overlayPreferences.sanitized.backgroundOpacity }
    var body: some View {
        VStack(spacing: 0) {
            if !model.expanded && model.floatingLayout == .avatar { avatarOnly }
            else if !model.expanded && model.floatingLayout == .vertical { verticalStrip }
            else { strip }
            if model.expanded {
                Divider().overlay(ForestStyle.line)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 18) {
                        ForEach(["Overview", "Processes"], id: \.self) { name in
                            Button { tab = name } label: {
                                Text(name).font(ForestStyle.font(12, .semibold))
                                    .foregroundStyle(tab == name ? ForestStyle.text : ForestStyle.secondary)
                                    .padding(.vertical, 8)
                                    .overlay(alignment: .bottom) { if tab == name { Rectangle().fill(ForestStyle.accent).frame(height: 2) } }
                            }.buttonStyle(.plain).accessibilityAddTraits(tab == name ? .isSelected : [])
                        }
                        Spacer()
                    }
                    ScrollView {
                        if tab == "Overview" { overview } else { processes }
                    }.scrollIndicators(.hidden).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    footer
                    Button { model.companionReply = nil; model.openDashboard?() } label: {
                        HStack { Text("Open dashboard"); Spacer(); Image(systemName: "arrow.up.right") }.frame(maxWidth: .infinity)
                    }.buttonStyle(ForestButtonStyle(prominent: true))
                }.padding(.horizontal, 20).padding(.bottom, 16)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .font(ForestStyle.font(12)).foregroundStyle(ForestStyle.text)
            .background(ForestStyle.surface.opacity(!model.expanded && model.floatingLayout == .avatar ? 0 : opacity), in: RoundedRectangle(cornerRadius: 19))
            .overlay(RoundedRectangle(cornerRadius: 19).stroke(!model.expanded && model.floatingLayout == .avatar ? Color.clear : ForestStyle.line, lineWidth: 1))
            .padding(1).environment(\.colorScheme, .dark)
            .contextMenu {
                Button(model.overlayPreferences.style == .avatar ? "Show metric strip" : "Pebble only") { model.setFloatingStyle(model.overlayPreferences.style == .avatar ? .strip : .avatar) }
                Button("Return to notch") { model.returnToNotch?() }
                Button("Center on this screen") { model.centerOverlay?() }
                Toggle("Lock dragging", isOn: $model.overlayPreferences.positionLocked)
                Button("Settings…") { model.openSettings?() }
            }
            .onChange(of: model.expanded) { _, _ in model.companionReply = nil }
    }
    private var avatarOnly: some View {
        PebbleAvatar(expression: model.companion.expression, responding: model.companionReply != nil, size: 60)
            .overlay {
                OverlayDragHandle(locked: model.overlayPreferences.positionLocked,
                    begin: { model.beginOverlayDrag?() }, move: { model.moveOverlayDrag?($0) }, end: { model.endOverlayDrag?() },
                    showsDots: false, click: { model.expandOverlay?() }, hover: { inside in
                        if inside { model.showCompanionReply() } else { model.companionReply = nil }
                    })
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var verticalStrip: some View {
        VStack(spacing: 8) {
            OverlayDragHandle(locked: model.overlayPreferences.positionLocked, begin: { model.beginOverlayDrag?() }, move: { model.moveOverlayDrag?($0) }, end: { model.endOverlayDrag?() }).frame(width: 30, height: 16)
            Button { model.showCompanionReply() } label: { PebbleAvatar(expression: model.companion.expression, responding: model.companionReply != nil) }
                .buttonStyle(.plain).accessibilityLabel("Pebble’s check-in").accessibilityValue(model.companion.lines[0])
                .onHover { inside in if inside { model.showCompanionReply() } else { model.companionReply = nil } }
            Button { model.expandOverlay?() } label: {
                VStack(spacing: 10) {
                    compact("CPU", value: model.sample[.cpu]); compact("GPU", value: model.sample[.gpu]); compact("RAM", value: model.sample.memoryPercent)
                    Text(model.companion.status).font(ForestStyle.font(10, .medium)).lineLimit(1).minimumScaleFactor(0.7)
                    Text(model.sample[.cpuTemperature].map { String(format: "%.1f°C", $0) } ?? "Temp —").font(ForestStyle.font(10)).foregroundStyle(ForestStyle.secondary)
                    Image(systemName: model.overlayPreferences.dockedEdge == .right ? "chevron.left" : "chevron.right").font(.system(size: 10, weight: .semibold))
                }.frame(maxWidth: .infinity).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("CPU \(Metric.cpu.format(model.sample[.cpu])), GPU \(Metric.gpu.format(model.sample[.gpu])), RAM \(model.sample.memoryPercent.map { String(format: "%.0f percent", $0) } ?? "unavailable"). Expand details")
        }.padding(.vertical, 9).padding(.horizontal, 6)
    }
    private var strip: some View {
        HStack(spacing: 10) {
            OverlayDragHandle(locked: model.overlayPreferences.positionLocked, begin: { model.beginOverlayDrag?() }, move: { model.moveOverlayDrag?($0) }, end: { model.endOverlayDrag?() })
                .frame(width: 16, height: 44)
            Button { model.showCompanionReply() } label: {
                PebbleAvatar(expression: model.companion.expression, responding: model.companionReply != nil)
            }.buttonStyle(.plain)
                .accessibilityLabel("Pebble’s check-in")
                .accessibilityValue(model.companionReply ?? model.companion.lines[0])
                .accessibilityHint("Show a response about the current readings.")
                .onHover { inside in if inside { model.showCompanionReply() } else { model.companionReply = nil } }
            Button { model.expandOverlay?() } label: {
                HStack(spacing: 10) {
                    HStack(spacing: 14) {
                        compact("CPU", value: model.sample[.cpu])
                        compact("GPU", value: model.sample[.gpu])
                        compact("RAM", value: model.sample.memoryPercent)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Rectangle().fill(ForestStyle.line).frame(width: 1, height: 29)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Circle().fill(model.companion.expression == .attention ? ForestStyle.warning : ForestStyle.accent).frame(width: 5, height: 5)
                            Text(model.companion.status).font(ForestStyle.font(11, .medium)).lineLimit(1).minimumScaleFactor(0.75)
                        }
                        Text(model.sample[.cpuTemperature].map { String(format: "%.1f°C CPU", $0) } ?? "CPU temp —")
                            .font(ForestStyle.font(10)).foregroundStyle(ForestStyle.secondary).lineLimit(1)
                    }.frame(width: 94, alignment: .leading)
                    Image(systemName: model.expanded ? "chevron.up" : "chevron.down").font(.system(size: 11, weight: .semibold)).frame(width: 20, height: 38)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel("CPU \(Metric.cpu.format(model.sample[.cpu])), GPU \(Metric.gpu.format(model.sample[.gpu])), RAM \(model.sample.memoryPercent.map { String(format: "%.0f percent", $0) } ?? "unavailable"). \(model.companion.status). \(model.expanded ? "Collapse" : "Expand") details")
        }.padding(.horizontal, 12).frame(height: 66)
    }
    private func compact(_ title: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(ForestStyle.font(10, .medium)).foregroundStyle(ForestStyle.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value.map { String(format: "%.0f", $0) } ?? "—").font(ForestStyle.font(18, .semibold)).monospacedDigit()
                if value != nil { Text("%").font(ForestStyle.font(10)).foregroundStyle(ForestStyle.secondary) }
            }
        }.frame(minWidth: 38, alignment: .leading)
    }
    private var overview: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(model.companion.category).font(ForestStyle.font(10, .medium)).tracking(1.3).foregroundStyle(ForestStyle.secondary)
                Text(model.companion.heading).font(ForestStyle.font(21, .medium)).lineLimit(1).minimumScaleFactor(0.8)
                Text(model.companion.detail).font(ForestStyle.font(11)).foregroundStyle(ForestStyle.secondary).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                GridRow { fact("Thermal state", model.sample.thermal.name); fact("Memory pressure", model.sample.pressure.name) }
                GridRow { fact("CPU temperature", Metric.cpuTemperature.format(model.sample[.cpuTemperature])); fact("GPU temperature", Metric.gpuTemperature.format(model.sample[.gpuTemperature])) }
            }
            OverlayActivityChart(snapshots: model.recent)
            Text(model.historyIssue ?? model.companion.action).font(ForestStyle.font(11))
                .foregroundStyle(model.historyIssue != nil ? ForestStyle.warning : ForestStyle.secondary).lineLimit(3)
        }
    }
    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(ForestStyle.font(10)).foregroundStyle(ForestStyle.secondary)
            Text(value).font(ForestStyle.font(12, .medium)).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
    private var processes: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Largest observable processes").font(ForestStyle.font(12, .medium))
                Spacer()
                HStack(spacing: 2) {
                    sortButton("CPU", memory: false)
                    sortButton("Memory", memory: true)
                }.padding(2).overlay(RoundedRectangle(cornerRadius: 8).stroke(ForestStyle.line, lineWidth: 1))
                    .accessibilityElement(children: .contain).accessibilityLabel("Sort processes")
            }.frame(height: 30)
            let top = Array(model.processes.sorted { sortMemory ? $0.memoryBytes > $1.memoryBytes : ($0.cpuPercent ?? -1) > ($1.cpuPercent ?? -1) }.prefix(4))
            if top.isEmpty {
                Text("Process information is unavailable or still loading.").foregroundStyle(ForestStyle.secondary).padding(.vertical, 24)
            } else {
                ForEach(top) { process in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) { Text(process.name).lineLimit(1); Text("PID \(process.pid)").font(ForestStyle.font(10)).foregroundStyle(ForestStyle.secondary) }
                        Spacer()
                        Text(sortMemory ? String(format: "%.0f MiB", Double(process.memoryBytes) / 1_048_576) : Metric.cpu.format(process.cpuPercent)).monospacedDigit()
                    }.frame(height: 34).padding(.vertical, 2).accessibilityElement(children: .combine)
                    Divider().frame(height: 1).overlay(ForestStyle.line)
                }
            }
            Text("100% CPU means one fully used core. Updated every 5 seconds. High resource use can be intentional.").font(ForestStyle.font(11)).foregroundStyle(ForestStyle.secondary).fixedSize(horizontal: false, vertical: true)
        }.fixedSize(horizontal: false, vertical: true)
    }
    private func sortButton(_ title: String, memory: Bool) -> some View {
        Button { sortMemory = memory } label: {
            Text(title).font(ForestStyle.font(11, .medium)).foregroundStyle(sortMemory == memory ? ForestStyle.text : ForestStyle.secondary)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(sortMemory == memory ? ForestStyle.line : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain).accessibilityLabel("Sort processes by " + title)
            .accessibilityAddTraits(sortMemory == memory ? .isSelected : [])
    }
    private var footer: some View {
        HStack(spacing: 10) {
            Label(Metric.battery.format(model.sample[.battery]), systemImage: "battery.75percent")
                .help(model.sample.batteryInfo.powerSource).font(ForestStyle.font(11)).foregroundStyle(ForestStyle.secondary)
            Spacer(minLength: 0)
            Button { model.setFloatingStyle(.avatar) } label: { Image(systemName: "minus") }
                .buttonStyle(ForestButtonStyle()).accessibilityLabel("Minimize to Pebble only").help("Minimize to Pebble only")
            Button(model.snoozedUntil > Date() ? "Resume alerts" : "Snooze 1h") {
                model.snoozedUntil = model.snoozedUntil > Date() ? .distantPast : Date().addingTimeInterval(3600)
            }.buttonStyle(ForestButtonStyle()).help("Snooze notifications; monitoring and history continue.")
            Button { model.companionReply = nil; model.openSettings?() } label: { Label("Settings", systemImage: "slider.horizontal.3") }.buttonStyle(ForestButtonStyle())
        }
    }
}

struct CompanionReplyView: View {
    let message: String
    var body: some View {
        Text(message).font(ForestStyle.font(12)).foregroundStyle(ForestStyle.text)
            .fixedSize(horizontal: false, vertical: true).padding(14).frame(width: 330, alignment: .leading)
            .background(ForestStyle.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(ForestStyle.line, lineWidth: 1)).padding(1)
            .accessibilityLabel("Pebble. " + message)
    }
}
