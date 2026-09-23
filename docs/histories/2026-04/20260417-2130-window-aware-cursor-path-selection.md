## [2026-04-17 21:30] | Task: Converge the visual cursor's window-aware trajectory

### 🤖 Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `gpt-5.4`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Keep digging into the cursor/overlay implementation inside the official `Codex Computer Use.app`, since the current open-source version still isn't good enough; I want to bring back whatever behavior we can dig out into our own implementation.

### 🛠 Changes Overview
**Scope:** `packages/OpenComputerUseKit`, `docs/references`, `docs/histories`

**Key Actions:**
- **[Window-aware path selection]**: Added multi-candidate Bezier path selection to `SoftwareCursorOverlay`; when the snapshot carries a target `windowID`, it runs a window hit-test against the candidate paths' control points and key sample points, preferring a path that still lands on the target window.
- **[Conservative fallback]**: Added a strict-straight-line conservative fallback, to avoid still hard-playing an exaggerated trajectory when every curved path drifts off the target window.
- **[Ordering resilience]**: The overlay now validates whether the target window still exists before ordering, and keeps checking whether the target window has become invalid during the move animation and idle sway, falling back to normal front-ordering once it becomes invalid.
- **[Docs sync]**: Updated the reverse-engineering docs to add the inference about the official implementation's "binding to a specific target window id" and "trajectory window hit-check," and recorded this round of implementation into history.

### 🧠 Design Intent (Why)
This round isn't about making the overlay flashier — it's about filling in a more critical constraint present in the official implementation: the relationship between the cursor trajectory and the target window. Simply "ordering above the target window" isn't enough; if the control points and intermediate sample points visibly drift outside the target window, the look will differ a lot from the official one. By making path selection window-aware, the most obvious visual deviation can be pulled back in without touching the input-injection pipeline.

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SoftwareCursorOverlay.swift`
- `docs/references/codex-computer-use-reverse-engineering/software-cursor-overlay.md`
- `docs/histories/2026-04/20260417-2130-window-aware-cursor-path-selection.md`
