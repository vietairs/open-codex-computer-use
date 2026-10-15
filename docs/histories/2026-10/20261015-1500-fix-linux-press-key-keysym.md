# Fix Linux press_key keysym synthesis

## Summary

Linux `press_key` sent the wrong keys: Enter typed `4` and modifier shortcuts arrived without their modifiers.

## Changes

- `send_key` now sends named keys and modified characters with `KeySynthType.SYM`, which takes a keysym, instead of
  `PRESSRELEASE`, which takes a hardware keycode.
- Modifiers are held with `LOCKMODIFIERS` / `UNLOCKMODIFIERS` using an X modifier mask, and are released in a
  `finally` block so a failed key send cannot leave a modifier held. The keysym is resolved before any modifier is
  locked, so an unknown key name never touches modifier state.
- Modifier names accepted on Linux: `ctrl`/`control`, `shift`, `alt`, `super`/`win`/`cmd`, plus `command` (Super),
  `option` (Alt), `meta` (Alt, the xdotool convention, Mod1) and the xdotool keysym forms `Control_L/R`, `Shift_L/R`,
  `Alt_L/R`, `Super_L/R`. Matching is case-insensitive.
- The Linux `scroll` fallback goes through `send_key`, so it now sends real Page_Up / Page_Down / arrow keys; before, a
  keysym passed as a keycode typed characters (for example `+` when scrolling down) into the focused field.
- Single characters are mapped with `Gdk.unicode_to_keyval`, because GDK has no name lookup for punctuation such as `/`.
- Unknown modifiers and key names (including GDK's `VoidSymbol` answer) raise an error instead of being skipped or sent.
- Added Python tests for `send_key` that run without a desktop (`apps/OpenComputerUseLinux/runtime_test.py`). They
  assert the full lock / keysym / unlock event sequence, that modifiers are released when the send fails, and that a bad
  key name sends no event.
- Updated the Linux section of `docs/ARCHITECTURE.md` and added a row to `docs/releases/feature-release-notes.md`.

## Notes

- AT-SPI treats the value passed to `PRESS`, `RELEASE`, and `PRESSRELEASE` as a keycode and reads the low byte of a
  keysym, so Return (`0xFF0D`) became keycode 13 and Control_L (`0xFFE3`) became an unmapped keycode.
- Ported from the upstream open-codex-computer-use project (iFurySt/open-codex-computer-use), where the fix was written
  by Aaron Hammer. The core `send_key` change and its tests come from that work; this fork adds the modifier aliases,
  the resolve-before-lock ordering and the stronger release tests.
- Upstream verified the change live on Ubuntu 26.04 with X11 and Chrome. This fork ran it only against a faked `Atspi` /
  `Gdk`; no real Linux desktop was available on this macOS host.
- Wayland is best-effort: whether a lock made through XWayland reaches native Wayland apps is not confirmed.
