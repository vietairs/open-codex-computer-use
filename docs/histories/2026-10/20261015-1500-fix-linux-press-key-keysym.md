# Fix Linux press_key keysym synthesis

## Summary

Linux `press_key` sent the wrong keys: Enter typed `4` and modifier shortcuts arrived without their modifiers.

## Changes

- `send_key` now sends named keys and modified characters with `KeySynthType.SYM`, which takes a keysym, instead of
  `PRESSRELEASE`, which takes a hardware keycode.
- Modifiers are held with `LOCKMODIFIERS` / `UNLOCKMODIFIERS` using an X modifier mask, and are released in a
  `finally` block so a failed key send cannot leave a modifier held.
- Single characters are mapped with `Gdk.unicode_to_keyval`, because GDK has no name lookup for punctuation such as `/`.
- Unknown modifiers and key names (including GDK's `VoidSymbol` answer) raise an error instead of being skipped or sent.
- Added Python tests for `send_key` that run without a desktop (`apps/OpenComputerUseLinux/runtime_test.py`).
- Updated the Linux section of `docs/ARCHITECTURE.md` and added a row to `docs/releases/feature-release-notes.md`.

## Notes

- AT-SPI treats the value passed to `PRESS`, `RELEASE`, and `PRESSRELEASE` as a keycode and reads the low byte of a
  keysym, so Return (`0xFF0D`) became keycode 13 and Control_L (`0xFFE3`) became an unmapped keycode.
- This port was verified only against a faked `Atspi` / `Gdk`; no real Linux desktop was available on this macOS host.
