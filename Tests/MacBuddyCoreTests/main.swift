import Foundation

// A dependency-free executable test runner for Command Line Tools installations without XCTest.
var failures = 0
var checks = 0
func fail(_ text: String, file: StaticString, line: UInt) { failures += 1; print("FAIL \(file):\(line): \(text)") }
func expectTrue(_ condition: Bool, file: StaticString = #file, line: UInt = #line) { if !condition { fail("expected true", file: file, line: line) } }
func expectEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #file, line: UInt = #line) { let a = actual; if a != expected { fail("\(a) != \(expected)", file: file, line: line) } }
func expectEqual(_ actual: Double, _ expected: Double, accuracy: Double, file: StaticString = #file, line: UInt = #line) { if abs(actual - expected) > accuracy { fail("\(actual) != \(expected)", file: file, line: line) } }
func expectNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) { if value != nil { fail("expected nil", file: file, line: line) } }
func expectNotNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) { if value == nil { fail("unexpected nil", file: file, line: line) } }
func expectGreaterThan(_ value: Int, _ minimum: Int, file: StaticString = #file, line: UInt = #line) { if value <= minimum { fail("\(value) <= \(minimum)", file: file, line: line) } }
func expectThrows<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #file, line: UInt = #line) { do { _ = try expression(); fail("expected an error", file: file, line: line) } catch {} }
func requireValue<T>(_ value: T?) throws -> T { guard let value else { throw NSError(domain: "Checks", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unexpected nil"]) }; return value }
class CheckSuite { func setUpWithError() throws {}; func tearDownWithError() throws {} }
func run(_ name: String, suite: CheckSuite, _ body: () throws -> Void) {
    checks += 1; let before = failures
    do { try suite.setUpWithError(); try body() } catch { failures += 1; print("FAIL \(name): \(error)") }
    do { try suite.tearDownWithError() } catch { failures += 1; print("FAIL cleanup: \(error)") }
    if failures == before { print("PASS \(name)") }
}
if let index = CommandLine.arguments.firstIndex(of: "--crash-fixture"), CommandLine.arguments.count > index + 1 {
    do { try writeCrashFixture(CommandLine.arguments[index + 1]) } catch { fputs("FAIL crash fixture: \(error)\n", stderr); exit(1) }
}
if CommandLine.arguments.contains("--archive-soak") {
    do { try runArchiveSoak(); exit(0) } catch { fputs("FAIL archive soak: \(error)\n", stderr); exit(1) }
}
let advice = AdviceTests()
run("No invented Celsius / RAM / existing-swap warning", suite: advice, advice.testHighCelsiusRAMAndExistingSwapDoNotInventWarning)
run("Thermal durations and immediate critical", suite: advice, advice.testThermalDurationsAndImmediateCritical)
run("Spikes and sleep reset", suite: advice, advice.testTransientLoadAndSleepResetDuration)
run("Unknown pressure is not recovery", suite: advice, advice.testMemoryPressureImmediateAndUnknownIsNotRecovery)
run("Sustained compression growth", suite: advice, advice.testCompressionNeedsSustainedGrowth)
run("Capacity is distinct from thermal", suite: advice, advice.testCapacityIsDistinctFromThermal)
run("Storage durations and escalation", suite: advice, advice.testStorageThresholdsAndDurations)
run("Cooldown, snooze and escalation", suite: advice, advice.testCooldownSnoozeAndEscalation)
run("Missing sensors", suite: advice, advice.testMissingSensorCannotTriggerCapacity)
run("Stale disk readings", suite: advice, advice.testStaleDiskCannotTriggerStorage)
run("Clock rollback", suite: advice, advice.testClockRollbackResetsContinuity)
run("Normal pressure can recover with high stable RAM", suite: advice, advice.testMemoryRecoveryDoesNotRequireLowRAM)
let adviceRecovery = AdviceRecoveryTests()
run("CPU incident recovers without optional GPU", suite: adviceRecovery, adviceRecovery.testCPURecoversWithoutGPU)
run("GPU incident recovers without optional CPU", suite: adviceRecovery, adviceRecovery.testGPURecoversWithoutCPU)
run("Missing incident source is not recovery", suite: adviceRecovery, adviceRecovery.testMissingTriggerIsNotRecovery)
run("Capacity recovery tracks all incident sources", suite: adviceRecovery, adviceRecovery.testBothTriggersMustRecover)
run("Another high resource interrupts recovery", suite: adviceRecovery, adviceRecovery.testOtherHighResourceInterruptsRecovery)
run("Capacity cause survives sleep; recovery restarts", suite: adviceRecovery, adviceRecovery.testSleepPreservesCauseAndResetsRecovery)
run("Combined CPU and GPU evidence", suite: adviceRecovery, adviceRecovery.testSimultaneousTriggerEvidence)
let charts = ChartDataTests()
run("Live chart bound and endpoints", suite: charts, charts.testLiveBoundAndEndpoints)
run("Live chart retains source gaps after sampling", suite: charts, charts.testMissingDataSurvivesDownsampling)
run("Live chart isolated observations and long gaps", suite: charts, charts.testLongGapsAndSingleObservations)
run("Live chart clock corrections and unique identities", suite: charts, charts.testClockCorrectionsDoNotJoinOrDuplicateIDs)
run("History chart continuity and missing hours", suite: charts, charts.testFullHoursConnectAndMissingHoursBreak)
run("History chart isolates partial hours", suite: charts, charts.testPartialHoursStayIsolated)
run("History chart source-specific coverage", suite: charts, charts.testCoverageIsSpecificToEachSource)
run("History chart weighted means and availability", suite: charts, charts.testWeightedHistoryAndUnavailableValues)
run("History chart respects daily resolution", suite: charts, charts.testDailyArchiveDoesNotBecomeAnHour)
let processes = ProcessTests()
run("Process exit and PID reuse", suite: processes, processes.testExitPIDReuseAndRateReset)
run("Invalid reading availability", suite: processes, processes.testInvalidReadingRemainsUnavailable)
let history = HistoryTests()
run("Minute boundaries, gaps, coverage", suite: history, history.testMinuteBoundaryCoverageAndGap)
run("Restart and idempotent daily archive", suite: history, history.testRestartAndDailyArchiveAreIdempotent)
run("Restart merges current minute", suite: history, history.testExistingMinuteMergesAfterRestart)
run("Storage budget preserves existing history", suite: history, history.testBudgetPausesWithoutDeletingHistoryAndClearRecovers)
run("Sleep/wake continuity", suite: history, history.testSleepEventsAndContinuity)
run("Database failures surface", suite: history, history.testReadOnlyFailureIsReported)
run("PDF empty history and pagination", suite: history, history.testPDFEmptyAndPagination)
let reliability = ReliabilityTests()
run("Notification denial and stale callbacks", suite: reliability, reliability.testPermissionDenialAndStaleCallbacks)
run("Report days across DST and today", suite: reliability, reliability.testCalendarDaysAcrossDSTAndToday)
run("History rollback across restart", suite: reliability, reliability.testHistoryClockRollbackAndRestart)
run("Last sample peak preserved on flush", suite: reliability, reliability.testLastSamplePeakSurvivesOrderlyFlush)
run("Recovery does not include sleep time", suite: reliability, reliability.testPressureAndThermalRecoveryAfterSleep)
let recovery = RecoveryTests()
run("Unexpected exit preserves committed WAL", suite: recovery, recovery.testUnexpectedProcessExitRecoversCommittedWAL)
run("Malformed history preserved", suite: recovery, recovery.testMalformedDatabaseIsPreserved)
run("Newer schema preserved", suite: recovery, recovery.testNewerSchemaIsRejectedWithoutDowngrade)
let overlay = OverlayTests()
run("Floating position round trips across displays", suite: overlay, overlay.testPositionRoundTripsAndNegativeScreenOrigins)
run("Expansion keeps saved placement recoverable", suite: overlay, overlay.testExpansionAtBottomDoesNotChangeSavedPosition)
run("Screen resize and offscreen recovery", suite: overlay, overlay.testScreenResizeAndOffscreenRecovery)
run("Placement avoids notch and Dock", suite: overlay, overlay.testSafeAreaAvoidsNotchAndDock)
run("Appearance and position preferences persist safely", suite: overlay, overlay.testPreferencesPersistAndClampInvalidValues)
let companion = CompanionTests()
run("Pebble distinguishes bursts, unknown data and thermal state", suite: companion, companion.testTransientAndMissingReadings)
run("Pebble follows real incident and two-minute recovery", suite: companion, companion.testRealIncidentRecoveryLifecycle)
run("Pebble does not celebrate missing sources, sleep or restart", suite: companion, companion.testMissingCausalSourceAndSleepNeverCelebrate)
run("Pebble optional source recovery and attention priority", suite: companion, companion.testOptionalGPUAndPriority)
run("RAM chart preserves availability, gaps and point bounds", suite: companion, companion.testRAMChartAvailabilityAndBounds)
let floating = FloatingLayoutTests()
run("Floating options migrate without resetting legacy preferences", suite: floating, floating.testLegacyPreferencesAndNewOptions)
run("Side-edge docking handles negative displays and overshoot", suite: floating, floating.testEdgeDetectionAndOvershoot)
run("Avatar and vertical anchors survive expansion and collapse", suite: floating, floating.testAllAnchorsRoundTripAndExpand)
print("\(checks) checks; \(failures) failures")
exit(failures == 0 ? 0 : 1)
