# Feishu Electron Snapshot Stability

## Goal

Compare the real-world behavior of the official `computer-use` and this repo's `open-computer-use` when operating Feishu (飞书), fix this repo's incomplete `get_app_state` tree rendering on deep Electron/WebView UI, and verify the fix works with a repeatable command.

## Scope

- In scope: macOS `get_app_state` AX tree traversal, manual comparison verification on Feishu/Electron deep UI, necessary unit tests, and docs/history.
- Out of scope: rewriting the input simulation strategy, introducing new MCP tools, handling Electron compatibility for the Windows/Linux runtimes.

## Background

- Related docs: `docs/ARCHITECTURE.md`, `docs/RELIABILITY.md`, `docs/QUALITY_SCORE.md`
- Related code paths: `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- Known constraints: for a typical third-party app, the AX tree and screenshots depend on macOS Accessibility and ScreenCaptureKit; Electron apps have a deeper WebView hierarchy than native AppKit controls.

## Risks

- Risk: relaxing traversal depth may cause overly long output or increased traversal time for some complex apps.
- Mitigation: keep a cap on total node count, and add test coverage for deep-tree reachability and the node budget.

## Milestones

1. Compare the official `computer-use`'s and `open-computer-use`'s `list_apps` / `get_app_state` behavior on Feishu.
2. Converge on the code-level cause and implement a minimal fix.
3. Run unit tests, smoke tests, and a live Feishu regression, and record the results.

## Verification

- Command: `swift test`
- Command: `./scripts/run-tool-smoke-tests.sh`
- Manual check: run `get_app_state` against `com.electron.lark` with both `computer-use` and `open-computer-use`, confirming this repo's output covers chat messages and the input box, and returns a screenshot.

## Progress Log

- [x] Confirmed both MCPs can discover the running "Feishu — com.electron.lark".
- [x] Reproduced the discrepancy: the official `get_app_state` can expand into messages and the entry area, while this repo's screenshot is normal but the AX tree stops at a shallow WebView container.
- [x] Completed the minimal fix and tests.
- [x] Completed post-fix verification and recorded history.

## Decision Log

- 2026-05-07: Prioritized fixing AX tree traversal depth without changing the input strategy of action-type tools; the failure point reproduced in this round was that the tree was too shallow, while the screenshot pipeline already returned a valid PNG in the field sample.
- 2026-05-07: Simply increasing traversal depth alone still consumed the 500-node budget on empty Electron wrappers, so empty strings, `AXScrollToVisible` noise, and non-semantic generic wrappers were filtered at the same time; after the fix, the Feishu state can return messages, the entry area, and a PNG screenshot within the 500-node budget.
