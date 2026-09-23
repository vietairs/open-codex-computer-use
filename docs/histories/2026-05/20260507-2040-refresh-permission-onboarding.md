# Refresh Dev Permission Onboarding

## User Request

After the Dev build is already authorized in System Settings, the permission onboarding window still shows `Allow`, making it look like the authorization didn't take effect.

## Main Changes

- The permission onboarding title and description now use the current bundle name; the Dev build shows `Open Computer Use (Dev)`.
- After the user clicks `Allow`, if the current process still hasn't seen the permission refresh, the corresponding card switches to `Restart` after a brief wait.
- Clicking `Restart` relaunches the current app bundle, so macOS refreshes the Accessibility / Screen Recording permission status for the new process.

## Design Intent

macOS doesn't always immediately refresh newly granted TCC permissions for an already-running app agent. When System Settings already shows the permission granted, continuing to show `Allow` misleads the user into retrying repeatedly. Explicitly switching to `Restart` better matches actual state, and also avoids requiring the user to manually find the process and restart it.

## Validation

- `swift test`
- `./scripts/build-open-computer-use-app.sh debug`
- `./scripts/run-tool-smoke-tests.sh`
- `./scripts/check-docs.sh`
- `git diff --check`

## Files Affected

- `apps/OpenComputerUse/Sources/OpenComputerUse/PermissionOnboardingApp.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/Permissions.swift`
