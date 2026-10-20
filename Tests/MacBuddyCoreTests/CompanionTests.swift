import Foundation
import MacBuddyCore

final class CompanionTests: CheckSuite {
    private func sample(_ time: Int, cpu: Double? = 12, gpu: Double? = 6, pressure: Pressure = .normal, thermal: Thermal = .nominal) -> Snapshot {
        let date = Date(timeIntervalSince1970: Double(time))
        var s = Snapshot(at: date, thermal: thermal, pressure: pressure)
        for (metric, value) in [(Metric.cpu,cpu),(.gpu,gpu),(.memoryUsed,10 * 1_073_741_824.0),(.memoryTotal,16 * 1_073_741_824.0),(.compressed,0),(.swapRate,0)] {
            s.readings[metric] = Reading(value,at:date,source:"Companion fixture",unit:metric.unit)
        }
        return s
    }
    func testTransientAndMissingReadings() {
        var tracker = CompanionTracker()
        expectEqual(tracker.update(Snapshot(),advice:[]).expression,.checking)
        let high = tracker.update(sample(100,cpu:95),advice:[])
        expectEqual(high.expression,.focused)
        expectTrue(high.detail.contains("brief burst"))
        expectTrue(!high.lines.joined().contains("two minutes"))
        expectEqual(tracker.update(sample(102,cpu:nil,gpu:nil),advice:[]).status,"Partial data")
        expectEqual(tracker.update(sample(104),advice:[]).expression,.normal)
        expectEqual(tracker.update(sample(106,thermal:.critical),advice:[]).expression,.attention)
    }
    func testRealIncidentRecoveryLifecycle() {
        var engine = AdviceEngine(); var tracker = CompanionTracker()
        var last = CompanionPresentation.checking
        for time in stride(from:0,through:120,by:2) {
            let s=sample(time,cpu:95); last=tracker.update(s,advice:engine.update(s).active)
        }
        expectEqual(last.category,"CAPACITY")
        for time in stride(from:122,through:240,by:2) {
            let s=sample(time); last=tracker.update(s,advice:engine.update(s).active)
            expectEqual(last.expression,.recovering)
        }
        let settled=sample(242)
        expectEqual(tracker.update(settled,advice:engine.update(settled).active).expression,.relieved)
        for time in stride(from:244,through:274,by:2) {
            let s=sample(time);last=tracker.update(s,advice:engine.update(s).active)
        }
        expectEqual(last.expression,.normal)
    }
    func testMissingCausalSourceAndSleepNeverCelebrate() {
        var engine=AdviceEngine();var tracker=CompanionTracker()
        for time in stride(from:0,through:120,by:2) {let s=sample(time,cpu:95);_=tracker.update(s,advice:engine.update(s).active)}
        for time in stride(from:122,through:260,by:2) {
            let s=sample(time,cpu:nil);expectTrue(tracker.update(s,advice:engine.update(s).active).expression != .relieved)
        }
        let first=sample(262);expectEqual(tracker.update(first,advice:engine.update(first).active).expression,.recovering)
        let afterSleep=sample(500);expectTrue(tracker.update(afterSleep,advice:engine.update(afterSleep).active).expression != .relieved)
        var restarted=CompanionTracker()
        expectTrue(restarted.update(sample(502),advice:[]).expression != .relieved)
    }
    func testOptionalGPUAndPriority() {
        var engine=AdviceEngine();var tracker=CompanionTracker()
        var last=CompanionPresentation.checking
        for time in stride(from:0,through:242,by:2) {
            let s=sample(time,cpu:time<=120 ? 95:12,gpu:nil)
            last=tracker.update(s,advice:engine.update(s).active)
        }
        expectEqual(last.expression,.relieved)
        expectTrue(last.detail.contains("unavailable"))
        let memory=sample(244,pressure:.warning)
        expectEqual(tracker.update(memory,advice:engine.update(memory).active).expression,.attention)
        expectEqual(tracker.update(sample(246,pressure:.warning),advice:engine.update(sample(246,pressure:.warning)).active).category,"MEMORY")
    }
    func testRAMChartAvailabilityAndBounds() {
        var samples=(0..<100).map { sample($0) }
        samples[50].readings[.memoryTotal]=nil
        let points=UtilizationChartData.live(samples,limitPerMetric:20,metrics:[.memoryUsed])
        expectEqual(points.count,20)
        expectEqual(points.first!.value,62.5,accuracy:0.001)
        expectEqual(points.last!.date,samples.last!.timestamp)
        expectGreaterThan(Set(points.map(\.segment)).count,1)
        expectTrue(points.allSatisfy{$0.value<=100})
    }
}
