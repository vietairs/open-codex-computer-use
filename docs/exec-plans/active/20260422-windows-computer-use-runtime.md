# Windows Computer Use Runtime

## Goal

Extend `open-computer-use`, which currently only covers macOS Accessibility, to Windows, prioritizing getting the same set of 9 Computer Use tools running through a standalone `.exe`, while keeping a path for later hardening.

## Scope

- Included:
  - Standalone Windows runtime, not coupled to the Swift `.app`.
  - Go CLI / MCP / `call --calls` entry points.
  - Functional implementations of `list_apps`, `get_app_state`, `click`, `perform_secondary_action`, `scroll`, `drag`, `type_text`, `press_key`, and `set_value`.
  - Windows `.exe` build scripts and basic Go unit tests.
  - Architecture docs, README, and history.
- Not included:
  - Replacing the macOS Swift mainline.
  - Windows installer, code signing.
  - Visual cursor overlay.
  - A complete Windows fixture / smoke suite.

## Background

- Related docs:
  - `docs/ARCHITECTURE.md`
  - `docs/QUALITY_SCORE.md`
  - `docs/exec-plans/active/20260422-remaining-tool-official-alignment.md`
- Related code paths:
  - `apps/OpenComputerUseWindows/`
  - `scripts/build-open-computer-use-windows.sh`
  - `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ToolDefinitions.swift`
  - `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseToolDispatcher.swift`
- Known constraints:
  - Windows UI Automation requires the runtime to run within a logged-in desktop session; an SSH/service process detached from the desktop may not see top-level windows.
  - The first version delivers the `.exe` via Go, but UIA operations call Windows' built-in .NET UI Automation API through an embedded PowerShell bridge.
  - A Win32 window-message fallback can reduce real mouse pre-emption, but different GUI toolkits support background messages inconsistently.
  - Windows has no model equivalent to macOS AX for background keyboard/mouse across arbitrary apps; the current strategy prefers UIA patterns, falls back to window messages on a best-effort basis, and makes foreground-pre-empting paths such as launching the app / `SetFocus` / UIA text fallback explicit opt-ins.

## Risks

- Risk: the PowerShell bridge is slower than pure Go UIA and depends more heavily on Windows PowerShell 5.1 / .NET Framework availability.
  - Mitigation: stabilize the Go runtime's protocol surface, state reuse, and build artifacts first; the bridge's internals can later be replaced incrementally with native Go COM/UIA.
- Risk: SSH verification processes aren't in an interactive desktop context, causing false negatives in `list_apps` / `get_app_state`.
  - Mitigation: use SSH only to verify exe startup, JSON/MCP, and error paths; supplement with interactive-desktop smoke tests for real UI actions.
- Risk: window-message fallback behavior varies significantly across complex apps such as Electron, WinUI, UWP, and browsers.
  - Mitigation: prefer UIA patterns, document fallback behavior explicitly; add Windows fixtures and real-app samples later.

## Milestones

1. Complete the Windows Go runtime skeleton and functional implementation of the 9 tools.
2. Complete the `.exe` build script, Go unit tests, MCP/tools list, and basic SSH verification.
3. Add interactive-desktop smoke tests, Windows fixtures, installer/signing, and a more native UIA implementation.

## Verification

- Commands:
  - `(cd apps/OpenComputerUseWindows && go test ./...)`
  - `./scripts/build-open-computer-use-windows.sh --arch arm64`
  - `open-computer-use.exe --version`
  - `open-computer-use.exe call list_apps`
  - `open-computer-use.exe mcp`
- Manual checks:
  - Open Notepad on a logged-in Windows desktop, run the `get_app_state -> set_value/type_text/press_key/click` sequence.
  - Confirm the action returns the latest state text and screenshot.
- Observability checks:
  - Confirm an empty window list under SSH/service environments is surfaced explicitly, not misreported as a UIA logic failure.

## Progress Log

- [x] Added `apps/OpenComputerUseWindows`, implementing the CLI, MCP, tool schema, `call --calls`, and snapshot cache in Go.
- [x] Embedded a Windows PowerShell UIA bridge implementing functional paths for all 9 tools.
- [x] Added Windows arm64/amd64 `.exe` build scripts.
- [x] Added Go unit tests and wired them into the repo's baseline CI.
- [x] Verified `.exe --version`, `call list_apps`, and MCP initialize/tools-list over SSH to Windows.
- [x] Located, via Windows Codex App session history, the first real MCP test issue: `list_apps` worked; `get_app_state` returned `Argument types do not match` for `Notepad` and `appNotFound(...)` for `notepad.exe`.
- [x] Fixed Windows app matching and made UIA tree rendering tolerant, so a single control's abnormal property no longer fails the whole `get_app_state` call.
- [x] Reproduced and verified `get_app_state -> type_text -> get_app_state` via an interactive Windows scheduled task, confirming the Notepad text area accepted `hello windows mcp` and showed the ValuePattern value in the following snapshot.
- [x] Tightened Windows background-run defaults: no longer auto-launching the app when it isn't found, `SetFocus` disabled by default, both only explicitly enabled via environment variables.
- [x] Changed `type_text`'s default path from UIA `ValuePattern.SetValue` to prefer child-HWND `EM_SETSEL` / `EM_REPLACESEL`; the UIA text fallback that could bring the app to the foreground is now explicit opt-in via an environment variable.
- [x] Verified the new `type_text` path via an interactive Windows scheduled task: all three steps of `get_app_state -> type_text -> get_app_state` returned `isError=false`, Notepad's text contained the `bgmsg-*` marker, and the foreground window stayed Codex before and after the call.
- [ ] Add real UI-action smoke tests for Notepad / Edge etc. on an interactive Windows desktop session.
- [ ] Add Windows fixtures and a repeatable smoke runner.
- [ ] Evaluate using `PrintWindow` / Windows Graphics Capture to add a background screenshot path that doesn't depend on window visibility.
- [ ] Add clearer capability/error signaling for apps/toolkits that must rely on foreground input, instead of silently falling back to focus-stealing behavior.
- [x] Wired the Windows artifact into npm release packaging, distributed as a bundled artifact of the existing npm root/alias packages.
- [ ] Add a Windows signing / installer plan.
- [ ] Evaluate the benefit/risk of replacing the PowerShell bridge with native Go COM/UIA.

## Decision Log

- 2026-04-22: The Windows runtime does not reuse the Swift `.app`; it uses a standalone Go `.exe` to avoid forcing macOS's permission/onboarding model onto Windows.
- 2026-04-22: The first version manages protocol, state, and distribution boundaries in Go, calling Windows UI Automation / Win32 API via an embedded PowerShell, prioritizing a functional closure of the 9 tools.
- 2026-04-22: Kept the same-process state-reuse semantics of `call --calls`; Windows action tools prioritize the `element_index` metadata from the previous round's `get_app_state`.
- 2026-04-22: Real Codex App testing showed `list_apps` worked, but `get_app_state` was still dragged down by abnormal UIA property reads; the Windows snapshot renderer was changed to per-field safe reads and now supports process-name input such as `notepad.exe`.
- 2026-04-22: PowerShell's `@(...)` wrapping of a .NET generic list triggers `Argument types do not match` when returning the object; the Windows bridge now uniformly returns UIA records/element collections via `.ToArray()`.
- 2026-04-22: `type_text` no longer only sends `WM_CHAR` to the top-level window; it now prefers finding a writable `ValuePattern` text element in the same process and appending text, falling back to the window-message path only if none is found.
- 2026-04-22: To avoid Windows tools pre-empting the user's focus, `Resolve-App` no longer `Start-Process`es the target app by default, and the `SetFocus` secondary action returns an error by default; foreground behavior requires explicitly setting `OPEN_COMPUTER_USE_WINDOWS_ALLOW_APP_LAUNCH=1` or `OPEN_COMPUTER_USE_WINDOWS_ALLOW_FOCUS_ACTIONS=1`.
- 2026-04-22: Real Notepad testing showed `type_text`'s UIA `ValuePattern.SetValue` brought the window to the foreground; the default path was changed to the child-HWND `EM_REPLACESEL` background-message path, with the old UIA fallback requiring `OPEN_COMPUTER_USE_WINDOWS_ALLOW_UIA_TEXT_FALLBACK=1`.
- 2026-04-22: An interactive Windows scheduled task verified the new `type_text` path can write into Notepad without switching the foreground from Codex to Notepad; Notepad's text control has UIA class `RichEditD2DPT`, has a child native handle, and can accept `EM_REPLACESEL`.
- 2026-04-23: The Windows release artifact was wired into npm package bundled artifacts, with no new system installer/signing added; the root `open-computer-use` package automatically selects the `.exe` for `win32-arm64` / `win32-x64` via its launcher.
