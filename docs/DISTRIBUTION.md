# Distribution roadmap

## Available now: public source

Clone or download this repository and build on your own Mac. The build script creates an ARM64, ad-hoc signed application with bundled licenses. It requires no paid Apple Developer membership. MIT applies to the project; third-party notices and Manrope's OFL still apply.

The initial beta is M4-focused with physical validation on one M4 Air. Other chips/OS combinations need explicit validation. Green CI verifies builds and isolated behavior, not physical sensors or an end-user installation.

## Before a ready-to-run GitHub download

1. Establish version/release metadata and a final Pebble application icon. Preserve or explicitly migrate the existing bundle identity, settings/history and login behavior.
2. Add Developer ID signing, hardened runtime, secure timestamp, notarization and stapling. Keep signing keys and credentials outside source control. This is outside the App Store and does not require App Store review. See [Apple Developer ID](https://developer.apple.com/developer-id/).
3. Package a versioned ZIP/DMG, checksums, release notes and compatibility table in [GitHub Releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases). A source ZIP is not an installer. Do not teach users to disable Gatekeeper.
4. Validate on another Mac/account: installation, first launch, Gatekeeper, optional permissions, stable app path/login startup, upgrades preserving data, displays, accessibility and the reported three-finger transition.
5. Run final normal-app resource/stability acceptance for the release build. Keep sampled peaks, lifetime peaks and instrumentation overhead separate; retain unresolved limitations honestly.
6. Add chip-specific adapters and test devices before broadening advertised support. Intel requires a separate build/telemetry effort.

Automatic updates and Homebrew distribution can follow later. No signing credentials or paid services are needed for the current source milestone.
