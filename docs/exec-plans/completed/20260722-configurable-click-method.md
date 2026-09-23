# Configurable click method

## Goal

Add a backward-compatible `click_method` parameter to `click`, letting callers explicitly choose between accessibility, app-posted mouse events, or global pointer events, while keeping the `auto` behavior unchanged when the parameter is omitted.

## Scope

- Included:
  - macOS `click` dispatcher, tool schema, service routing, and input-simulation safety boundaries.
  - The same protocol parameter on Windows / Linux, mapped to existing capabilities, with unsupported errors where needed.
  - Swift / Go unit tests, architecture, security, skill usage, and history docs.
- Not included:
  - Changing the AX descendant candidate-scanning strategy under `auto`.
  - Adding global `SendInput` for Windows, or a process-targeted mouse backend for Linux.
  - Publishing, tagging, or pushing to remote.

## Background

- Related docs: `docs/ARCHITECTURE.md`, `docs/SECURITY.md`, `skills/open-computer-use/references/usage.md`.
- Related code paths: `ComputerUseService.click`, `InputSimulation.clickTargeted` / `clickGlobally`, `MacOSAppAgentProxy`, the Windows UIA / `PostMessage` bridge, the Linux AT-SPI bridge.
- Known constraints: the default behavior must not change; forced modes must not silently fall back; the global pointer still requires `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1`.

## Risks

- Risk: global pointer events move the real mouse, change foreground focus, or hit an unintended window.
- Mitigation: require explicit dual authorization via both the call parameter and the environment variable, and reject unauthorized requests before execution.
- Risk: asymmetric underlying capabilities across platforms.
- Mitigation: keep the public enum consistent, return a stable error for unsupported modes on a given platform, without faking success or silently falling back to another implementation.
- Risk: refactoring the `auto` path introduces behavioral drift.
- Mitigation: keep the existing branches and fallback functions, only adding explicit routing around them.

## Milestones

1. Add the public parameter, parsing, and safety validation.
2. Wire it into the existing implementations on all three platforms and add tests.
3. Update docs, complete verification, and record history.

## Verification

- Command: `swift test`.
- Command: `(cd apps/OpenComputerUseWindows && go test ./...)`.
- Command: `(cd apps/OpenComputerUseLinux && go test ./...)`.
- Command: `npm run package:skill`.
- Manual check: confirm `tools/list` exposes the four enum values, still defaulting to `auto`.
- Observability check: explicit `app_post` does not enter the AX route; explicit `global` without authorization produces no mouse event.

## Progress Log

- [x] Confirmed scope, the existing implementations on all three platforms, and the safety boundaries.
- [x] Completed the protocol and implementation.
- [x] Completed tests and docs.
- [x] Completed verification and archived the plan.

## Decision Log

- 2026-07-22: The public parameter is named `click_method`, with enum values `auto`, `accessibility`, `app_post`, `global`; `app_post` means delivering the event to the target app/window, mapped to `postToPid` on macOS and to HWND `PostMessage` on Windows.
- 2026-07-22: `accessibility` requires `element_index`; `app_post` / `global` can use either `element_index` or `x/y`.
- 2026-07-22: The first Windows version does not support `global`, and the first Linux version does not support `app_post`; both return explicit errors.
- 2026-07-22: Both the macOS CLI and the MCP proxy forward `OPEN_COMPUTER_USE_*` environment variables with the request, ensuring the app agent that actually performs the input can see the global-pointer authorization.
- 2026-07-22: `swift test`, Windows / Linux `go test ./...`, skill packaging, the standard 9-tool smoke test, and the visual-cursor idle smoke test all passed; the live global click, which would move the real mouse, was not auto-executed.
