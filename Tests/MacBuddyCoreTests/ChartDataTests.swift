import Foundation
import MacBuddyCore

final class ChartDataTests: CheckSuite {
    private let epoch = Date(timeIntervalSince1970: 1_780_012_800)

    private func sample(_ time: Double, cpu: Double? = 20, gpu: Double? = 10) -> Snapshot {
        let date = epoch.addingTimeInterval(time)
        return Snapshot(at: date, readings: [
            .cpu: Reading(cpu, at: date, source: "Chart fixture", unit: "%"),
            .gpu: Reading(gpu, at: date, source: "Chart fixture", unit: "%")
        ])
    }

    private func row(_ time: Double, duration: Double = 60, observed: Double = 60,
                     cpu: Double? = 20, gpu: Double? = 10) -> Summary {
        var row = Summary(start: epoch.addingTimeInterval(time), duration: duration)
        row.add(sample(time, cpu: cpu, gpu: gpu), seconds: observed)
        return row
    }

    func testLiveBoundAndEndpoints() {
        for count in [0, 1, 2, 599, 600, 601, 1199, 1801, 3601] {
            let samples = (0..<count).map { sample(Double($0), cpu: Double($0 % 100)) }
            let points = UtilizationChartData.live(samples)
            for metric in [Metric.cpu, .gpu] {
                let resource = points.filter { $0.metric == metric }
                expectEqual(resource.count, min(count, 600))
                expectEqual(resource.first?.date, samples.first?.timestamp)
                expectEqual(resource.last?.date, samples.last?.timestamp)
                expectEqual(Set(resource.map(\.id)).count, resource.count)
            }
        }
        let samples = [sample(0), sample(2)]
        expectTrue(UtilizationChartData.live(samples, limitPerMetric: 0).isEmpty)
        expectEqual(UtilizationChartData.live(samples, limitPerMetric: 1).filter { $0.metric == .cpu }.first?.date,
                    samples.last?.timestamp)
    }

    func testMissingDataSurvivesDownsampling() {
        let samples = (0..<1200).map { sample(Double($0), cpu: $0 == 600 ? nil : 20) }
        let points = UtilizationChartData.live(samples)
        let cpu = points.filter { $0.metric == .cpu }
        let gpu = points.filter { $0.metric == .gpu }
        expectEqual(cpu.count, 600)
        expectEqual(Set(cpu.map(\.segment)).count, 2)
        expectEqual(Set(gpu.map(\.segment)).count, 1)
        for (a, b) in zip(cpu, cpu.dropFirst()) where a.date < epoch.addingTimeInterval(600) && b.date > epoch.addingTimeInterval(600) {
            expectTrue(a.series != b.series)
        }
        expectTrue(UtilizationChartData.live([sample(0, cpu: nil, gpu: nil)]).isEmpty)
    }

    func testLongGapsAndSingleObservations() {
        let points = UtilizationChartData.live([sample(0), sample(100)])
        expectTrue(points.allSatisfy(\.isolated))
        let cpu = points.filter { $0.metric == .cpu }
        expectEqual(cpu.count, 2)
        expectTrue(cpu[0].series != cpu[1].series)
        expectTrue(UtilizationChartData.live([sample(0)]).allSatisfy(\.isolated))
    }

    func testClockCorrectionsDoNotJoinOrDuplicateIDs() {
        let points = UtilizationChartData.live([0.0, 2, 1, 2, 4].map { sample($0) })
        expectEqual(Set(points.map(\.id)).count, points.count)
        let cpu = points.filter { $0.metric == .cpu }
        expectTrue(cpu[1].series != cpu[2].series)
        let corrected = UtilizationChartData.live([100.0, 102, 200, 90, 92].map { sample($0) })
        expectTrue(corrected.allSatisfy { $0.date <= epoch.addingTimeInterval(92) })
        let recent = UtilizationChartData.live([sample(0), sample(4000)])
        expectEqual(recent.filter { $0.metric == .cpu }.count, 1)
    }

    func testFullHoursConnectAndMissingHoursBreak() {
        let rows = [row(0, duration: 3600, observed: 3600),
                    row(3600, duration: 3600, observed: 3600),
                    row(10800, duration: 3600, observed: 3600)]
        let cpu = UtilizationChartData.history(Array(rows.reversed())).filter { $0.metric == .cpu }
        expectEqual(cpu.count, 3)
        expectEqual(cpu[0].series, cpu[1].series)
        expectTrue(cpu[1].series != cpu[2].series)
        expectTrue(cpu[2].isolated)
    }

    func testPartialHoursStayIsolated() {
        let rows = [row(0, cpu: 20), row(3540, cpu: 80),
                    row(3600, duration: 3600, observed: 3600)]
        let cpu = UtilizationChartData.history(rows).filter { $0.metric == .cpu }
        expectEqual(cpu.count, 2)
        expectEqual(cpu[0].value, 50, accuracy: 0.0001)
        expectEqual(cpu[0].observedSeconds, 120)
        expectEqual(cpu[0].intervalSeconds, 3600)
        expectTrue(cpu.allSatisfy(\.isolated))
        expectTrue(cpu[0].series != cpu[1].series)
    }

    func testCoverageIsSpecificToEachSource() {
        let rows = [row(0, duration: 1800, observed: 1800),
                    row(1800, duration: 1800, observed: 1800, gpu: nil),
                    row(3600, duration: 3600, observed: 3600)]
        let points = UtilizationChartData.history(rows)
        let cpu = points.filter { $0.metric == .cpu }
        let gpu = points.filter { $0.metric == .gpu }
        expectEqual(cpu[0].series, cpu[1].series)
        expectEqual(gpu[0].observedSeconds, 1800)
        expectTrue(gpu[0].series != gpu[1].series)
        expectTrue(gpu.allSatisfy(\.isolated))
    }

    func testWeightedHistoryAndUnavailableValues() {
        let rows = [row(0, observed: 30, cpu: 10, gpu: nil), row(60, cpu: 90, gpu: nil)]
        let points = UtilizationChartData.history(rows)
        expectEqual(points.count, 1)
        expectEqual(points[0].value, 5700 / 90.0, accuracy: 0.0001)
        expectEqual(points[0].observedSeconds, 90)
        expectTrue(UtilizationChartData.history([row(0, observed: 0)]).isEmpty)
        expectEqual(rows[1].metrics[.cpu]?.peak, 90)
    }

    func testDailyArchiveDoesNotBecomeAnHour() {
        let points = UtilizationChartData.history([row(0, duration: 86400, observed: 7200)])
        expectEqual(points.first?.intervalSeconds, 86400)
        expectEqual(points.first?.observedSeconds, 7200)
        expectTrue(points.allSatisfy(\.isolated))
    }
}
