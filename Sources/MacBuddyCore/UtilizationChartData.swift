import Foundation

public struct UtilizationPoint: Identifiable, Sendable {
    public var date: Date
    public var value: Double
    public var metric: Metric
    public var segment: Int
    public var observedSeconds: Double?
    public var intervalSeconds: Double?
    public var isolated = false
    public var id: String { "\(metric.rawValue)-\(date.timeIntervalSince1970)-\(segment)" }
    public var series: String { "\(metric.rawValue)-\(segment)" }
}

/// Chart preparation is independent of SwiftUI, persistence and preferences.
/// Sampling never joins different observed segments or alters archived peaks.
public enum UtilizationChartData {
    public static func live(_ snapshots: [Snapshot], limitPerMetric: Int = 600, metrics: [Metric] = [.cpu, .gpu]) -> [UtilizationPoint] {
        guard limitPerMetric > 0, let end = snapshots.last?.timestamp else { return [] }
        let start = end.addingTimeInterval(-3600)
        var result: [UtilizationPoint] = []
        for metric in metrics {
            var points: [UtilizationPoint] = []
            var previous: Date?
            var segment = 0
            for snapshot in snapshots {
                guard snapshot.timestamp >= start, snapshot.timestamp <= end,
                      let value = (metric == .memoryUsed ? snapshot.memoryPercent : snapshot[metric]), value.isFinite else {
                    previous = nil
                    segment += 1
                    continue
                }
                if let previous {
                    let elapsed = snapshot.timestamp.timeIntervalSince(previous)
                    if elapsed <= 0 || elapsed > 15 { segment += 1 }
                }
                points.append(UtilizationPoint(date: snapshot.timestamp, value: value, metric: metric, segment: segment))
                previous = snapshot.timestamp
            }
            if points.count > limitPerMetric {
                if limitPerMetric == 1 {
                    points = [points[points.count - 1]]
                } else {
                    let last = points.count - 1
                    points = (0..<limitPerMetric).map { index in
                        points[Int((Double(index) * Double(last) / Double(limitPerMetric - 1)).rounded())]
                    }
                }
            }
            markIsolated(&points)
            result.append(contentsOf: points)
        }
        return result
    }

    public static func history(_ rows: [Summary]) -> [UtilizationPoint] {
        var grouped: [Date: Summary] = [:]
        for row in rows {
            // Minute records become hourly averages. A daily archive remains a
            // daily observation if one is supplied; it is never labelled an hour.
            let duration = max(3600, row.duration)
            let start = Date(timeIntervalSince1970: floor(row.start.timeIntervalSince1970 / duration) * duration)
            if grouped[start] == nil { grouped[start] = Summary(start: start, duration: duration) }
            grouped[start]!.merge(row)
        }
        let buckets = grouped.values.sorted { $0.start < $1.start }
        var result: [UtilizationPoint] = []
        for metric in [Metric.cpu, .gpu] {
            var points: [UtilizationPoint] = []
            var previousEnd: Date?
            var previousComplete = false
            var segment = 0
            for bucket in buckets {
                guard let statistics = bucket.metrics[metric], let value = statistics.mean, value.isFinite else {
                    previousEnd = nil
                    previousComplete = false
                    segment += 1
                    continue
                }
                // Summaries do not retain the exact location of sub-minute gaps.
                // Isolate every partial bucket instead of inventing continuity.
                let complete = abs(statistics.seconds - bucket.duration) < 0.001
                let adjacent = previousEnd.map { abs(bucket.start.timeIntervalSince($0)) < 0.001 } ?? false
                if !complete || !previousComplete || !adjacent { segment += 1 }
                points.append(UtilizationPoint(date: bucket.start, value: value, metric: metric, segment: segment,
                                               observedSeconds: statistics.seconds, intervalSeconds: bucket.duration))
                previousEnd = bucket.start.addingTimeInterval(bucket.duration)
                previousComplete = complete
            }
            markIsolated(&points)
            result.append(contentsOf: points)
        }
        return result
    }

    private static func markIsolated(_ points: inout [UtilizationPoint]) {
        let counts = points.reduce(into: [Int: Int]()) { $0[$1.segment, default: 0] += 1 }
        for index in points.indices { points[index].isolated = counts[points[index].segment] == 1 }
    }
}
