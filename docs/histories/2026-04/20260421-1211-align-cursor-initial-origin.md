## [2026-04-21 12:11] | Task: Align the cursor's first-appearance origin to the official `(0,0)`

### 🤖 Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5`
* **Runtime**: `local CLI`

### 📥 User Query
> Based on reverse-engineering the official `.app`, we found a fresh cursor appears from the screen's bottom-left `(0,0)`; I want this repository's implementation to start from `(0,0)` too.

### 🛠 Changes Overview
**Scope:** `packages/OpenComputerUseKit`, `docs/`

**Key Actions:**
- **[Initial Origin Alignment]**: When `SoftwareCursorOverlay` has no previous-frame cursor tip, it no longer generates a starting point from behind the target point, but instead computes the first tip from the AppKit global `(0,0)` window origin, matching the official fresh state.
- **[Regression Coverage]**: Updated the unit tests to verify that the default first tip corresponds to a cursor window origin of `(0,0)`.
- **[Docs Sync]**: Updated the architecture notes to clarify that the first display starts from the `(0,0)` window origin, and subsequent actions continue to reuse the previous frame's visible tip.

### 🧠 Design Intent (Why)
The official `SkyComputerUseService`'s `ComputerUseCursor.Window` initialization sets both `currentInterpolatedOrigin` and the initial `NSWindow` content rect to `(0,0)`. The main runtime should reuse this fresh-session semantics, to avoid the first movement segment cutting in near the target and drifting from the official look.

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SoftwareCursorOverlay.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/ARCHITECTURE.md`
- `docs/histories/2026-04/20260421-1211-align-cursor-initial-origin.md`

### 🔁 Follow-up (2026-04-21 12:23)
- **[Runtime Heading Fix]**: Kept the `CursorMotion` / glyph resource's `-3π/4` neutral heading; the main runtime overlay still places the window using AppKit global coordinates, and path selection uses the actual visible AppKit forward heading, but before entering visual dynamics / render state it flips the velocity's y-axis back to `CursorMotion`'s y-down screen state, to avoid the cursor's side facing forward when moving upward.
- **[Regression Coverage]**: Added unit tests locking down the conversion relationship between AppKit upward velocity, CursorMotion screen-state velocity, render rotation, and the final AppKit forward heading.
- **[Docs Sync]**: Updated the architecture notes to clarify the layering between artwork calibration and the runtime motion coordinate basis.
