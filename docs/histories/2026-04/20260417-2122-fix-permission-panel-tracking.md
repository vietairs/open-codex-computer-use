## [2026-04-17 21:22] | Task: Fix permission-onboarding panel tracking logic

### 🤖 Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5.4`
* **Runtime**: `Codex CLI / Swift 6.2.4 / macOS`

### 📥 User Query
> After opening the permission page, when clicking `Allow` the assist window's tracking is off; it keeps following the `+ / -` row under `System Settings`' `Accessibility` window, and needs fixing.

### 🛠 Changes Overview
**Scope:** `apps/OpenComputerUse`, `docs/`

**Key Actions:**
- **[Restored control-level vertical anchor]**: scan the `+ / -` button row in `System Settings`' Accessibility tree, and prefer that control row as the panel's vertical tracking target.
- **[Kept content-area horizontal alignment]**: the panel still centers on `System Settings`' right-side content area, falling back to the window's bottom edge only when the `+ / -` control geometry can't be obtained.
- **[Synced docs]**: updated the architecture notes and the permission-onboarding execution plan to reflect the latest behavior of "prefer following the `+ / -` row, fall back otherwise".

### 🧠 Design Intent (Why)
The focus of this fix is not simply widening the window-level tolerance further, but separating the horizontal and vertical anchors. The panel keeps centering on the content area to avoid drifting left/right with local layout changes; but its vertical position now follows the `+ / -` control row again, so it doesn't get incorrectly pinned to the bottom on long pages like `Screen & System Audio Recording`.

### 📁 Files Modified
- `apps/OpenComputerUse/Sources/OpenComputerUse/PermissionOnboardingApp.swift`
- `docs/ARCHITECTURE.md`
- `docs/exec-plans/active/20260417-permission-onboarding-app.md`
