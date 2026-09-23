# Preserve the link role for Markdown links

## User request

Keep aligning with the official `computer-use` state renderer, so Lark/Electron app returns stay readable while still preserving actionable-element semantics.

## Main changes

- Fixed `AXLink` being generalized into `container` after children are suppressed.
- Markdown link lines now keep the `link [label](url)` form instead of `container [label](url)`.
- Added a unit test covering the boundary that `AXLink` still keeps the `link` role after flattening.

## Design intent

After the previous pass flattened URL-bearing links into Markdown text, the Lark regression showed the row prefix had become `container`. That improved readability but weakened element semantics. The reverse-engineered official renderer has both `flattenLinksIntoMarkdownText` and `role`/`roleDescription` fields at the same time, so the more sensible shape is to keep the link role while still flattening the text.

## Verification

- Local Lark regression confirms link lines render as `link [label](url)`.
- `swift test`
- `./scripts/build-open-computer-use-app.sh debug`
- `./scripts/run-tool-smoke-tests.sh`
- `./scripts/check-docs.sh`
- `git diff --check`

## Affected files

- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
