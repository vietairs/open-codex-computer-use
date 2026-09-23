## [2026-07-22 17:18] | Task: add configurable click method

### 🤖 Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5.6`
* **Runtime**: `Codex desktop`

### 📥 User Query
> Add an optional implementation choice for `click`, keeping the current behavior as the default, and when explicitly selected, avoid AX candidate matching redirecting the coordinate click to a different element.

### 🛠 Changes Overview
**Scope:** macOS OpenComputerUseKit / app-agent proxy, Windows runtime, Linux runtime, tool schema, skill and repo docs

**Key Actions:**
- **[Shared parameter]**: Added `click_method=auto|accessibility|app_post|global`; when the parameter is not passed, it continues to use the original `auto` routing, and an explicit mode does not silently fall back on failure.
- **[macOS routing]**: `accessibility` only performs AX; `app_post` bypasses AX and uses `CGEvent.postToPid`; `global` bypasses AX and uses `.cghidEventTap`.
- **[Safety gate]**: `global` still requires `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1`, and the CLI / MCP proxy passes the restricted-prefix environment variable along with the request to the app agent.
- **[Cross-platform mapping]**: on Windows, `app_post` maps to HWND `PostMessage` and rejects `global`; on Linux, `global` maps to AT-SPI mouse synthesis and rejects `app_post`.
- **[Verification]**: full Swift test suite, Windows / Linux Go tests, skill packaging, standard tool smoke, and visual cursor idle smoke all passed.

### 🧠 Design Intent (Why)
The automatic AX path for coordinate clicks can scan from the hit container to a clickable descendant that doesn't contain the original coordinate. With an explicit implementation choice added, the caller can keep the default compatible behavior while using `app_post` to strictly send the mouse event at the original coordinate to the target app; the higher-risk global pointer path still requires dual authorization — both the call parameter and the process environment.

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/InputSimulation.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseToolDispatcher.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ToolDefinitions.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift`
- `apps/OpenComputerUseWindows/main.go`
- `apps/OpenComputerUseWindows/main_test.go`
- `apps/OpenComputerUseWindows/runtime.ps1`
- `apps/OpenComputerUseLinux/main.go`
- `apps/OpenComputerUseLinux/main_test.go`
- `apps/OpenComputerUseLinux/runtime.py`
- `docs/ARCHITECTURE.md`
- `docs/SECURITY.md`
- `docs/exec-plans/completed/20260722-configurable-click-method.md`
- `skills/open-computer-use/SKILL.md`
- `skills/open-computer-use/references/usage.md`
