# Align AX tree root-node indentation

## User Request

Continue comparing the `get_app_state` output between the open-source version and the official `computer-use` on Lark / Electron apps, and progressively fix mismatched output shapes.

## Main Changes

- Changed the real AX tree renderer's root-node indentation from one tab level to flush-left.
- Applied the same indentation rule to synthetic text nodes, avoiding summary children being indented one level deeper than real children.

## Design Intent

In the official Lark output, the root node is flush-left, like `0 standard window ...`, with child nodes starting at one tab level. The open-source version previously output `\t0 standard window ...`, so the whole tree was indented one level deeper than official, which hurt comparison and readability.

## Verification

- Local Lark regression confirms the first three tree lines are now: root node flush-left, level-1 children at one indent level, level-2 children at two indent levels.
- `swift test --filter SnapshotRenderedTextStartsDirectlyWithAppHeader`
- `./scripts/build-open-computer-use-app.sh debug`

## Files Affected

- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
