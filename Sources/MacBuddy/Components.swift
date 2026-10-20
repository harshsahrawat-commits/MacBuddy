import SwiftUI
import MacBuddyCore

// Select the stable property-wrapper type; CLT-only SDK 27 does not ship the new State macro plugin.
typealias ViewState<Value> = SwiftUI.State<Value>

extension Thermal {
    var color: Color {
        switch self { case .nominal: return .mint; case .fair: return .yellow; case .serious: return .orange; case .critical: return .red; case .unknown: return .gray }
    }
}
struct MetricTile: View {
    var metric: Metric
    var sample: Snapshot
    var subtitle: String
    var title: String? = nil
    var usesMemoryPercent = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text((title ?? metric.title).uppercased()).font(ForestStyle.font(10, .semibold)).foregroundStyle(ForestStyle.secondary)
            Text(usesMemoryPercent ? sample.memoryPercent.map { String(format: "%.0f%%", $0) } ?? "Unavailable" : metric.format(sample[metric])).font(ForestStyle.font(30, .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(subtitle).font(ForestStyle.font(11)).foregroundStyle(ForestStyle.secondary).lineLimit(2)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(ForestStyle.raised, in: RoundedRectangle(cornerRadius: 14))
            .help(sample.readings[metric].map { "\($0.source)\nUpdated \($0.timestamp.formatted(date: .omitted, time: .standard))\($0.unavailableReason.map { "\n" + $0 } ?? "")" } ?? "Waiting for first sample")
    }
}
struct AdviceList: View {
    @ObservedObject var model: MonitorModel
    var body: some View {
        if model.advice.isEmpty {
            Label("No sustained bottlenecks detected", systemImage: "checkmark.circle")
                .foregroundStyle(ForestStyle.secondary).font(ForestStyle.font(13))
            Text("Mac Buddy watches thermal conditions, memory pressure, workload capacity, and free storage.")
                .font(ForestStyle.font(11)).foregroundStyle(ForestStyle.secondary)
        } else {
            ForEach(model.advice) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Label(item.title + (item.recovering ? " · recovering" : ""), systemImage: item.severity > 1 ? "exclamationmark.triangle" : "info.circle").font(ForestStyle.font(14, .semibold))
                    Text(item.evidence).font(ForestStyle.font(13))
                    Text(item.action).font(ForestStyle.font(13)).foregroundStyle(ForestStyle.secondary)
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(ForestStyle.warning.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}
/// Explicit colors remain readable when the non-activating panel is not key.
/// AppKit's inactive bordered-prominent treatment can otherwise remove the tint.
struct OverlayActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color(red: 0.02, green: 0.07, blue: 0.06))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color(red: 0.35, green: 0.90, blue: 0.73).opacity(configuration.isPressed ? 0.85 : 1), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
    }
}
