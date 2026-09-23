# Add macOS SkyLight background click

## Goal

Add an explicit `click_method=sky_click` to `click`, so macOS can deliver a Chromium-compatible background left-click to the target process and window of the current snapshot via the SkyLight private SPI, while keeping the real mouse, foreground app, window z-order, and existing `auto` behavior unchanged.

## Scope

- In scope:
  - macOS SkyLight symbol dynamic resolution, window-targeted event fields, off-window primer, and the real click sequence.
  - macOS `click_method` routing, argument validation, window identity validation, and diagnostic errors.
  - Syncing the Windows / Linux shared enum, and an explicit unsupported result.
  - Swift / Go unit tests, skill usage, architecture, security, reliability, and history docs.
- Out of scope:
  - Modifying `auto` routing or having the existing `app_post` auto-upgrade to SkyLight.
  - `SLPSSetFrontProcessWithOptions` foreground assist, cross-Space snapshots, restoring hidden or minimized windows.
  - Chromium webpage right-click, and surfaces like Canvas / Unity / Blender that only accept global HID.
  - Publishing, tagging, committing, or pushing to remote.

## Background

- Related docs: `docs/ARCHITECTURE.md`, `docs/SECURITY.md`, `docs/RELIABILITY.md`, `skills/open-computer-use/references/usage.md`.
- Related code paths: `ComputerUseService.click`, `InputSimulation.clickTargeted`, `AccessibilitySnapshot.AppSnapshot`, the `click_method` parser/schema for all three platforms.
- Known constraints: an explicit method must not silently fall back; the target window must come from the current snapshot; the private SPI must be probed at runtime via `dlopen` / `dlsym`; the first version only commits to occluded windows that remain on-screen within the same Space.

## Risks

- Risk: the SkyLight functions and raw event fields are undocumented ABI, and could break or crash after a macOS update.
- Mitigation: centrally encapsulate the function signatures and fields, fail closed when symbols are missing, and verify on macOS 14 / 15 / 26 with signed app artifacts.
- Risk: dual delivery via SkyLight and the public `postToPid` could produce duplicate actions on some non-Chromium surfaces.
- Mitigation: keep `sky_click` explicit and never route through `auto`, check for duplicate delivery using a single-count fixture; if duplication occurs, converge the internal post policy to SkyLight-only.
- Risk: a stale snapshot's window id may already be destroyed or reused.
- Mitigation: check the `CGWindowID`'s owner pid and on-screen status before delivery, and require re-running `get_app_state` on a mismatch.
- Risk: primer coordinates or unsupported mouse types hit an unintended target.
- Mitigation: the primer uses both off-window screen/local coordinates; the first version only accepts left-click and 1–2 clicks.

## Milestones

1. Implement the SkyLight SPI, the pure-event recipe, and macOS explicit routing.
2. Sync the protocol, tests, and usage docs across the three platforms.
3. Run unit, cross-platform, skill, smoke, and local capability verification, complete the history entry, and archive the plan.

## Verification

- Command: `swift build`, `swift test`.
- Command: `(cd apps/OpenComputerUseWindows && go test ./...)`.
- Command: `(cd apps/OpenComputerUseLinux && go test ./...)`.
- Command: `npm run package:skill`, `./scripts/run-tool-smoke-tests.sh`.
- Command: `OPEN_COMPUTER_USE_RUN_SKY_CLICK_LIVE_TEST=1 swift test --filter SkyClickLiveTests` (isolated Chrome profile + local page).
- Manual check: `tools/list` exposes `sky_click` on all three platforms, with Windows / Linux returning unsupported before the snapshot lookup.
- Observational check: no event is sent when the SkyLight capability is missing on macOS, the window owner is wrong, it's not a left-click, or it's outside double-click range; the success path never calls `.cghidEventTap` or app activation.
- Live check: a Chrome button fully occluded by another window fires only once, with the foreground PID, real cursor position, and target window z-order unchanged.

## Progress Log

- [x] Completed source research into the article, Cua Driver, yabai, and OCU's existing input paths.
- [x] Completed the SkyLight SPI and macOS `sky_click` routing.
- [x] Completed the cross-platform protocol, tests, and docs.
- [x] Completed automated verification and controlled live verification.
- [x] Completed history and archived the execution plan.

## Decision Log

- 2026-07-22: The public parameter uses `click_method=sky_click`, kept explicitly macOS-only; Windows / Linux return a stable unsupported result.
- 2026-07-22: The first version does not modify `auto`, nor does it introduce `SLPSSetFrontProcessWithOptions`, which can raise or switch Space. Live testing on a fully occluded Chrome window proved that `SLEventPostToPid` alone is insufficient, so a recoverable `SLPSPostEventRecordTo` AppKit-active switch was added, following the article and the yabai pattern.
- 2026-07-22: The event recipe is based on the current Cua Driver Chromium path, including window-local coordinates, PID/window fields, move primer, off-window primer, and click-group id.
- 2026-07-22: The dynamic function pointer for `CGEventSetWindowLocation` is declared per the Cua Rust bridge's `(CGEventRef, double, double)` scalar ABI, and field writes are verified with a delivery-free runtime test, avoiding reliance on Swift's `CGPoint` aggregate-parameter inference.
- 2026-07-22: The focus-without-raise begin/restore steps each keep a 40ms event-record interval, and a real mouse-up is followed by a 100ms renderer settle delay; controlled Chrome page testing verified single firing, foreground PID, real cursor, and z-order all remain unchanged.
