# Structured permission query

Port of the read-only `doctor --json` diagnostics onto the fork.

## Changes

- `doctor --json` prints one permission JSON snapshot (`platform`, `accessibilityTrusted`, `screenCaptureGranted`,
  `allGranted`, `missingPermissions`) and never opens onboarding. Missing permissions still exit 0.
- `PermissionDiagnostics.jsonText()` is shared by the CLI path and the shared app agent's CLI handler.
- Fork adaptation: the proxy handles the JSON snapshot before `connectOrLaunchAgent`. It queries the agent only when it is
  already running and current, otherwise reads the diagnostics in the calling process. It never launches, relaunches or
  terminates the agent, and leaves the menu-Quit marker alone.
- Linux and Windows `doctor --json` return an explicit "only supported on macOS" error with nothing on stdout.
- README, architecture notes and the feature release notes describe the flag.

## Verification

Swift unit tests (CLI parsing, proxy routing, JSON payload for all four permission combinations) and the Linux and Windows
Go tests; see the commit for the commands run.
