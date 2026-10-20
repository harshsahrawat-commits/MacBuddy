# Validation status

This document separates automated checks, isolated native UI evidence, user confirmations and remaining unknowns. Historical raw captures and personal session notes are kept local rather than published.

## Automated baseline — 20 October 2026

Source-publication verification passed 58 functional checks, native CPU-timebase/gap/brief-peak recorder regressions, five scheduler groups, packaged runtime integration and ad-hoc signature verification. These ran from a fresh export of the staged public files, without the original build cache, on ARM64 macOS 27.0.1 with Swift 6.4. GitHub Actions shows the result for each published revision.

Coverage includes advisory trigger/recovery and missing sources; chart point bounds/newest points/gaps; weighted history and retention; database failure/retry, budget and crash recovery; PDF empty/pagination; backward-compatible preferences; shortcuts/control state; avatar responses; side-edge geometry with negative coordinates and overshoot; and preserved anchors between floating shapes.

The scheduler/runtime harnesses use synthetic samples and disposable SQLite. They do not exercise real notification delivery, natural login, OS sleep hardware or a physical swipe. The brief-peak regression validates the recorder using a disposable allocation burst; it does not resolve the app's original transient.

CI builds on ARM64 `macos-15` with Swift 6+, packages the app, verifies its local signature, and runs functional/native/scheduler/runtime checks. It logs the toolchain/OS. CI is generic software coverage on a hosted machine, not M4 sensor validation or a claim that all macOS 14+ releases were tested.

## Installer verification

The single-command installer passes 12 fast checks covering first/repeated installation, spaced paths, source ZIPs, Git fast-forward/self-refresh, dirty/diverged/unreachable upstream protection, one retained previous app, concurrent locks, refusal to overwrite unrelated files/symlinks, build/signature/copy/quit/replacement failures and launch-error reporting. Real Git and filesystem operations are used with compiler/signature/lifecycle command doubles. Fixture preferences, SQLite history and sidecar bytes remain identical in every case.

A thirteenth local check uses actual signing, app copying and the AppKit lifecycle helper with a unique disposable app identity: first launch, normal quit with a shutdown-flush marker, replacement, exact-path relaunch and previous-bundle retention pass. It never targets the user's Mac Buddy identifier or real data. CI runs the fast checks and compiles the real helper. Installation/login/Gatekeeper acceptance on another user's physical Mac remains separate.

The installer itself never edits preferences/history or notification/login registration. The app's normal shutdown can flush the current minute and append a lifecycle event; preserving history does not mean suppressing normal recording.

## Isolated native UI evidence

Actual-view synthetic renders and an isolated running app exercised the Forest/Manrope/Pebble strip/panel, dashboard and Settings, live metrics, process sorting, history/report controls, snooze/resume, avatar minimize/click/drag, left/right docking, drag undocking and edge expansion. Test data/preferences were separate; the user's settings/history were verified preserved. Earlier native checks cover transparency, Reduce Motion, keyboard navigation and placement persistence. These are bounded checks, not long performance certification.

The images in `docs/images` are native offscreen renders with synthetic data; no personal process list or history is included. They use a 3× backing scale and PNG pixel dimensions, with logical display sizes specified in the README to avoid enlargement. `scripts/render-readme.py` validates dimensions and omits EXIF/text metadata. Strip/panel/dashboard exports are visually inspected for text, avatar, controls and complete chart/scroll content. They show layout, not a separate simulated frontend.

## User-confirmed behavior

Typing while dragging, Safari fullscreen, Terminal fullscreen and desktop Spaces presence were explicitly confirmed on the development machine. These confirmations remain valid evidence; do not repeat them merely to establish context.

Continuous three-finger transition visibility was newly reported and the code changed; that focused physical check remains pending. Other outstanding platform checks are in [known issues](KNOWN_ISSUES.md).

## Memory investigation — older normal build

| Evidence | Result and scope |
| --- | --- |
| 30-minute normal collapsed app | 1,800.4 observed seconds; 0.6028% of one CPU core mean, 49.26 MiB mean / 107.39 MiB sampled peak footprint; no observation gaps; history audit passed. |
| Stability baseline | Deliberately stopped at 4h 59m 26s (17,966 observed seconds). No recorded restart/crash or observed gaps over five seconds. Last cumulative CPU 0.6836% of one core; no exact whole-run mean memory was emitted. Not an eight-hour pass. |
| Lifetime footprint | 149.42 MiB high-water mark included UI activity before the recording window. It cannot be attributed to collapsed monitoring. |
| Allocation-logging copy | Five Settings and five dashboard lifecycles did not accumulate closed app hosting views. A leak scan found about 19.5 KiB rooted in Apple XPC/AppIntents cycles without a Mac Buddy frame. One snapshot attributed about 192 MiB to performance-tool data. This is not a zero-leak result or a normal-app benchmark. |

The original 107.39 MiB event was not causally explained or reproduced with a useful stack capture. Stable footprint and released views argue against continuing growth in the paths tested, but do not prove every allocation path is correct. The 100 MiB sampled-peak target remains unmet. The old 0.012% CPU claim was withdrawn and is not a valid measurement. The hourly follow-up is paused; no long stability test is started by CI or publication.
