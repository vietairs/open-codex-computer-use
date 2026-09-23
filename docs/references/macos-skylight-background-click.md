# macOS SkyLight Background Click Reference

## Purpose

This note records the external research, pinned source versions, and boundaries adopted by OCU that `click_method=sky_click` relies on. SkyLight is a macOS private SPI; what's described here is a source-cross-validated compatible implementation, not a publicly stable API Apple has committed to.

## Reference sources

- Cua article: [Inside macOS Window Internals](https://cua.ai/blog/inside-macos-window-internals)
  - Explains the differences between normal HID hit testing, PID-targeted delivery, and SkyLight delivery.
  - Covers problem areas such as Chromium background input, focus-without-raise, and the AX remote observer.
- Cua Driver: [trycua/cua](https://github.com/trycua/cua/tree/b8a0f32a06c75225ba24ebb5ab14f6507fa90d15/libs/cua-driver)
  - This implementation is checked against commit `b8a0f32a06c75225ba24ebb5ab14f6507fa90d15`.
  - The event sequence baseline comes from `click_at_xy_chromium` in `rust/crates/platform-macos/src/input/mouse.rs`.
  - The dynamic symbol and private function signature baseline comes from `rust/crates/platform-macos/src/input/skylight.rs`.
- yabai: [asmvik/yabai](https://github.com/asmvik/yabai/tree/dd845723416f5fe92af49fad5ebab00369e07edd)
  - Used to cross-check engineering practice around SkyLight dynamic loading and private window APIs; OCU does not copy yabai code.

## The event sequence OCU adopted

`sky_click` uses the current snapshot's PID, `CGWindowID`, in-window coordinates, and screen coordinates, and delivers in the following order:

1. Resolve the target PSN via `GetProcessForPID`, and send a focus record only to the target, briefly putting it into a synthetic-active state; it never queries the foreground PSN, and never sends a defocus record to the real foreground app.
2. A `mouseMoved` at the target point, gesture phase `2`.
3. An off-window primer `mouseDown` / `mouseUp` at `(-1, -1)`, phase `1` / `2`.
4. Wait `100ms`, then deliver the real target `mouseDown` / `mouseUp` at phase `3`.
5. For a double click, wait `80ms` before sending the second pair of events, incrementing the click state from `1` to `2`.
6. Wait for the renderer to consume the async mouse-up, then send a defocus record only to the target, revoking this round's synthetic-active state.

Every event carries the same click-group id and sets the PID, window id, window-under-pointer, and window-local location. Every step goes through both `SLEventPostToPid` and the public `CGEvent.postToPid`: the former covers Chromium/Catalyst, the latter preserves AppKit compatibility. This is a fixed dispatch policy, not a retry-on-failure.

The earlier implementation followed the Cua / yabai focus-without-raise pattern: send a defocus to the real foreground app first, then send a focus restore at the end. Although that sequence doesn't change the WindowServer frontmost PID or z-order, it does trigger AppKit's `resignActive` / `resignKey` and breaks first responder. Controlled Chrome validation showed that synthesizing only the target's focus is sufficient, so the current implementation treats "the foreground app is never deactivated" as a hard constraint.

## What OCU explicitly does not adopt

- It does not call `SLPSSetFrontProcessWithOptions`, and does not use `NSRunningApplication.activate` or `AXRaise` on the target app. It only changes the target app's synthetic event-routing state; the real foreground app's AppKit active state, key window, and first responder must remain unchanged.
- The action-result snapshot after `sky_click` completes uses a read-only recovery policy; if the target AX/window is momentarily unreadable, it returns an error rather than letting the snapshot-recovery path activate or raise the target.
- It does not put `sky_click` into `auto`, and does not fall back to `global` from a failed `sky_click`.
- It does not support right-click, middle-click, triple-click, cross-Space, or hidden/minimized windows.
- It makes no promise that Canvas, Unity, Blender, or other surfaces that reject PID-targeted events will work.

## Compatibility checks

At runtime, the following symbols are probed via `dlopen` / `dlsym`; if any is missing, it fails closed before delivery:

- `SLEventPostToPid`
- `SLEventSetIntegerValueField`
- `CGEventSetWindowLocation`
- `SLPSPostEventRecordTo`
- `GetProcessForPID`

Before delivery, it must also confirm the snapshot's `CGWindowID` is still owned by the same PID and is still on-screen. After a macOS update, symbols, event fields, signed app artifacts, and fully occluded Chromium pages should be re-verified; the on-device bar also includes the foreground fixture's active/key/first-responder state and the transient resign/key-loss count.

## License

The Cua code is under the MIT License. Attribution and license text for the derived event recipe in this repo are in `THIRD_PARTY_NOTICES.md` at the repo root.
