## [2026-04-22 17:05] | Task: fix targeted mouse coordinate space

### 🤖 Execution Context
* **Agent ID**: `unknown`
* **Base Model**: `GPT-5 Codex`
* **Runtime**: `Codex CLI`

### 📥 User Query
> if mcp click with x,y like `click({"app":"Calendar","x":1060,"y":790})`, it will trigger the "About Mac" page, why? fix this

### 🛠 Changes Overview
**Scope:** `OpenComputerUseKit`, `docs/ARCHITECTURE.md`, `docs/histories/`

**Key Actions:**
- **[Retina pixel mapping fix]**: `click`/`drag`'s screenshot `x/y` is now first mapped from screenshot pixel coordinates back to window points, then combined into Quartz global coordinates, avoiding treating Retina 2x screenshot pixels directly as window points.
- **[Regression coverage]**: Added unit tests for the screenshot-pixel-to-window-point conversion, covering the real Calendar sample's 2x scenario of a `2048x1266` screenshot against `1024x633` window bounds.
- **[Behavior docs]**: Updated the architecture docs to state that coordinate tools first interpret input as screenshot pixel coordinates, then scale them by the ratio of screenshot size to window bounds.

### 🧠 Design Intent (Why)
`get_app_state` exposes screenshot pixel coordinates to the tools. Real window bounds and AX frames, however, are in point units; on a Retina display the two are often off by exactly `2x`. In local live diagnostics, the Calendar screenshot was `2048x1266`, but the window bounds were only `1024x633`. Previously, treating the screenshot pixels directly as window points would push the target point outside the window, so clicking Calendar would instead trigger some other system UI. The key to the fix is not adding another y-flip, but first recovering the screenshot pixel coordinates back into points using the ratio of screenshot size to window bounds.

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/InputSimulation.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/ARCHITECTURE.md`
- `docs/histories/2026-04/20260422-1705-fix-targeted-mouse-coordinate-space.md`
