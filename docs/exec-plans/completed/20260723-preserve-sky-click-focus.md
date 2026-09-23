# Preserve foreground focus during SkyLight background clicks

## Goal

Fix `click_method=sky_click` briefly deactivating the real foreground application: a fully occluded target window still receives targeted clicks, while the foreground application, key window, first responder, real mouse, and window layering all stay unchanged.

## Scope

- In scope:
  - Collapse the SkyLight activation session from "defocus foreground + focus target + bidirectional restore" down to changing only the target application's compositing state.
  - Add foreground AppKit active, key-window, and first-responder observation to the real-machine Chrome regression.
  - Disable activate/raise recovery for `sky_click`'s action-result snapshot refresh.
  - Sync architecture, reliability, SkyLight reference material, and history.
- Out of scope:
  - Changing the public behavior of `auto`, `app_post`, or `global`.
  - Using `NSRunningApplication.activate`, `AXRaise`, or global HID to remedy a failed background click.
  - Replicating the full event-tap state machine of Codex's closed-source `SyntheticAppFocusEnforcer`.
  - Releasing, committing, or pushing.

## Background

- Related docs: `docs/ARCHITECTURE.md`, `docs/RELIABILITY.md`, `docs/references/macos-skylight-background-click.md`.
- Related code paths: `SkyLightSPI.swift`, `SkyClickSimulation.swift`, `AccessibilitySnapshot.swift`, `ComputerUseService.click`, `SkyClickLiveTests.swift`.
- Known constraints: `SLPSPostEventRecordTo` is a private SPI; the Chromium renderer still needs a brief synthetic focus and an off-window primer; explicit modes must fail closed.

## Risks

- Risk: after sending a focus record only to the target application, Chromium may still reject events for a fully occluded window.
- Mitigation: keep the existing event fields, primer, dual-channel delivery, and renderer settle; verify on a real machine with an isolated Chrome profile; on failure, do not fall back to the old implementation that deactivates the foreground app.
- Risk: the snapshot action-result refresh returns an error when the target AX/CGWindow is momentarily invisible.
- Mitigation: disable recovery only for `sky_click`'s post-click refresh; keep the first explicit `get_app_state` behavior unchanged.
- Risk: comparing only the final AX state misses a brief resign/key-loss.
- Mitigation: have the foreground fixture record cumulative counts of `applicationDidResignActive` and `windowDidResignKey`, and also check the first responder.

## Milestones

1. Land the target-only synthetic focus session and pure-logic tests.
2. Add the non-invasive action-result refresh and the foreground focus probe.
3. Complete unit, build, smoke, and macOS real-machine verification, update docs, and archive the plan.

## Verification

- Command: `swift build`.
- Command: `swift test`.
- Command: `./scripts/run-tool-smoke-tests.sh`.
- Command: `OPEN_COMPUTER_USE_RUN_SKY_CLICK_LIVE_TEST=1 swift test --filter SkyClickLiveTests`.
- Manual check: the user-provided Chrome `sky_click` CLI sequence no longer causes the current application to lose input focus.
- Observation check: the target DOM is clicked exactly once; foreground PID, AppKit active, key window, first responder, mouse, and z-order all stay unchanged; the foreground fixture's resign/key-loss counts do not increase.

## Progress log

- [x] Confirmed the root cause is the old implementation actively sending `focused=false` to the foreground application.
- [x] Completed the target-only synthetic focus session.
- [x] Completed the non-invasive snapshot refresh and focus probe.
- [x] Completed verification, docs, and history.

## Decision log

- 2026-07-23: "without raise" no longer equates to "keeps focus"; the new hard constraint is that no activation record may be sent to the real foreground application.
- 2026-07-23: if target-only synthetic focus cannot satisfy a given target framework, `sky_click` must fail explicitly and must not silently fall back to foreground defocus or global HID.
- 2026-07-23: an isolated, fully occluded Chrome instance can still trigger one DOM click via target-only synthetic focus; the foreground fixture's active, key window, first responder, and loss counters all stay unchanged.
