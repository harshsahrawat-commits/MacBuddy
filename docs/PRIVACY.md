# Privacy and data

The app performs no network requests and includes no account system, analytics, advertising SDK, remote AI service or automatic update checker. Building/cloning and GitHub itself use the network separately from the app.

## What the app reads

System CPU/memory/thermal counters, optional GPU/temperature adapters, battery and startup-volume capacity. For process information it reads names, PIDs, birth identities, CPU counters and memory footprint where permitted. It reads display identifiers/geometry to place the floating panel. It never reads command-line arguments, document/browser contents, screen pixels, general keyboard input or coding conversations.

No Screen Recording or Accessibility permission is requested. The Carbon hotkey registers only the configured shortcut. Silent notifications require an optional macOS permission; login startup is optional. Sensor reads do not change hardware settings or control fans. The app has no process termination feature.

## What stays on disk

- Aggregate metric history and observed lifecycle events: `~/Library/Application Support/MacBuddy/history.sqlite` and SQLite sidecars. Raw process names/PIDs are not persisted.
- Preferences and normalized display placement: UserDefaults domain `app.macbuddy.personal`.
- PDF reports: only where you save them; reports include metric aggregates, dates/coverage and lifecycle observations, not process lists.
- Limited UI-state diagnostics in macOS unified logging (visibility, window state and display mode).

Data is local but not encrypted by the app. Other tools with access to your account, backups or an exported PDF may read it. macOS/FileVault and filesystem permissions provide the surrounding protections. No external servers receive it from Mac Buddy.

The 100 MiB history budget includes SQLite sidecars; old minutes become daily summaries rather than a promise of indefinite raw detail. Errors pause recording. Settings offers explicit Clear history; exported PDFs are unaffected. Back up data while the app is quit, or use a SQLite-aware backup that includes committed WAL data—copying just the main SQLite file while it is open can miss recent records.

## Diagnostics and reports you share

`--diagnose` prints real process names/PIDs. UI-check status files include the current frontmost app identifier. History audits, screenshots, profiling tools and PDFs can reveal usage dates, application identifiers or activity patterns. These tools do not upload anything, but inspect/redact their output before posting it to a public issue. The repository excludes local artifacts and session records from version control.

See the [README](../README.md) for uninstall/data-removal instructions and [SECURITY](../SECURITY.md) for private vulnerability reports.
