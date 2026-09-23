# Align Feishu state wrappers

## User request

After restarting Codex, the user asked to keep comparing `open-computer-use` against the official `computer-use`, confirming how the new Dev app build differs in Feishu (飞书) / Electron state rendering.

## Changes

- Aligned with the official `computer-use`'s Electron state tree: a generic wrapper with a single child, no own semantics, and only a `settable/string` trait is now elided.
- Under WebArea, a single-child generic container is no longer kept just because it's at a shallow depth, reducing redundant layers at the top and body of Feishu pages.
- Added an independent time-range guard to the text-merging rule, to avoid merging a schedule title, a countdown, and an `HH:mm - HH:mm` time range into one sentence.
- Text summarization now lets AXLink participate in merging, so content list items can better match the official single-line summary shape.
- Standalone AXLink rendering also now consistently keeps the markdown link form, and avoids emitting a duplicate `Description` alongside a long URL.
- Added unit tests covering wrapper elision and time-range merge boundaries.

## Validation

- `swift test`
- `./scripts/build-open-computer-use-app.sh debug`
- Connected directly to the newly built Dev app and sampled `get_app_state`, confirming the empty wrapper before Feishu's top-level `ClientView` is now elided and schedule time ranges are no longer merged.
- Connected directly to the newly built Dev app and sampled link rendering, confirming long Feishu links are output as markdown links without a duplicate `Description`.
- `./scripts/run-tool-smoke-tests.sh`
- `./scripts/check-docs.sh`
- `git diff --check`

## Affected files

- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
