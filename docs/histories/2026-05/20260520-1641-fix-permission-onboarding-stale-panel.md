# Fix permission overlay not dismissing after completion

## User Request

The user ran `open-computer-use doctor` which already showed `accessibility=granted, screenRecording=granted`, but the `Drag Open Computer Use...` authorization helper overlay above System Settings kept displaying persistently.

## Main Changes

- `PermissionDiagnostics.current()` now merges TCC's persisted authorization record with the current app process's runtime preflight result.
- If any matching client in TCC is already granted, it's still treated as granted, preserving stable behavior between the app-agent and the CLI.
- If the currently running `.app` process has already passed `AXIsProcessTrusted()` or `CGPreflightScreenCaptureAccess()`, it's also immediately treated as granted, avoiding a stale or mismatched TCC path query result overriding the actual live permission state.
- Added unit test coverage for the persisted/runtime permission merge rule.
- Added `scripts/run-permission-onboarding-e2e.sh`, which, in a real local authorized environment, first checks that `doctor` already reports granted, then asserts that launching onboarding with no arguments exits quickly and doesn't keep the overlay hanging around; the script disables the app-agent proxy by default, to avoid a local ad-hoc `.app` authorization identity interfering with the current CLI runtime regression.
- Updated the permission-determination explanation in the architecture docs.

## Design Intent

Whether the onboarding overlay dismisses depends on `PermissionDiagnostics.current()`'s polling result. Previously, the code prioritized the TCC database query result; when the TCC query returned `false` due to a path/client mismatch or a stale record, it would not fall back to the runtime preflight even if the current app process actually already had permission. This could result in a state where the CLI `doctor` already shows granted, but the old onboarding UI still believes permission is missing and keeps hovering.

The new merge rule treats both a TCC grant and the current process's runtime grant as trustworthy positive signals, avoiding the UI getting stuck after authorization is actually complete.

## Affected Files

- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/Permissions.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/run-permission-onboarding-e2e.sh`
- `docs/ARCHITECTURE.md`

## Verification

- `swift test --filter Permission`
- `swift test`
- `./scripts/check-docs.sh`
- `git diff --check`
- `.build/debug/OpenComputerUse doctor`
- `./scripts/run-permission-onboarding-e2e.sh`
