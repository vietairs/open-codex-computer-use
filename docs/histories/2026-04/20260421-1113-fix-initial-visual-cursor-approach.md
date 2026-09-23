## [2026-04-21 11:13] | Task: Fix initial visual cursor approach

### Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### User Query
> Run the direct call-seq myself and troubleshoot with screenshots, fixing the issue where `set_value` initially appears to move backward.

### Changes Overview
**Scope:** `OpenComputerUseKit` visual cursor runtime

**Key Actions:**
- **Initial cursor approach**: Changed the default appearance point on first display from a fixed screen offset to a resting-forward-based reverse offset, ensuring the first travel vector is consistent with the cursor's facing direction.
- **Regression coverage**: Added a unit test for the default appearance point, locking down the geometric constraint of "appearing from behind the resting-forward side."
- **Documentation**: Updated the overlay behavior description in the architecture doc.

### Design Intent (Why)
A fixed `target + (72, -54)` offset is inconsistent with the current runtime's resting forward, making the first `set_value` movement phase look like it's approaching the target from the side or backward. The default appearance point should be determined by the cursor's own resting forward, not a hardcoded screen direction.

### Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SoftwareCursorOverlay.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/ARCHITECTURE.md`

### Follow-up (2026-04-21, align runtime glyph with CursorMotion)

- **Reference glyph**: `OpenComputerUseKit` now prioritizes loading `official-software-cursor-window-252.png` just like `CursorMotion`, avoiding the programmatic fallback exposing jagged edges on the main path.
- **Packaged app resource**: `scripts/build-open-computer-use-app.sh` now copies the same cursor baseline PNG into `Open Computer Use.app/Contents/Resources/`, and declares `NSHighResolutionCapable`.
- **Fallback boundary**: The programmatic pointer/fog remains as the fallback for when the resource is missing, but is no longer the runtime's default visual path.

**Follow-up Files:**
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SoftwareCursorGlyphRenderer.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/build-open-computer-use-app.sh`
- `docs/ARCHITECTURE.md`
