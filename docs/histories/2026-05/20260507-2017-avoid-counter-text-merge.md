# Avoid merging counter-text siblings

## User request

Continued comparing `get_app_state` output for Lark / Electron apps against the official `computer-use`, fixing state-rendering details that didn't match.

## Main changes

- Adjusted the `mergeTextOnlySiblings` rule: when a sibling's text contains a `number/number` counter shape, no longer merge the whole group of text into a single-line summary.
- Added a unit test covering `["消息", "126/126"]` (`消息` = "Messages") not being merged.

## Design intent

The official Lark sample renders "Messages" and the unread/total counter as separate text nodes. The open-source version previously output `text 消息 126/126` (`消息` = "Messages"); the information was still present, but the structure was coarser and didn't match the official tree shape. This rule only targets clear counter siblings, avoiding the node-budget pressure that would come from broadly abandoning short-text merging.

## Verification

- Local Lark regression confirms the output now shows separate `text 消息` (`消息` = "Messages") and `text 126/126` nodes.
- `swift test --filter AccessibilityRendererOnlyMergesShortTextOnlySiblingRuns`
- `./scripts/build-open-computer-use-app.sh debug`

## Affected files

- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
