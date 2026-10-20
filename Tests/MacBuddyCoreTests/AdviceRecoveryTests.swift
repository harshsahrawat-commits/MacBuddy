import Foundation
import MacBuddyCore

final class AdviceRecoveryTests: CheckSuite {
    private let fixture = AdviceTests()

    @discardableResult private func feed(_ engine: inout AdviceEngine, from: Int, through: Int,
                                        cpu: Double?, gpu: Double?) -> AdviceUpdate {
        var result = engine.update(fixture.sample(Double(from), cpu: cpu, gpu: gpu))
        for time in stride(from: from + 2, through: through, by: 2) {
            result = engine.update(fixture.sample(Double(time), cpu: cpu, gpu: gpu))
        }
        return result
    }

    func testCPURecoversWithoutGPU() {
        var engine = AdviceEngine()
        expectEqual(feed(&engine, from: 0, through: 120, cpu: 95, gpu: nil).active.first?.category, .capacity)
        let recovering = feed(&engine, from: 122, through: 240, cpu: 20, gpu: nil)
        expectEqual(recovering.active.first?.recovering, true)
        expectTrue(feed(&engine, from: 242, through: 242, cpu: 20, gpu: nil).active.isEmpty)
    }

    func testGPURecoversWithoutCPU() {
        var engine = AdviceEngine()
        expectEqual(feed(&engine, from: 0, through: 120, cpu: nil, gpu: 95).active.first?.category, .capacity)
        expectTrue(feed(&engine, from: 122, through: 242, cpu: nil, gpu: 10).active.isEmpty)
    }

    func testMissingTriggerIsNotRecovery() {
        var engine = AdviceEngine()
        _ = feed(&engine, from: 0, through: 120, cpu: 95, gpu: 10)
        let missing = feed(&engine, from: 122, through: 400, cpu: nil, gpu: 10)
        expectEqual(missing.active.first?.category, .capacity)
        expectEqual(missing.active.first?.recovering, false)
        expectTrue(feed(&engine, from: 402, through: 522, cpu: 20, gpu: nil).active.isEmpty)
    }

    func testBothTriggersMustRecover() {
        var engine = AdviceEngine()
        let first = feed(&engine, from: 0, through: 120, cpu: 95, gpu: 10)
        let second = feed(&engine, from: 122, through: 242, cpu: 20, gpu: 95)
        expectEqual(second.active.first?.since, first.active.first?.since)
        expectTrue(second.notifications.isEmpty)
        expectEqual(feed(&engine, from: 244, through: 400, cpu: nil, gpu: 10).active.count, 1)
        expectTrue(feed(&engine, from: 402, through: 522, cpu: 20, gpu: 10).active.isEmpty)

        // A later CPU-only incident must not inherit the previous GPU cause.
        _ = feed(&engine, from: 524, through: 644, cpu: 95, gpu: nil)
        expectTrue(feed(&engine, from: 646, through: 766, cpu: 20, gpu: nil).active.isEmpty)
    }

    func testOtherHighResourceInterruptsRecovery() {
        var engine = AdviceEngine()
        _ = feed(&engine, from: 0, through: 120, cpu: 95, gpu: nil)
        _ = feed(&engine, from: 122, through: 180, cpu: 20, gpu: nil)
        expectEqual(feed(&engine, from: 182, through: 200, cpu: 20, gpu: 95).active.first?.recovering, false)
        expectEqual(feed(&engine, from: 202, through: 320, cpu: 20, gpu: nil).active.count, 1)
        expectTrue(feed(&engine, from: 322, through: 322, cpu: 20, gpu: nil).active.isEmpty)
    }

    func testSleepPreservesCauseAndResetsRecovery() {
        var engine = AdviceEngine()
        _ = feed(&engine, from: 0, through: 120, cpu: 95, gpu: nil)
        _ = feed(&engine, from: 122, through: 180, cpu: 20, gpu: nil)
        engine.resetContinuity()
        expectEqual(feed(&engine, from: 10000, through: 10118, cpu: 20, gpu: nil).active.count, 1)
        expectTrue(feed(&engine, from: 10120, through: 10120, cpu: 20, gpu: nil).active.isEmpty)
    }

    func testSimultaneousTriggerEvidence() {
        var engine = AdviceEngine()
        let result = feed(&engine, from: 0, through: 120, cpu: 95, gpu: 95)
        expectTrue(result.active.first?.evidence.contains("CPU and GPU") == true)
    }
}
