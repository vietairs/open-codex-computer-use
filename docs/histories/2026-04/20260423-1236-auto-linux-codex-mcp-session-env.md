## [2026-04-23 12:36] | Task: Linux runtime should auto-detect desktop session env

## User Request

Wanted Linux to also work directly through the `npm i -g open-computer-use`, `open-computer-use install-codex-mcp`, `codex` path, without manually writing desktop session environment variables such as `XDG_RUNTIME_DIR` and `DBUS_SESSION_BUS_ADDRESS` into the Codex config.

## Key Changes

- **[Linux Runtime]**: Before calling the Python AT-SPI bridge, the Go runtime now fills in any missing Linux desktop session env, auto-discovering the session bus, Wayland / X11 display, X authority, and AT-SPI-related environment from the current user's `/proc` desktop processes and `/run/user/<uid>`.
- **[Codex Install]**: `install-codex-mcp` continues to write the plain `open-computer-use mcp` command, without hardcoding session-related variables into `~/.codex/config.toml`.
- **[Docs]**: README, the Chinese README, architecture, reliability docs, and release notes were updated to describe the Linux runtime's dynamic session-env discovery behavior.
- **[Version Bump]**: Bumped Open Computer Use to `0.1.36`, for a new npm release including the installer fix.

## Design Intent

Linux AT-SPI is not an environment-free background system service; it hangs off the D-Bus session of a logged-in desktop user. `tools/list` can expose the schema alone, but real `list_apps` / `get_app_state` calls require the bridge process to be started with the desktop session environment attached. Putting the detection logic in the runtime, instead of hardcoding it into the Codex config, works better across session restarts, different shells/terminals, and the default experience of different mainstream distros.

## Files Affected

- `apps/OpenComputerUseLinux/main.go`
- `apps/OpenComputerUseLinux/main_test.go`
- `README.md`
- `README.zh-CN.md`
- `docs/ARCHITECTURE.md`
- `docs/RELIABILITY.md`
- `docs/releases/RELEASE_GUIDE.md`
- `docs/releases/feature-release-notes.md`
- Version-source-related files

## Verification

- Passed: `bash -n scripts/install-codex-mcp.sh`
- Passed: `node --check scripts/install-config-helper.mjs`
- Passed: `node --check scripts/npm/build-packages.mjs`
- Passed: `(cd apps/OpenComputerUseLinux && go test ./...)`
- Passed: `(cd apps/OpenComputerUseWindows && go test ./...)`
- Passed: `swift test`
- Passed: `./scripts/build-open-computer-use-linux.sh --arch arm64`
- Passed: `./scripts/build-open-computer-use-linux.sh --arch amd64`
- Passed: `node ./scripts/npm/build-packages.mjs --out-dir dist/release/npm-staging-check`
- Passed: `./scripts/release-package.sh`
- Passed: a temporary `CODEX_HOME` install-config check confirming the Codex config is still `command = "open-computer-use"` / `args = ["mcp"]`, with no session env written.
- Passed: in a Linux VM, as user `leo`, clearing the desktop environment with `env -i` and running `/tmp/open-computer-use-0.1.36-test call list_apps`, which successfully listed `gnome-shell`, `gnome-text-editor`, and `ptyxis`.
- Passed: in a Linux VM, as user `leo`, starting MCP with `env -i`; `initialize`, `tools/list`, and `tools/call(list_apps)` all succeeded.
- Passed: in a Linux VM, as user `leo`, with `env -i`, running a sequence smoke test across all 9 tools — `list_apps`, `get_app_state`, `click`, `set_value`, `type_text`, `press_key`, `scroll`, `drag`, `perform_secondary_action` — all returned `isError=false`.
- Passed: GitHub Actions release workflow `24817430041`, with both `package-npm` and `release-cursor-motion-dmg` succeeding.
- Passed: `npm view open-computer-use@0.1.36`, `open-computer-use-mcp@0.1.36`, `open-codex-computer-use-mcp@0.1.36` were all visible.
- Passed: GitHub Release `v0.1.36` had `What's Changed` added, with `Full Changelog` retained.
- Passed: in an Ubuntu aarch64 VM, user `leo` ran `npm i -g open-computer-use@0.1.36` successfully; `open-computer-use -v` and package.json both showed `0.1.36`, and `dist/linux/arm64/open-computer-use` in the installed package was an aarch64 ELF.
- Passed: in an Ubuntu aarch64 VM, after `open-computer-use install-codex-mcp`, `~/.codex/config.toml` was still `command = "open-computer-use"` / `args = ["mcp"]`, with no session env written.
- Passed: in an Ubuntu aarch64 VM, `codex mcp list` / `codex mcp get open-computer-use` showed the server enabled, with command `open-computer-use mcp`.
- Passed: in an Ubuntu aarch64 VM, as user `leo`, running the npm-installed `open-computer-use` under `env -i` with `call list_apps` succeeded; the raw MCP `tools/list` returned 9 tools.
