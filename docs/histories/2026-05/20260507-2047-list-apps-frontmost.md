# list_apps marks the frontmost app

## User Request

Continue aligning with official `computer-use` tool output, prioritizing convergence of the visible differences between `list_apps` and the official output.

## Main Changes

- Added `isFrontmost` state to `ListedAppDescriptor`.
- `list_apps` output now renders `frontmost` for the frontmost app, placing it before `running`.
- Sorting now prioritizes putting the frontmost app at the top of the running-apps list.
- Added unit tests covering both `frontmost` render ordering and sort priority.

## Design Rationale

The official `computer-use`'s `list_apps` explicitly flags the current frontmost app, e.g. `[frontmost, running, ...]`. This flag helps the host determine the current desktop context, and also reduces guesswork by downstream action tools about the target window's state.

## Verification

- `swift test`
- `./scripts/build-open-computer-use-app.sh debug`
- `./scripts/run-tool-smoke-tests.sh`
- `./scripts/check-docs.sh`
- `git diff --check`
- Confirmed via direct Dev app CLI connection that the first line includes `frontmost`

## Files Affected

- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AppDiscovery.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
