import SwiftUI
import MacBuddyCore

/// A bounded 60-second chart with the same source/gap segmentation as the dashboard.
/// Canvas avoids axis layout work in a small floating utility panel.
struct OverlayActivityChart: View {
    var snapshots: [Snapshot]
    private var recent: [Snapshot] {
        guard let end = snapshots.last?.timestamp else { return [] }
        return snapshots.filter { $0.timestamp >= end.addingTimeInterval(-60) }
    }
    var body: some View {
        let points = UtilizationChartData.live(recent, limitPerMetric: 61, metrics: [.cpu, .gpu, .memoryUsed])
        VStack(spacing: 8) {
            HStack {
                Text("Last 60 seconds")
                Spacer()
                key("CPU", ForestStyle.accent); key("GPU", ForestStyle.gpu); key("RAM", ForestStyle.ram)
            }.font(ForestStyle.font(10)).foregroundStyle(ForestStyle.secondary)
            Canvas { context, size in
                for fraction in [0.0, 0.5, 1.0] {
                    var line = Path(); line.move(to: CGPoint(x: 0, y: size.height * fraction)); line.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
                    context.stroke(line, with: .color(ForestStyle.line), lineWidth: 0.5)
                }
                guard let end = snapshots.last?.timestamp else { return }
                for segment in Dictionary(grouping: points, by: \.series).values {
                    guard let first = segment.first else { continue }
                    let color = first.metric == .cpu ? ForestStyle.accent : first.metric == .gpu ? ForestStyle.gpu : ForestStyle.ram
                    var path = Path()
                    for (index, point) in segment.enumerated() {
                        let p = CGPoint(x: max(0, min(1, 1 + point.date.timeIntervalSince(end) / 60)) * size.width,
                                        y: (1 - max(0, min(100, point.value)) / 100) * size.height)
                        if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
                        if point.isolated { context.fill(Path(ellipseIn: CGRect(x:p.x-2,y:p.y-2,width:4,height:4)),with:.color(color)) }
                    }
                    context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            }.frame(height: 76)
                .overlay { if points.isEmpty { Text("Collecting activity…").font(ForestStyle.font(11)).foregroundStyle(ForestStyle.secondary) } }
                .accessibilityLabel("CPU, GPU and RAM utilization, zero to one hundred percent, for the last sixty seconds. Missing readings and observation gaps stay blank.")
        }
    }
    private func key(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 4) { RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 8,height: 2); Text(title) }
    }
}
