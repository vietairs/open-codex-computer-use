# Recover hidden Electron windows before collecting state

## User request

Keep comparing the open-source `open-computer-use` against the official `computer-use` for tool returns on Lark/Electron apps, and keep improving areas that don't yet match official behavior.

## Main changes

- Added a best-effort window-recovery flow in `get_app_state` for when an AX window is found but no on-screen CGWindow can be found, or no usable focused window can be found for the moment.
- The recovery flow tries unhide, activate, `open -b <bundle-id>`, un-minimize, `AXRaise`, setting main/focused, then briefly waits and retries the window match.
- Kept the official-shape error text for when recovery still fails: `Apple event error -10005: cgWindowNotFound`.
- Updated the architecture docs to explain that hidden/invisible Electron windows are recovered before state is collected.

## Verification

- Comparative observation: the open-source version returned `cgWindowNotFound` on the first request against a hidden Feishu (飞书), while the official `computer-use` brings the window up and returns full state.
- Local regression: after hiding Feishu, calling `get_app_state` directly against a freshly built Dev app returns `isError=false` and includes a screenshot content block.
- `swift test --filter NoWindowErrorMessageMatchesOfficialShape`
- `./scripts/build-open-computer-use-app.sh debug`

## Affected files

- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `docs/ARCHITECTURE.md`
