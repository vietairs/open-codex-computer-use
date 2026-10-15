# macOS SkyLight Background Keyboard Reference

## Purpose

This note records how `key_method=sky_key` works, what was verified on real hardware, and which approaches were ruled out. The live findings come from the upstream project's controlled tests on macOS 27.0 (build 26A5425a) against a fully covered, isolated Chrome `--app` window and this repository's fixture app. The test code is `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/SkyKeyboardLiveTests.swift`; it is opt-in and is not part of CI.

## The problem

- An ordinary AppKit app accepts `CGEvent.postToPid` keyboard events while it is in the background: the fixture receives text while inactive and not key.
- Chromium and Electron do not. The page receives `keydown` / `keyup`, but `document.hasFocus()` is false, no `input` event fires, and no text is inserted. Chromium's `content/app_shim_remote_cocoa/render_widget_host_view_cocoa.mm` drives page focus from `OnWindowIsKeyChanged(keyTrackingWindow.isKeyWindow)`: unless the NSWindow is the AppKit key window, the renderer treats the page as unfocused.

## The sequence `sky_key` uses

1. Refuse when the screen is locked or its lock state is unknown. `OPEN_COMPUTER_USE_ALLOW_LOCKED` does not change this.
2. Take the synthetic-focus lock shared with `sky_click`, so no other session's focus records interleave.
3. Validate the target: the app is not hidden, and the snapshot's window id still exists and belongs to the same PID (`CGWindowListCopyWindowInfo(.optionAll)`, so a covered or other-Space window is accepted).
4. If the target app is already frontmost, require that the snapshot's window is its key window and send the keys; nothing else changes.
5. Otherwise reuse `sky_click`'s target-only synthetic-active record (`[0x08]=0x0D`, `[0x8a]=0x01`), sent only to the target PSN, never to the real foreground app.
6. Post yabai's `window_manager_make_key_window` record pair to the target PSN: `[0x04]=0xF8`, `[0x3a]=0x10`, `[0x20..0x30)=0xFF`, the window id little-endian at `0x3c..0x3f`, and `[0x08]` first `0x01`, then `0x02`. The target app makes that window its key window internally; the WindowServer frontmost app, z-order and Space do not change.
7. Wait a fixed 10 ms, then poll the target app's `AXFocusedWindow` (for at most 250 ms) until it maps to the snapshot's window id. If it never does, release the target and fail without sending anything.
8. Send the keys through the existing public `CGEvent.postToPid` path (`InputSimulation.typeText` / `pressKey`). A one-character chord with `cmd` instead presses the target's menu item whose `AXMenuItemCmdChar` and `AXMenuItemCmdModifiers` match, through `AXPress`.
9. Wait a fixed 10 ms and post the deactivate record (`[0x8a]=0x02`) to undo the synthetic state; the Chrome page blurs.

The settle times are constants in code. They are not read from the environment, because a peer's per-call environment is applied to the shared agent process and a huge value would stall every session.

## Menu-bar chords

AppKit dispatches menu key equivalents only for the active app, so `cmd+a` / `cmd+c` / `cmd+v` / `cmd+x` / `cmd+z` sent as key events to a background Chromium do nothing. The target's Edit menu items are enabled in the background, and `AXPress` runs them correctly. Key-binding chords such as `cmd+shift+left` still go as key events.

The fork bounds and narrows the menu walk:

- The first menu-bar item, the Apple menu, is never searched: its items act on the whole login session (Log Out, Lock Screen), not on the target app.
- In the application menu only the menu's own items are searched, not its submenus, which keeps the system-provided Services menu out of reach.
- An item matches only when it reports itself enabled; an unknown state counts as disabled, because `AXPress` does not re-validate the item.
- When more than one enabled item matches, nothing is pressed and the call fails.
- The walk stops at 1,500 nodes, one submenu level, or one second, and each element read carries a 0.5 s AX messaging timeout. When the budget runs out before the walk could rule out a second match, nothing is pressed and the call fails.
- Values read from the menu bar are type-checked with `CFGetTypeID` before use; a wrong type from the target app cannot crash the shared agent.
- A chord with no matching item is sent as key events.

## Verified on real hardware (upstream, macOS 27.0)

- The synthetic-active record alone does not make Chrome key. The activation record must come first and the key-window records second; the other order is ignored.
- Once the window is key, public `postToPid` input works. Cua Driver's `SLSEventAuthenticationMessage` envelope is not required, and it does not help while the window is not key, so this repository does not use it.
- The menu chords listed above work through `AXPress` on a covered Chrome window.
- A target window on another Space (tested with a full-screen Space) also works: the active Space and the frontmost app do not change.
- The foreground fixture stays active, key and first responder throughout; its `resignActive` / `resignKey` counters stay at 0, the real pointer does not move, and the target's z-order does not change.
- An app hidden with `cmd+h` ignores the key-window records, so `sky_key` fails closed for hidden apps and does not unhide them.

The fork-specific additions (the lock rule, the shared lock, the `AXFocusedWindow` confirmation, the narrowed menu walk and the off-stage refusal) have unit coverage only; the live suite has not been re-run against them.

## Approaches ruled out

- `SLPSSetFrontProcessWithOptions` (Cua `with_foreground_assist` / `with_menu_shortcut_activation`): the real foreground app resigns active, which the foreground fixture's counters catch.
- `CGSSetConnectionProperty(cid, targetCid, "SetFrontmost", true)`: returns 1000 on macOS 27 and has no effect on Chrome.
- `SLSEventAuthenticationMessage` + `SLEventPostToPid` alone, stamping window fields 40/51/91/92 on key events, a `sky_click` before typing, or writing `AXFocused` / `AXMain` on the window: none of these focuses the Chrome page.

## Sources

- yabai: [asmvik/yabai](https://github.com/asmvik/yabai/tree/dd845723416f5fe92af49fad5ebab00369e07edd), `window_manager_make_key_window` in `src/window_manager.c`.
- Cua Driver: [trycua/cua](https://github.com/trycua/cua/tree/b8a0f32a06c75225ba24ebb5ab14f6507fa90d15), `libs/cua-driver/rust/crates/platform-macos/src/input/keyboard.rs` and `skylight.rs`.
- Chromium: `content/app_shim_remote_cocoa/render_widget_host_view_cocoa.mm` (`isKeyTrackingWindowKey`, `OnWindowIsKeyChanged`, `performKeyEquivalent:`).

## Compatibility checks

`sky_key` uses the same five private symbols as `sky_click` and fails closed when any is missing. After a macOS update, re-run `OPEN_COMPUTER_USE_RUN_SKY_KEY_LIVE_TEST=1 swift test --filter SkyKeyboardLiveTests` from Terminal.app with Accessibility granted to the test runner.
