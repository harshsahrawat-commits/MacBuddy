# Contributing to Mac Buddy

Thank you for helping with this M4-focused source beta. Discuss significant features or UI changes in an issue before implementing them. Small, focused fixes with reproducible evidence are welcome.

## Set up and check

Use an Apple-silicon Mac and Swift 6+ with a macOS 14+ SDK. Follow the [README](README.md) to build. There are no external Swift package dependencies.

```sh
./scripts/build.sh
./scripts/check.sh
./scripts/scheduler-check.sh
"dist/Mac Buddy.app/Contents/MacOS/MacBuddy" --runtime-checks
```

`check.sh` runs the executable `MacBuddyChecks`, native CPU-timebase/gap checks and a brief-memory-peak recorder regression. `scheduler-check.sh` compiles the actual sampling service into an isolated harness and checks five groups. Runtime checks exercise the packaged executable with synthetic samples and a temporary database. `swift test` is not the entry point because the dependency-free runner supports Command Line Tools installations without XCTest.

Installer checks use disposable app bundles, preferences, SQLite/sidecar sentinels and local Git remotes:

```sh
python3 scripts/install-checks.py
python3 scripts/install-checks.py --native
```

The fast checks double compiler/signature/lifecycle commands while exercising real Git and filesystem operations, including replacement rollback and preservation of user-data sentinels. `--native` additionally compiles, installs, opens, normally quits and updates a real AppKit fixture with a unique test bundle identifier on a logged-in desktop. It never targets `app.macbuddy.personal`. CI runs the fast checks and compiles the actual lifecycle helper; the native interactive acceptance is separate.

Use `./scripts/install.sh --no-update` when intentionally testing local uncommitted source; add `--no-open` or a temporary `--destination` as needed. Production defaults pull the configured Git upstream, refuse dirty/diverged checkouts, install for the current user and launch. The installer never edits user preferences/history or login/notification registration. Normal app shutdown can flush the current minute and record its lifecycle event.

CI uses the same checks on an ARM64 macOS 15 runner. Timers are real-time integration checks. They are not a substitute for physical sensors, accessibility, fullscreen, display reconnection or gestures.

## Optional diagnostics

After building, these commands use synthetic data and do not start personal monitoring:

```sh
mkdir -p tmp/renders
"dist/Mac Buddy.app/Contents/MacOS/MacBuddy" --render-overlay tmp/renders/panel.png
"dist/Mac Buddy.app/Contents/MacOS/MacBuddy" --render-overlay tmp/renders/strip.png --collapsed
"dist/Mac Buddy.app/Contents/MacOS/MacBuddy" --render-overlay tmp/renders/dashboard.png --render-scene dashboard
"dist/Mac Buddy.app/Contents/MacOS/MacBuddy" --report-fixture tmp/renders/report.pdf
```

Available render scenes: normal, cpu, memory, recovering, recovered, unavailable, processes, avatar, vertical, dashboard, settings. A render is a layout fixture, not a live UI test.

`--diagnose` reads real system metrics and prints observable process names/PIDs. Review and redact its output before sharing. `python3 scripts/audit-history.py` reads the local archive, including WAL, without changing application records. It can also take an explicit database path.

`python3 scripts/build-overlay-ui-check.py` builds a separate app with temporary history and preferences. Launch its printed path manually. It samples real telemetry and attempts to register the configured global shortcut, so quit the normal app first if testing that shortcut. It also writes the frontmost app identifier to its local status file; review that file before sharing. On orderly quit its test preferences are removed. Temporary artifacts remain for inspection.

For resource investigations only, `./scripts/measure.sh PID 1800 --observed-duration` records one process without keeping the Mac awake. `./scripts/stability.sh PID 28800` also audits the default local archive before/after. Verify the PID belongs to the intended normal app first. These are opt-in long checks; do not run them merely to establish context. Distinguish sampled memory, lifetime high-water marks, unobserved gaps and instrumentation overhead.

## Pull requests

- Describe the concrete problem, resulting behavior and checks actually run.
- Preserve existing preferences and history. Schema/preferences changes need backward compatibility and targeted tests.
- Keep unavailable values explicit. Do not invent hardware mappings, turn unavailable data into zero, or infer causation from a timestamp correlation.
- Use deterministic fixtures for advisories and chart gaps rather than deliberately overloading a contributor's Mac.
- Do not upload personal history, preferences, logs, memgraphs, signing material, API keys or unredacted process/screen data. The root allowlist in `.gitignore` intentionally excludes local session notes and prototypes.
- Keep Manrope's OFL and Stats attribution when redistributing.

For chip compatibility reports include the exact chip/model, macOS version, Swift version, build revision and unavailable readings. A passing generic CPU test does not validate a model's SMC sensors. See the [bug report template](.github/ISSUE_TEMPLATE/bug_report.yml) and [security policy](SECURITY.md).
