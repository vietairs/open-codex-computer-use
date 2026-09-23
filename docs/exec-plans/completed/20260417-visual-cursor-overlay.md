# Visual Cursor Overlay

## Goal

Give `open-computer-use` a visible software cursor overlay on the `click` path: it moves along a curve toward the target point before clicking, gives clear visual feedback on click, lingers briefly afterward with a slight idle sway, then auto-hides — all while preserving the current AX-first, avoid-stealing-focus execution strategy.

## Scope

- Included:
- Add a main-thread runtime for `mcp` mode capable of hosting an AppKit overlay.
- Implement a software cursor overlay as an independent transparent window.
- Wire the `click` path to the overlay without changing the existing AX-first / HID-fallback decision logic.
- Add necessary tests, and sync the README, architecture docs, and history.
- Not included:
- This round does not replicate the official closed-source cursor's private assets, full choreography, or private event-injection pipeline.
- This round does not wire drag, scroll, or keyboard input into the unified overlay.

## Background

- Related docs:
- `docs/ARCHITECTURE.md`
- `docs/REPO_COLLAB_GUIDE.md`
- `docs/references/codex-computer-use-reverse-engineering/software-cursor-overlay.md`
- `docs/PLANS_GUIDE.md`
- Related code paths:
- `apps/OpenComputerUse/Sources/OpenComputerUse/OpenComputerUseMain.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/InputSimulation.swift`
- Known constraints:
- The current `mcp` mode is a synchronous `readLine()` main loop, with no long-running AppKit event loop.
- The official implementation already has evidence of an independent `Software Cursor` window and Bezier motion, but the open-source version currently has no overlay UI.
- The click path has already been converged toward AX-first; the new overlay must not break this behavioral boundary.

## Risks

- Risk: Modifying the `mcp` runtime to support the overlay may affect existing stdio read/write stability.
- Mitigation: Keep the change surface minimal; only switch to the AppKit runtime when the visual cursor is enabled, and keep stdin reads serialized.
- Risk: The overlay's AppKit UI may interfere with the smoke suite or hit-testing on ordinary apps.
- Mitigation: Make the overlay window transparent and mouse-event-ignoring, and provide the smoke suite with an explicit disable switch.
- Risk: Visual animation may become out of sync with the actual action, confusing the user further.
- Mitigation: Explicitly design the overlay as a "visual cue layer" — actions still execute via the existing AX/HID path, and the click pulse is centered only on the final target point.

## Milestones

1. Runtime and overlay infrastructure land.
2. The `click` path is wired to the visual cursor.
3. Verification, doc sync, and archiving.

## Verification

- Commands:
- `swift test`
- `./scripts/run-tool-smoke-tests.sh`
- Current results:
- `swift test` passes.
- `./scripts/run-tool-smoke-tests.sh` still hits an existing `list_apps`/fixture constraint: the current `AppDiscovery.listCatalog()` only converges on user-facing apps with a bundle ID, while the smoke fixture is a directly-run executable that doesn't appear in that output; this is not a regression introduced by visual cursor in this round.
- Subsequent follow-ups have continued converging cursor sizing, official asset fallback, and ordering logic relative to the target window; this part continues to pass `swift test`.
- Manual checks:
- Ran `click` repeatedly against a real app, confirming the overlay lingers briefly near the target point with a slight idle sway before auto-disappearing.
- In AX-action-hit scenarios, confirmed the foreground app is not additionally `activate`d after the click.
- Observational checks:
- `CGWindowListCopyWindowInfo` shows a transparent overlay window present under the `open-computer-use` process.

## Progress Log

- [x] Milestone 1
- [x] Milestone 2
- [x] Milestone 3

## Decision Log

- 2026-04-17: Prioritize implementing "independent overlay window + curved motion + click pulse + idle sway," without attempting to replicate all of the official private choreography in this round.
- 2026-04-17: `mcp` mode only switches to the AppKit runtime when the visual cursor is enabled, avoiding forcing a full runtime refactor onto all headless scenarios.
- 2026-04-17: The smoke suite continues to explicitly disable the visual cursor, since this regression chain's goal is to verify the tools' behavioral closure, not the UI animation itself.
- 2026-04-17: For official bundle assets, prefer "read at runtime + process locally then draw" over vendoring closed-source images directly into the open-source repo.
