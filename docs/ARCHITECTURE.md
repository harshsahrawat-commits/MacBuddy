# Architecture and limitations

Mac Buddy is one native macOS process, with no remote backend or privileged helper. SwiftUI provides the views, AppKit provides nonactivating floating panels and normal dashboard/settings windows, and Swift Charts/Canvas draw activity.

## Data flow

1. `NativeTelemetry` reads counters via Mach, sysctl, IOKit, libproc and isolated SMC/IORegistry adapters.
2. `MacBuddyCore/Telemetry.swift` produces typed, timestamped readings with a source and explicit unavailable state. Process deltas track PID plus birth identity to avoid reusing counters across different processes.
3. `SamplingService` serializes collection, advisory evaluation and history writes on its own queue. Adaptive sampling is two seconds collapsed/one second with details; Steady is two seconds and Eco five seconds. Process refresh is independently five seconds, storage one minute. Sleep suspends timers; wake resets rate/continuity baselines.
4. `AdviceEngine` evaluates sustained conditions with recovery/cooldown state. `CompanionTracker` maps that real state to Pebble responses, distinguishing brief load, active pressure, recovery in progress, confirmed recovery and unavailable readings.
5. Main-thread `MonitorModel` publishes readings to the strip/panel, dashboard and Settings and delivers permitted notifications. History queries return asynchronously. Closing detail windows releases their content.

## Native integrations

- Carbon registers a particular global shortcut; no general keyboard monitor or Accessibility permission is used.
- `NSPanel` uses stationary/all-Spaces/fullscreen-auxiliary behavior without taking typing focus. Explicitly opening dashboard/Settings activates their normal windows.
- `UNUserNotificationCenter` handles opt-in silent notifications, permission changes and snooze. Cooldown is 15 minutes per category; worsening severity can notify sooner.
- `SMAppService.mainApp` handles opt-in login startup at a stable bundle path.
- CoreText registers bundled Manrope for this process only. CoreGraphics/CoreText generate PDFs locally.

## Storage

`HistoryStore` uses SQLite via the system library. One hour of raw metric snapshots is bounded in memory; minute summaries persist for 30 days, then complete UTC days become daily aggregates. Weighted statistics preserve coverage, sampled peaks/minima and pressure/thermal durations, not every raw sample. Lifecycle events record observed start/stop/sleep/wake for 30 days.

Minute boundaries, sleep, export and orderly quit flush pending history. A crash can lose the unfinished minute, while transactions protect completed summaries. The 100 MiB archive budget includes WAL/shared-memory/journal files. Maintenance tries aggregation, checkpointing and vacuuming; failure pauses recording and surfaces an issue instead of deleting existing records.

Live chart preparation caps each metric at 600 points, retains the newest observation and separates sleep/source/clock discontinuities. Partial history hours are isolated points because their minute summaries cannot recover each internal gap. Daily PDF boundaries use UTC, including the selected final day; today stops at export time.

Preferences use UserDefaults domain `app.macbuddy.personal`; normalized position plus display UUID, opacity, lock and floating shape decode backward compatibly. One position is saved, not a collection per monitor. Process names/PIDs never enter history or reports.

## Interpretation and hardware boundaries

SMC temperatures and AGX GPU utilization are undocumented, read-only interfaces. Temperature collection explicitly requires a sysctl brand string containing `Apple M4`; keys are probed for type/presence and values outside a broad plausible range are rejected. That plausibility check is not a safety threshold. Other M4 variants may expose different sensors. Outside M4, temperatures deliberately remain unavailable. GPU utilization relies on AGX performance statistics and may be absent. Generic CPU/memory support does not prove full hardware support.

Memory accounting is a Mach VM estimate, not an exact clone of Activity Monitor. Per-process CPU can exceed 100% because it counts cores. Process enumeration is bounded at 4,096 observable entries and limited by macOS permissions. Battery health/capacity appears only if the OS exposes the relevant property. Available disk capacity can include reclaimable space.

Thermal classification comes from macOS rather than Celsius bands. Capacity warnings require CPU or GPU above 90% for two minutes. Memory-pressure signals can warn immediately; the high-utilization heuristic also requires sustained compression growth or swap-out activity. Storage warnings combine absolute and percentage thresholds with duration. Recovery requires two minutes; missing a triggering source cannot prove recovery. These are app heuristics, not Apple-certified safety guarantees; see `Advice.swift` for the authoritative policy.

The OS controls Spaces transitions and fullscreen composition. Redundant reframe/reorder operations were removed, but continuous visibility during a physical swipe is still unverified. The app does not promise to stay above every system surface.
