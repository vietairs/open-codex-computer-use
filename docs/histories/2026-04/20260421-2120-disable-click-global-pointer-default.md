## [2026-04-21 21:20] | Task: Align click's non-intrusive default behavior

### 🤖 Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5`
* **Runtime**: `local macOS shell`

### 📥 User Query
> Keep reverse-engineering the official Computer Use's click/HID logic to confirm it, then fix this repo's implementation once you've reached a conclusion, to keep click from hijacking the user's mouse.

### 🛠 Changes Overview
**Scope:** `OpenComputerUseKit` click behavior and architecture docs

**Key Actions:**
- **[Official behavior confirmed]**: Statically confirmed the official package has AX actions, EventTap/CGEvent mouse event generation, `clickEventTap`, `MouseEventTarget`, and `feature/computerUseAlwaysSimulateClick`, but does not directly import public `CGEventPost` / `IOHID*` symbols; `AlwaysSimulateClick` defaults to off.
- **[Global click fallback off by default]**: `click` no longer defaults to calling the global `.cghidEventTap` mouse event after the AX path fails; `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1` must be set to allow the physical-pointer fallback.
- **[Fixed click_count branching]**: `AXPress` / `AXConfirm` / `AXShowMenu` now support repeating by `click_count`, avoiding falling straight into the global mouse path just because `clickCount != 1`.
- **[Added tests]**: Added a unit test confirming the global pointer fallback environment variable is off by default.

### 🧠 Design Intent (Why)
The official implementation does have physical click-simulation capability, but it doesn't simply send every fallback to the system-level hardware cursor; the binary also shows focus-steal suppression, target types, and a feature flag. This repo's current use of `.cghidEventTap` plus `.mouseMoved` directly moves the user's real cursor, which conflicts with the tool's documented expectation of background interaction. Make click's high-risk fallback an explicit opt-in first, while keeping a debuggable escape hatch.

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/ARCHITECTURE.md`
- `docs/histories/2026-04/20260421-2120-disable-click-global-pointer-default.md`
