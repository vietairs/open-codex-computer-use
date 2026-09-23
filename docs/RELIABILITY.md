# Reliability and Operability

## Current Minimum Verification Bar

- Build: `swift build`
- Unit tests: `swift test`
- End-to-end smoke: `./scripts/run-tool-smoke-tests.sh`
- macOS SkyLight live-device regression: `OPEN_COMPUTER_USE_RUN_SKY_CLICK_LIVE_TEST=1 swift test --filter SkyClickLiveTests`
- Linux runtime: `(cd apps/OpenComputerUseLinux && go test ./...)`, `./scripts/build-open-computer-use-linux.sh --arch arm64`
- Local diagnostics:
  - `open-computer-use doctor`
  - `open-computer-use snapshot <app>`

## Known Critical Dependencies

- On macOS, `Open Computer Use.app` must be granted `Accessibility` and `Screen Recording`; the terminal itself should no longer need to be a required authorization target.
- macOS `click_method=sky_click` additionally depends on the private SkyLight / ApplicationServices symbols `SLEventPostToPid`, `SLEventSetIntegerValueField`, `CGEventSetWindowLocation`, `SLPSPostEventRecordTo`, and `GetProcessForPID`. The runtime probes for these dynamically and fails closed, but macOS updates, signing changes, or shifts in a target app's input policy can still break background delivery. Beyond DOM, foreground PID, mouse, and z-order, controlled live-device regression must also verify foreground AppKit active state, key window, first responder, and resign/key-loss counts.
- The smoke suite depends on a local GUI session; it cannot be treated as a headless-environment command.
- `get_app_state` results for ordinary apps depend on the AX tree and window screenshots, so output varies across complex apps; Electron/WebView apps typically have very deep AX trees, and the current implementation compresses empty wrappers and relaxes traversal depth to prioritize retaining actionable text, buttons, and input fields.
- The Linux runtime depends on a logged-in desktop user session; when `XDG_RUNTIME_DIR`, `DBUS_SESSION_BUS_ADDRESS`, or the display environment is missing, it attempts to auto-discover the current user's session env from `/run/user/<uid>` and common desktop processes. A pure SSH tty still cannot access the AT-SPI GUI tree directly if no desktop session can be found.
- GNOME Wayland screenshots may be restricted by the compositor; the current Linux bridge treats black images as invalid screenshots and omits the image block.

## Current Troubleshooting Order

1. Run `open-computer-use doctor` first to check permission status; if permissions are missing, the command launches the permission onboarding window via the `.app` app agent, and if everything is already granted it just prints status and exits.
2. Use `open-computer-use list-apps` to confirm whether the target app is discovered.
3. Use `open-computer-use snapshot <app>` to determine whether it's a transport issue or a snapshot/action issue.
4. If only `sky_click` fails, re-run `get_app_state` first to confirm the window is still on-screen, not hidden/minimized, and hasn't switched Space; if the error mentions `missing SkyLight symbols`, do not silently switch to an implicit fallback — re-verify the private SPI against the current macOS version. If an obscured Chromium page still has no effect, use a controlled page to distinguish renderer policy changes from coordinate/window-local mapping issues.
5. If you only want to verify the repo baseline, run the fixture + smoke suite directly rather than troubleshooting on a complex third-party app first.
6. When troubleshooting the Linux runtime, first confirm whether the target command is being run by the desktop user, then use `open-computer-use call list_apps` and `open-computer-use snapshot <app>` to distinguish a session/env issue from an AT-SPI tree/action issue. For Codex MCP, re-run `open-computer-use install-codex-mcp` and restart Codex, confirming the config is still `open-computer-use mcp`.

## Lock Screen / Stale-Target / Status Menu Troubleshooting

**Locked session:**
- Symptom: all tools (except `tools/list`) return "Session is locked" or "Lock state unknown".
- Diagnosis: `CGSessionCopyCurrentDictionary` returns nil when the user session is locked or unavailable; this fail-closed behavior is the **default**, intended design, not a bug.
- Fix (attended): unlock the current macOS user session and retry, or use an already-logged-in desktop session.
- Fix (unattended agent needing to keep working while the screen is locked): set `OPEN_COMPUTER_USE_ALLOW_LOCKED=1` to enable best-effort lock-screen passthrough. Once enabled, actions can still drive an accessible app via process-targeted delivery (AX / `postToPid`); however **window screenshots return an empty image** (`get_app_state` only returns the AX tree), so coordinate-only paths are unreliable — use `element_index`-targeted actions instead. The first time passthrough is used, stderr prints a one-time degradation notice. Disabled by default.

**Stale target (the target window has changed):**
- Symptom: an action tool returns "Computer Use target screen changed. Call get_app_state for this app before acting again."
- Cause: the target app's pid, window ID, bounds, or screenshot dimensions changed (beyond an 8pt tolerance) since the last `get_app_state` call.
- Fix: call `get_app_state` again to get a fresh snapshot, then perform the action.

**Status menu Restart unavailable:**
- Symptom: the status menu's "Restart" item shows as disabled in direct AppKit MCP mode.
- Cause: `ControlStatusMenuController` only enables Restart in app-agent mode; direct mode requires the host to relaunch it, which cannot be triggered from inside the MCP process.
- Fix: to restart in direct mode, manually restart the `open-computer-use mcp` process on the host side. Restart only works for app-agent sessions launched via the CLI.

## Background-Only Operation Guarantee

By default, all MCP tool operations target apps by PID using accessibility APIs and targeted CGEvents — no app activation (`NSRunningApplication.activate`) is ever called on the normal path.

- `globalPointerFallbacksEnabled()` returns `false` unless `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1` is set; the global pointer paths (`clickGlobally` / `scrollGlobally` / `dragGlobally`) are never invoked without this explicit opt-in.
- Keyboard events use `CGEvent.postToPid` with the target PID; the target app need not be frontmost.
- Mouse events use `AXUIElement` `performAction` or `CGEvent.postToPid` targeted to the app's PID; no front-most requirement exists.
- This guarantees MCP tools do not steal focus, move the user's hardware cursor, or interrupt the user's active workflow.

## Future Hardening Directions

- Add structured logging and failure-reason classification.
- Continue adding failure context for screenshot capture / AX traversal and regression samples on ordinary apps.
- Add ordinary-app regression samples, rather than only covering fixtures.

The default structure for CI/CD pipelines and release automation is documented consistently in `docs/CICD.md`.
