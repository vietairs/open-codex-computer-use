# Structured permission query

Port of the read-only `doctor --json` diagnostics (from the upstream project) onto the fork, adapted so that diagnosing
never starts, replaces or terminates the shared app agent.

## Changes

- `doctor --json` prints one permission JSON object (`platform`, `source`, `accessibilityTrusted`,
  `screenCaptureGranted`, `allGranted`, `missingPermissions`, real JSON booleans, sorted keys) and never opens
  onboarding. Missing permissions still exit 0. Any other `doctor` argument is rejected with
  "doctor accepts only the --json option".
- `source` says whose grants were read: `agent` (the running, current `Open Computer Use.app` agent), `tcc` (no current
  agent: only the app's persisted record in the system TCC database), or `process` (proxy disabled or no app bundle).
- Fork adaptation: the proxy handles the snapshot before `connectOrLaunchAgent` and leaves the menu-Quit marker alone.
  With no current agent it does not measure the calling process (that would report the terminal's grants, not the
  app's). If the TCC database cannot be read (Full Disk Access) it exits non-zero with a stderr message and prints
  nothing on stdout.
- The routing decision (`macOSAppAgentConnectionPolicy`) and the onboarding decision (`shouldPresentPermissionOnboarding`)
  are pure helpers in `OpenComputerUseKit`, with unit tests, plus an exact-JSON-text test.
- Linux and Windows `doctor --json` return an explicit "only supported on macOS" error with nothing on stdout.
- README, architecture, security notes and the feature release notes describe the flag and the `source` field.

## Verification

Run from the worktree with the swift scratch path inside it:

- `swift test --scratch-path <worktree>/<scratch> --filter 'OpenComputerUseKitTests/(testDoctorJSONContract|testPermissionSnapshot|testOnboardingOnly)'`: 5 tests passed.
- `swift test --scratch-path <worktree>/<scratch>`: 828 tests, 2 skipped, 0 failures.
- `go test ./...` in `apps/OpenComputerUseLinux` and `apps/OpenComputerUseWindows`: both ok.
- `scripts/check-docs.sh` and `scripts/check-repo-hygiene.sh`: both passed.

The live no-agent fallback against a real TCC database was not exercised here.
