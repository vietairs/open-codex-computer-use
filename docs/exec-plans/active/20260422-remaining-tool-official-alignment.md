# Remaining Computer Use Tool Alignment

## Goal

Now that `click` and `set_value` have finished aligning with official behavior, reverse-engineer and align the remaining 7 Computer Use tools one by one, focused on confirming whether they hijack the user's real mouse or steal foreground focus, and land the conclusions, implementation gaps, tests, and doc status in the repo.

## Scope

- In scope:
  - `list_apps`
  - `get_app_state`
  - `perform_secondary_action`
  - `scroll`
  - `drag`
  - `type_text`
  - `press_key`
  - The current version of the official bundled `computer-use`'s `tools/list`, static strings, imported symbols, and disassembly-based localization where needed.
  - Each tool's local implementation gaps, behavior fixes, tests, architecture docs, and history.
- Out of scope:
  - Reopening the already-completed `click` / `set_value` behavior fixes, unless reverse-engineering the remaining tools reveals a shared underlying layer that needs patching.
  - Reproducing the official closed-source host authorization, private IPC, or the full visual cursor choreography.
  - Using global physical mouse events as the default fallback just to buy surface-level pass rates.

## Background

- Related docs:
  - `docs/ARCHITECTURE.md`
  - `docs/references/codex-computer-use-reverse-engineering/tool-call-samples-2026-04-17.md`
  - `docs/references/codex-computer-use-reverse-engineering/internal-ipc-surface.md`
  - `docs/histories/2026-04/20260421-2120-disable-click-global-pointer-default.md`
  - `docs/histories/2026-04/20260422-1050-align-set-value-settable-boundary.md`
- Related code paths:
  - `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ToolDefinitions.swift`
  - `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseToolDispatcher.swift`
  - `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
  - `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/InputSimulation.swift`
  - `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
  - `apps/OpenComputerUseFixture/Sources/OpenComputerUseFixture/main.swift`
  - `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- Known constraints:
  - In the official `1.0.755` `tools/list`, `scroll.pages` is a `number`, with copy reading `Number of pages to scroll. Fractional values are supported. Defaults to 1`; older install roots may still expose the old `integer` schema.
  - The official binary exposes type names such as `MouseEventTarget`, `KeyboardEventTarget`, `EventTap`, `SyntheticAppFocusEnforcer`, `SystemFocusStealPreventer`, `UIElementScrollOperation`, `ScrollAreaUIElement`, and `ScrollBarUIElement`, which indicates action routing is not simply sending every fallback to a global HID cursor.
  - Local `drag` / `scroll` have already had their default paths fixed: the global `.cghidEventTap` is now only enabled when `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1` is set, defaulting instead to AX or pid-targeted events; the official private `MouseEventTarget` / `UIElementScrollOperation` are only confirmed statically as evidence, and this round does not attempt to reproduce their closed-source internal implementation.

## Risks

- Risk: only aligning the schema without handling the global-event fallback, so users can still have their mouse or focus hijacked.
  - Mitigation: for every action tool, explicitly write down its default execution path and whether a fallback is allowed; any high-risk physical-pointer path must be an explicit opt-in or replaced with a narrower targeted route.
- Risk: official behavior is implemented via private AccessibilitySupport types, so the open-source version can only approximate it.
  - Mitigation: distinguish between "confirmed identical," "confirmed different but with a safe alternative," and "pending reverse engineering"; do not write guesses as conclusions.
- Risk: changes to `drag` / `scroll` could affect the smoke fixture.
  - Mitigation: keep the fixture bridge deterministic; add separate unit tests for the real app path covering parameter parsing and fallback gating.

## Per-Tool TODO

- [x] `click`: already aligned to prefer element-targeted AX, repeat AX actions for `click_count`, and default-deny global physical pointer fallback.
- [x] `set_value`: already aligned to the `AXUIElementIsAttributeSettable(kAXValueAttribute)` precheck, returning an official-style error when not settable instead of falling back to keyboard/clipboard/undocumented text replacement.
- [x] `list_apps`: reviewed official `1.0.755` output fields, ordering, and denylist effects; confirmed the local Spotlight + running-app merge is still consistent.
- [x] `get_app_state`: reviewed the official session/start-state, screenshot, AX-tree rendering, stale-state error, and non-foreground-stealing policy; confirmed the local non-`activate` boundary.
- [x] `perform_secondary_action`: reviewed official action-name matching, menu-item/secondary-action error semantics, and whether a prepare interaction is needed; confirmed the local AX action path does not steal focus.
- [x] `scroll`: aligned to the official `pages` number schema and fractional pages; statically confirmed `UIElementScrollOperation` / scroll-bar type clues, eliminating the default global physical-event fallback.
- [x] `drag`: statically confirmed `MouseEventTarget` / drag-dispatch type clues; eliminated the default global mouse-event fallback, kept as an explicit opt-in.
- [x] `type_text`: reverse-engineered `KeyboardEventTarget` / keyboard-layout error semantics; confirmed the local `postToPid` does not steal focus, and aligned missing-text / Unicode edge cases.
- [x] `press_key`: reverse-engineered the xdotool key parser, keyboard layout, modifier semantics, and error copy; confirmed the local `postToPid` does not steal focus.

## Milestones

1. Confirm the official `1.0.755` schema, static strings, imported symbols, and current local differences for the remaining 7 tools.
2. Complete convergence on `scroll` / `drag`'s default non-physical-pointer path, fractional scroll, required-parameter errors, and secondary-action error semantics.
3. Complete the review conclusions, tests, docs, history, and final state cleanup for `list_apps` / `get_app_state` / `type_text` / `press_key`.

## Verification

- Commands:
  - `swift test`
  - `swift build --product OpenComputerUse`
  - `COMPUTER_USE_PLUGIN_ROOT="$HOME/.codex/plugins/cache/openai-bundled/computer-use/1.0.755" go run . list-tools --transport app-server`
  - `go run . list-tools --transport direct --server-bin ../../.build/debug/OpenComputerUse`
  - `./scripts/run-tool-smoke-tests.sh`
- Manual checks:
  - `tools/list` matches the official `1.0.755` schema, especially `scroll.pages`.
  - Every action tool can state whether it uses AX, a pid-targeted event, a window-targeted event, or an explicit opt-in physical pointer fallback.
  - No mouse-move / drag fallback that moves the system's real hardware cursor is allowed on the default path.
- Observation checks:
  - When running against real app samples, the user's hardware mouse position should not change due to a default tool call.
  - After an action, the response still includes the latest state text and screenshot.

## Progress Log

- [x] Confirmed the official `1.0.755` schema, static strings, imported symbols, and current local differences for the remaining 7 tools.
- [x] Completed convergence on `scroll` / `drag`'s default non-physical-pointer path, fractional scroll, required-parameter errors, and secondary-action error semantics.
- [x] Completed the review conclusions, tests, docs, history, and final state cleanup for `list_apps` / `get_app_state` / `type_text` / `press_key`.

## Decision Log

- 2026-04-22: Split the remaining 7 tools into an independent checklist; `drag` and `scroll` are prioritized first because they have global-event fallbacks, with the keyboard-class and read-only-class tools reviewed afterward.
- 2026-04-22: Confirmed the official `1.0.755` `scroll.pages` is a `number` schema; the `integer` schema returned by older plugin roots is treated as an old-version baseline and is no longer an alignment target.
- 2026-04-22: Confirmed the official app-server treats an empty string for a required string as missing; the local dispatcher has been unified to treat required strings as non-empty and return `Missing required argument: <name>`.
- 2026-04-22: Local `scroll` / `drag` no longer call the global `.cghidEventTap` and app-activation fallback by default; when no AX scroll action is matched, they now first target the process directly via `CGEvent.postToPid`, and only fall back to the physical pointer when `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1` is explicitly set.
- 2026-04-22: `perform_secondary_action` keeps the AX action path; the invalid-action error has been changed to the official string form; the fixture's `Raise` no longer calls the global pointer prepare step.
- 2026-04-22: The official binary's key table includes xdotool names such as `BackSpace`, `Page_Up`, `Prior`, `Next`, `F1...F12`, and the full `KP_0...KP_9/KP_Enter` set; the local `press_key` parser has been filled in with these common aliases, still delivered directionally via `CGEvent.postToPid`.
- 2026-04-22: `list_apps` / `get_app_state` had no new code paths added this round: the current implementation already outputs running + last-14-day apps per the official surface, and `get_app_state` does not actively `activate` the target app; verification is based on the official/local `tools/list`, the smoke suite, and existing reverse-engineering samples.
