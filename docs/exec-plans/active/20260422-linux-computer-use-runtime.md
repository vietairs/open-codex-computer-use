# Linux Computer Use Runtime

## Goal

Extend `open-computer-use` from macOS / Windows to Linux desktop, prioritizing getting the same set of 9 Computer Use tools running in an Ubuntu GNOME desktop session via a standalone binary, and clearly documenting the capability boundaries of Linux desktop automation.

## Scope

- In scope:
  - Standalone Linux runtime, not coupled to the Swift `.app`.
  - Go CLI / MCP / `call --calls` entry points.
  - Functional implementation of `list_apps`, `get_app_state`, `click`, `perform_secondary_action`, `scroll`, `drag`, `type_text`, `press_key`, `set_value`.
  - Linux arm64/amd64 build scripts and basic Go unit tests.
  - Live 9-tool smoke test on an Ubuntu GNOME VM.
  - Architecture docs, README, quality notes, and history.
- Out of scope:
  - Replacing the macOS Swift mainline.
  - Linux installer, desktop entry, system package, or code signing.
  - Visual cursor overlay.
  - Full Linux fixtures / a repeatable smoke runner.

## Background

- Related docs:
  - `docs/ARCHITECTURE.md`
  - `docs/QUALITY_SCORE.md`
  - `docs/SECURITY.md`
  - `docs/RELIABILITY.md`
- Related code paths:
  - `apps/OpenComputerUseLinux/`
  - `scripts/build-open-computer-use-linux.sh`
  - `scripts/ci.sh`
  - `apps/OpenComputerUseWindows/`
- Known constraints:
  - On Linux, the desktop interface closest to macOS AX is AT-SPI2, which exposes the app/window/accessibility tree, actions, editable text, and value interfaces via D-Bus.
  - Under Ubuntu GNOME's default Wayland session, arbitrary background coordinate keyboard/mouse input and screenshots have no unified model equivalent to macOS AX.
  - The first version's strategy prioritizes AT-SPI semantic action / editable text / value, with coordinate click / drag / key synthesis only as a best-effort fallback.
  - SSH ttys have no `XDG_RUNTIME_DIR` / `DBUS_SESSION_BUS_ADDRESS` / display environment by default; the runtime will try to auto-discover a logged-in desktop session for the current Unix user, but cross-user root processes should not be treated as an entry point for controlling a normal user's desktop.

## Risks

- Risk: the AT-SPI tree depth, role, and action names exposed differ greatly across toolkits.
  - Mitigation: the Linux bridge separately relaxes tree traversal depth and keeps field-level tolerance.
- Risk: under Wayland, screenshots may return black images or be rejected by the portal/compositor.
  - Mitigation: screenshots are best-effort only; when an all-black sample is detected, the image block is not returned, to avoid misleading the caller.
- Risk: coordinate click / drag / key synthesis may affect the current foreground context.
  - Mitigation: MCP instructions and the README clearly state the Linux background input boundary; prefer element-targeted AT-SPI actions.

## Milestones

1. Confirm the available interfaces and boundaries on Linux.
2. Complete the Linux Go runtime, Python AT-SPI bridge, and functional implementation of the 9 tools.
3. Complete local unit tests, cross-compilation, and 9-tool smoke test on an Ubuntu GNOME VM.
4. Follow up with Linux fixtures, a repeatable smoke runner, system packages, and a more stable screenshot approach.

## Verification

- Commands:
  - `(cd apps/OpenComputerUseLinux && go test ./...)`
  - `./scripts/build-open-computer-use-linux.sh --arch arm64`
  - `./scripts/build-open-computer-use-linux.sh --arch amd64`
  - `open-computer-use mcp`
  - `open-computer-use call list_apps`
  - `open-computer-use call --calls-file <9-tool smoke json>`
- Manual checks:
  - Open `gnome-text-editor` in an Ubuntu GNOME desktop session.
  - Run the `get_app_state -> set_value -> type_text -> press_key -> perform_secondary_action -> click -> scroll -> drag` sequence.
  - Confirm each tool returns `isError=false`, and that the Text Editor content contains the marker.
- Observational checks:
  - When the current desktop user lacks desktop environment variables, the runtime should first try to auto-discover the same user's session env; if no logged-in session is found, it should return a clear error instead of mistakenly attributing it to an AT-SPI logic failure.

## Progress Log

- [x] Confirmed the Ubuntu GNOME VM has a logged-in `leo` Wayland session, AT-SPI bus, Python GI, Atspi, Gdk/GdkPixbuf.
- [x] Added `apps/OpenComputerUseLinux`, implementing the CLI, MCP, tool schema, `call --calls`, and snapshot cache in Go.
- [x] Embedded a Python AT-SPI bridge implementing app/window discovery, tree rendering, semantic action, editable text, value, key/mouse fallback, and best-effort screenshot.
- [x] Added Linux arm64/amd64 build scripts.
- [x] Added Go unit tests and wired them into the repo's base CI.
- [x] Passed `(cd apps/OpenComputerUseLinux && go test ./...)` locally.
- [x] Passed `./scripts/build-open-computer-use-linux.sh --arch arm64` and `--arch amd64` locally.
- [x] Uploaded the arm64 binary to the Ubuntu VM and confirmed `--version` reports `0.1.33`.
- [x] Confirmed `call list_apps` on the Ubuntu VM returns `isError=false` and includes `gnome-text-editor`.
- [x] Confirmed MCP `initialize` / `tools/list` on the Ubuntu VM, with tool count 9.
- [x] Confirmed the 8-tool sequence on the Ubuntu VM: `get_app_state`, `set_value`, `type_text`, `press_key`, `perform_secondary_action`, `click`, `scroll`, `drag` all return `isError=false`.
- [x] Confirmed on the Ubuntu VM that the `0.1.36` pre-release binary can auto-discover session env under `env -i` for the `leo` user, and successfully runs MCP `tools/list`, `tools/call(list_apps)`, and the 9-tool sequence.
- [x] Confirmed on the Ubuntu VM that after `npm i -g open-computer-use@0.1.36`, the npm launcher selects the Linux arm64 binary, `codex mcp list` shows `open-computer-use mcp` enabled, raw MCP `tools/list` returns 9 tools, and `call list_apps` returns `isError=false`.
- [ ] Add Linux fixtures and a repeatable smoke runner.
- [ ] Evaluate xdg-desktop-portal / compositor-specific screenshot paths to fix non-black captures.
- [x] Wired the Linux artifact into npm release packaging, distributed as a bundled artifact alongside the existing npm root/alias packages.
- [ ] Evaluate the benefit and risk of replacing the Python GI bridge with native Go D-Bus/libatspi.

## Decision Log

- 2026-04-22: The Linux runtime does not reuse the Swift `.app` or the Windows `.exe` bridge, and instead uses a standalone Go binary, to avoid forcibly carrying macOS / Windows permission and input models onto Linux.
- 2026-04-22: The first version uses Go to manage the protocol, state, and distribution boundary, and calls AT-SPI/GDK via an embedded Python GI, prioritizing a functional closed loop for the 9 tools.
- 2026-04-22: Linux uses AT-SPI semantic action / editable text / value by default; coordinate mouse, drag, and keyboard synthesis serve as best-effort fallback, and the MCP instructions explicitly state this is not a general-purpose Wayland background input mechanism.
- 2026-04-22: GNOME Text Editor's AT-SPI tree depth exceeds the 16 layers the Windows runtime uses, so the Linux bridge separately relaxes the traversal depth to 64.
- 2026-04-22: Under GNOME Wayland, GDK root capture returns a black image on the VM; the Linux bridge detects all-black samples and omits the image block, to be revisited later with portal/compositor-specific capture.
- 2026-04-23: The Linux release artifact is wired into npm package bundled artifacts, with no new system installer added; the root `open-computer-use` package auto-selects the binary via the launcher based on `linux-arm64` / `linux-x64`.
- 2026-04-23: The Linux runtime does not write session env into the Codex config or shell profile; before each launch of the Python AT-SPI bridge, the Go runtime dynamically discovers `/run/user/<uid>`, the session bus, the Wayland / X11 display, and AT-SPI-related environment for the current Unix user.
