# Known issues and remaining validation

This is a source beta, validated on one M4 MacBook Air. A successful build or green CI does not mean every macOS/device combination has passed hands-on acceptance.

- **Original memory transient remains unexplained.** A previous normal-app collapsed 30-minute run measured 49.26 MiB mean / 107.39 MiB sampled peak. The strict 100 MiB peak target did not pass. The later stability baseline was deliberately stopped at 4h 59m 26s; it was not an eight-hour pass. Lifetime peaks include earlier UI activity, and allocation tracing adds substantial overhead. None of these older measurements certifies the newest UI.
- **Spaces animation:** code now avoids redundant app-driven window operations on transitions. Continuous visibility throughout a physical three-finger swipe still needs verification. Presence on desktop Spaces and uninterrupted transition animation are separate checks.
- **Hardware/OS coverage:** only the development M4 Air was physically validated. Other M4 variants and OS versions are unverified. Non-M4 temperatures are intentionally unavailable; Intel is outside the current ARM64 build.
- **Undocumented adapters:** SMC keys and AGX GPU statistics can vary or disappear with OS/model changes. Missing values stay unavailable.
- **Accessibility/platform acceptance:** actual spoken VoiceOver output, Chrome fullscreen, applicable external-display reconnect/Stage Manager configurations and a natural login-startup test remain separate checks. Existing user-confirmed typing while dragging, Safari/Terminal fullscreen and desktop Spaces presence are recorded passes, not blanket coverage of every configuration.
- **Placement:** one saved position/display preference. If there is no built-in notched display and no saved custom position, use the menu bar → Center on this screen. Per-display placement collections are not implemented.
- **Distribution:** no Developer ID signed/notarized download or app updater yet. The bundle still uses its original identifier/version and lacks a final distribution app icon. Build locally for now.
- **Build tooling:** scripts currently select SwiftPM's native build system for compatibility with the development Command Line Tools installation. Newer Swift versions warn that this option is deprecated; a future toolchain may require a build-script update.
- **Scope:** context-aware process recommendations, screen access, automatic optimization/process shutdown, alternate palettes and the full set of prototype customization options are not implemented. The native app and current source are authoritative.

Report a reproducible problem using the [issue template](../.github/ISSUE_TEMPLATE/bug_report.yml). Include chip, macOS, revision and source availability. Do not post raw personal databases or memory captures.
