# Security policy

Mac Buddy is an early source beta. The current `main` branch is the maintained code; there is no guaranteed response time or long-term support release yet.

## Report a vulnerability privately

Use this repository's [GitHub private vulnerability reporting](https://github.com/harshsahrawat-commits/MacBuddy/security/advisories/new). Include the affected revision, macOS/chip, impact and minimal reproduction. If the private form is unavailable, open a public issue asking for a private reporting channel without disclosing exploit details or personal data.

Do not put tokens, signing keys, personal history/preferences, memory dumps or unredacted process data in public issues. Normal bugs and unavailable sensor readings belong in the bug-report template.

## Boundaries

The app runs as the current user, without a privileged helper or App Sandbox. Sensor/IORegistry adapters are read-only, partly undocumented and may stop working after an OS update. The app neither terminates processes nor reads screens, input or document contents. No network service, telemetry upload or update checker is implemented.

Local history and exported reports are not encrypted by Mac Buddy. They rely on your macOS account, filesystem permissions and disk protection. See [privacy](docs/PRIVACY.md). Locally built ad-hoc signatures are not Developer ID distribution signatures or proof of notarization.
