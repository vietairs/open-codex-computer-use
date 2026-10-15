# Add sky_key background keyboard

## Summary

Port the upstream `key_method=sky_key` background keyboard into the fork, adapted to the shared app agent, the lock-screen policy and the fork's type_text focus gate. Request (condensed): port upstream's SkyLight key-window keyboard path as an explicit `key_method` on `type_text` and `press_key`, with Windows and Linux stubs, without the agent display, window placement, timing log or JS REPL parts.

## Changes

- `SkyLightSPI` gains the key-window record pair, `makeSyntheticTargetWindowKey`, a feature name in the capability text, method-specific error labels, and `syntheticFocusLock`, the one lock every begin...end synthetic-focus sequence takes. `sky_click` now uses it instead of its own lock.
- New `SkyKeyboardDispatcher` (`SkyKeyboardSimulation.swift`): strict lock check, owner validation with `.optionAll`, hidden-app refusal, synthetic focus, key-window records, an `AXFocusedWindow` confirmation that the snapshot's window became key, delivery, release. A failed release after delivery is returned as a warning, not an error.
- Command chords press the matching menu item. The walk skips the Apple menu and the application menu's submenus, needs an item that reports itself enabled, fails on more than one match, and is bounded by 1,500 nodes, one submenu level, one second and a 0.5 s per-element AX messaging timeout. CF values from the target app are type-checked.
- `KeyMethod` / `parseKeyMethod` and `key_method` on `type_text` / `press_key`, single and in `perform_actions` steps. A non-string or unknown value is an argument error. `type_text` with `sky_key` keeps the text-focus gate but always sends key events. Fixture apps accept only `auto`, and a batch refuses a `sky_key` step on a fixture app before any step runs. A `sky_key` step makes the batch's final refresh read-only. Stage Manager off-stage windows are refused.
- Windows and Linux Go servers expose the enum and return `key_method 'sky_key' is not supported on <OS>`.
- Unit tests for the records, the menu walk, the lock rule, parsing, schema, batch policy and fixture refusal, a source-level check that both methods share one lock, and an opt-in live test (`OPEN_COMPUTER_USE_RUN_SKY_KEY_LIVE_TEST=1`).
- Docs: usage keyboard section, `ARCHITECTURE.md`, `SECURITY.md`, `RELIABILITY.md`, a new keyboard reference note, the references index, the yabai section of `THIRD_PARTY_NOTICES.md` and a feature-release row.

## Design notes

- The lock rule ignores `OPEN_COMPUTER_USE_ALLOW_LOCKED`: nobody has verified what synthetic activation and key-window records do while the login window owns the screen.
- The shared agent runs one service per host connection concurrently; two synthetic-focus sequences that interleave would release each other's target, so one process-wide lock covers both methods.
- Settle times are fixed constants (10 ms after the key-window records, 10 ms before release). A per-call environment knob would be set in the shared agent process by any peer, and an infinite value would hang every session.
- Pressing an ambiguous or unvalidated menu item could run a command the user did not ask for, and the Apple menu reaches Log Out and Lock Screen, so the walk fails closed instead of guessing.

## Notes

- Not verified live in this fork: SkyLight delivery, the key-window effect and the `AXFocusedWindow` confirmation on covered Chrome, foreground-state invariance, and the narrowed menu walk on real apps. Upstream verified the base sequence on macOS 27.0.
- Out of scope here and planned separately: covered and other-Space snapshot capture, the occlusion keep-alive, and `sky_click` on covered or other-Space windows.
