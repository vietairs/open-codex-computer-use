# Non-intrusive computer-use interaction rework

## Goal

Make `open-codex-computer-use` avoid seizing the user's current focus and real mouse position during common interactions as much as possible, while also archiving comparison samples against the official `computer-use` into the repository for later data analysis and eval work.

## Scope

- In scope:
- Collecting a set of paired `computer-use` vs. `open-codex-computer-use` calls against the same target app, and saving both the tool calls and their results.
- Adjusting the implementation of `get_app_state` and the action-type tools to reduce unnecessary `activate` calls and global HID events.
- Adding more appropriate targeted delivery or AX-first strategies for keyboard and click paths.
- Syncing tests, architecture docs, the quality notes, and history.
- Out of scope:
- Reproducing the official closed-source implementation's private overlay, host integration, or the full background event routing.
- Resolving compatibility differences for every third-party app in this round.

## Background

- Related docs:
- `docs/ARCHITECTURE.md`
- `docs/REPO_COLLAB_GUIDE.md`
- `docs/QUALITY_SCORE.md`
- Related code paths:
- `packages/OpenCodexComputerUseKit/Sources/OpenCodexComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenCodexComputerUseKit/Sources/OpenCodexComputerUseKit/ComputerUseService.swift`
- `packages/OpenCodexComputerUseKit/Sources/OpenCodexComputerUseKit/InputSimulation.swift`
- Known constraints:
- The current implementation relies heavily on `NSRunningApplication.activate` and `CGEvent.post(tap: .cghidEventTap)`.
- If mouse-type events keep going through global HID, they will in theory still move the real mouse pointer.
- Among the SDK's available capabilities, `CGEventPostToPid` and `AXUIElementPostKeyboardEvent` are confirmed present, but their behavioral boundaries need verification.

## Risks

- Risk: after removing `activate`, some snapshots or actions that depend on the foreground window may fail to get the expected element.
- Mitigation: change snapshot to prefer reading the app's own window/focus info instead of hard-depending on foreground state; keep an explicit fallback path where necessary.
- Risk: `CGEventPostToPid` or `AXUIElementPostKeyboardEvent` may behave inconsistently with global HID on some apps.
- Mitigation: verify with samples on fixtures first; keep a fallback in the code with documented boundaries.
- Risk: over-sacrificing compatibility in order to reduce side effects.
- Mitigation: prioritize "avoid seizing focus where possible," not an unconditional ban on all global input.

## Milestones

1. Collect paired comparison samples from both tools and fix the archive structure.
2. Implement the non-intrusive-first snapshot / input strategy.
3. Complete verification, doc sync, and history record.

## Verification method

- Commands:
- `swift test`
- `./scripts/run-tool-smoke-tests.sh`
- Manual checks:
- Run `get_app_state`, `click`, `type_text` against a fixture app and record the foreground app and mouse coordinates before and after each call.
- Observational checks:
- Verify the paired sample directories under `artifacts/tool-comparisons/20260417-focus-behavior/` are complete.

## Progress log

- [x] Milestone 1
- [x] Milestone 2
- [x] Milestone 3

## Decision log

- 2026-04-17: This round prioritizes fixing the strong-side-effect class of issues around "seizing focus/seizing the mouse," and lands the comparison data directly in the repository, so future eval work can iterate from real samples rather than relying only on verbal descriptions.
- 2026-04-17: `get_app_state` no longer explicitly activates the target app; keyboard events now go through `CGEvent.postToPid`, and clicks prefer AX action / AX hit-test, falling back to global HID only for drag or when an AX element can't be hit.
