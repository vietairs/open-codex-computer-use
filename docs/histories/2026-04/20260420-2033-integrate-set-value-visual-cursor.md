## [2026-04-20 20:33] | Task: Integrate the `set_value` visual cursor movement pipeline

### 🤖 Execution Context
* **Agent ID**: `primary`
* **Base Model**: `gpt-5.4`
* **Runtime**: `Codex CLI on macOS + SwiftPM + Go`

### 📥 User Query
> Now that Cursor Motion can compute curves, integrate it into `open-computer-use`; scope it down to `click` and `set_value` first, and add a `TextEdit` comparison sequence that can be triggered directly via MCP, so we can observe it side by side with the official bundled `computer-use`.

### 🛠 Changes Overview
**Scope:** `packages/OpenComputerUseKit/`, `packages/OpenComputerUseKit/Tests/`, `scripts/computer-use-cli/`, `docs/`

**Key Actions:**
- **[Wire `set_value` into visual cursor]**: Added `VisualCursorTarget` and a target-point resolution helper in `ComputerUseService`, so that in real-app mode `set_value` runs `SoftwareCursorOverlay.moveCursor(...)` before `AXUIElementSetAttributeValue`, with both success and failure paths converging on `settle`.
- **[Unify internal target resolution for click/set_value]**: `click` now reuses the same visual cursor target representation, so the overlay point/window assembly logic is no longer scattered across branches, while `type_text`, `press_key`, `scroll`, and `drag` keep their existing behavior.
- **[Add tests and a reproducible example]**: Added a `makeVisualCursorTarget(...)` unit test; added `scripts/computer-use-cli/examples/textedit-set-value-click-raise-seq.json`, and documented in the README how to point the same calls file at both the official app-server and the local `OpenComputerUse` direct MCP.
- **[Sync architecture docs]**: Updated `docs/ARCHITECTURE.md` to state that both `click` and `set_value` drive a visual cursor move, and clarified that their finishing steps differ — `click pulse` vs. `settle only`.

### 🧠 Design Intent (Why)
This pass does not attempt to attach the overlay to every action-type tool; instead it converges on the two paths the user has confirmed are most in need of comparison: `click` and `set_value`. `click` already has an official-style motion/pulse pipeline; what `set_value` lacked was the minimal step of moving the visual cursor to the target area before writing the value. Wrapping the target point and target window into a reusable helper lets `set_value` reuse the cursor-motion parameters already validated on the main line, while avoiding future duplication of similar glue code.

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/computer-use-cli/examples/textedit-set-value-click-raise-seq.json`
- `scripts/computer-use-cli/README.md`
- `docs/ARCHITECTURE.md`
- `docs/histories/2026-04/20260420-2033-integrate-set-value-visual-cursor.md`

### 🔁 Follow-up (2026-04-20, fix non-intrusive `click 0` for window/root elements)

- **[Re-verified official behavior]**: Re-ran the `click element_index=0` sample against `TextEdit` on the official bundled `computer-use`, filtering the `SkyComputerUseService` unified log, and confirmed the official log pipeline is `Prepare to interact with element 0` -> `Finished preparing interaction with element 0` -> `Dispatch click to element 0`; there was no sign of the fallback-to-global-pointer pattern this repo previously required.
- **[Fixed local click decision]**: `ComputerUseService.performPreferredClick` no longer only tries `AXPress` / `kAXFocusedAttribute` / `AXConfirm`; it now also folds the window/root-element-common `AXRaise`, `kAXMainAttribute`, and `kAXFocusedAttribute` into the element-targeted left-click path, and only falls back to `clickGlobally(...)` once all of those fail.
- **[Removed an overly strict settable gate]**: For cases like a `TextEdit` window where `AXUIElementIsAttributeSettable(kAXFocusedAttribute) == false` but a direct `AXUIElementSetAttributeValue(..., true)` still succeeds, `click`-related boolean attribute writes no longer treat `isSettable` as a hard precondition.
- **[Added fallback tracing]**: Added a new, default-off `OPEN_COMPUTER_USE_DEBUG_INPUT_FALLBACKS` environment variable; when enabled, a debug line is printed to stderr only when the global pointer fallback is actually hit, making official/local A/B comparisons easier.
- **[Verification result]**: With `OPEN_COMPUTER_USE_DEBUG_INPUT_FALLBACKS=1` enabled, the local direct-MCP sequence `examples/textedit-overlay-seq.json` no longer prints `global pointer fallback`, and `swift test` is all green.

**Follow-up Files:**
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/ARCHITECTURE.md`
- `docs/histories/2026-04/20260420-2033-integrate-set-value-visual-cursor.md`

### 🔁 Follow-up (2026-04-20, align runtime cursor glyph with `CursorMotion`)

- **[Removed the bundle icon-cropping chain]**: `SoftwareCursorOverlay` no longer scans the `SoftwareCursor` asset inside the official `Codex Computer Use.app` bundle and crops it locally; that path was inconsistent with this repo's reverse-engineering conclusions about the official overlay, and it left the main runtime and `CursorMotion` maintaining different glyph shapes.
- **[Extracted a shared procedural glyph renderer]**: Added a shared `SoftwareCursorGlyphRenderer` in `OpenComputerUseKit`, consolidating `CursorMotion`'s current gray pointer + white outline + fog procedural drawing logic, the `126x126` canvas size, and the tip-anchor calibration into a single implementation.
- **[Switched the main runtime to the same cursor]**: `SoftwareCursorView` now calls the shared renderer directly, so the visual cursor for both `click` and `set_value` uses the same procedural glyph as `CursorMotion`, instead of the old gradient triangular pointer or the cropped bundle icon.
- **[Added a shared calibration test]**: Added a unit test that pins the `126x126` canvas and the `60.35 x 70.3` tip-anchor calibration, to keep the main runtime's hit-point calibration from drifting again later.

**Follow-up Files:**
- `Package.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SoftwareCursorGlyphRenderer.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SoftwareCursorOverlay.swift`
- `experiments/CursorMotion/Sources/CursorMotion/SynthesizedCursorGlyphView.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/ARCHITECTURE.md`
- `docs/histories/2026-04/20260420-2033-integrate-set-value-visual-cursor.md`

### 🔁 Follow-up (2026-04-20, remove PNG-first glyph split and re-isolate `CursorMotion`)

- **[Reverted `CursorMotion`'s PNG-first glyph]**: After re-checking the current implementation, confirmed `CursorMotion` was still loading `official-software-cursor-window-252.png` first, which is inconsistent with the user's requirement of a "code-drawn cursor"; the lab now always uses the procedural pointer/fog glyph and no longer depends on that PNG.
- **[Removed the experimental track's direct dependency on the main runtime]**: The previous pass, in order to reuse the glyph renderer, temporarily made `CursorMotion` depend directly on `OpenComputerUseKit`, which conflicts with the repo's long-standing boundary that "the experimental track is independent of the main MCP runtime"; the renderer has now been extracted into a neutral `SoftwareCursorGlyphKit` target that both the runtime and the lab depend on.
- **[Cleaned up the stale asset chain in the packaging script]**: `scripts/build-cursor-motion-dmg.sh` no longer requires copying `official-software-cursor-window-252.png` into the `.app` bundle, since the packaged `CursorMotion` no longer reads that image from the bundle.
- **[Synced current docs]**: The README, architecture notes, and the active execution plan were all updated to the final "procedural glyph + shared neutral target" state, to avoid leaving behind two conflicting narratives of PNG-first and `CursorMotion -> OpenComputerUseKit`.

**Follow-up Files:**
- `Package.swift`
- `packages/SoftwareCursorGlyphKit/Sources/SoftwareCursorGlyphKit/SoftwareCursorGlyphRenderer.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SoftwareCursorOverlay.swift`
- `experiments/CursorMotion/Sources/CursorMotion/SynthesizedCursorGlyphView.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/build-cursor-motion-dmg.sh`
- `experiments/CursorMotion/README.md`
- `docs/ARCHITECTURE.md`
- `docs/exec-plans/active/20260418-standalone-cursor-lab.md`
- `docs/histories/2026-04/20260420-2033-integrate-set-value-visual-cursor.md`

### 🔁 Follow-up (2026-04-20, restore `CursorMotion` and scope glyph reuse to runtime)

- **[Restored the `CursorMotion` boundary]**: The user explicitly reported that `CursorMotion` was already working correctly and should not be dragged along by main-runtime integration changes; the `CursorMotion -> SoftwareCursorGlyphKit` package dependency has been reverted, restoring its original independent-target shape.
- **[Restored the PNG-first lab glyph]**: `SynthesizedCursorGlyphView` is back to the implementation that prefers loading the official `official-software-cursor-window-252.png`, falling back to the local procedural drawing when it's missing; the DMG packaging script also continues to copy this reference image into the bundle.
- **[Runtime-internal replication is enough]**: The procedural glyph renderer needed by `click`/`set_value` now lives only inside `OpenComputerUseKit`, as an implementation detail of the main MCP runtime overlay; no new neutral shared target is added, and `CursorMotion` is no longer required to reuse runtime code.
- **[Synced doc wording]**: The README, architecture notes, and the active execution plan were all reverted to the boundary of "CursorMotion is independent and PNG-first; OpenComputerUseKit draws its own fallback with CursorMotion as a reference", to avoid continuing to mislead future changes.

**Follow-up Files:**
- `Package.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SoftwareCursorGlyphRenderer.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SoftwareCursorOverlay.swift`
- `experiments/CursorMotion/Sources/CursorMotion/SynthesizedCursorGlyphView.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/build-cursor-motion-dmg.sh`
- `experiments/CursorMotion/README.md`
- `docs/ARCHITECTURE.md`
- `docs/exec-plans/active/20260418-standalone-cursor-lab.md`
- `docs/histories/2026-04/20260420-2033-integrate-set-value-visual-cursor.md`

### 🔁 Follow-up (2026-04-21, fix runtime cursor drawing direction)

- **[Fixed the runtime heading baseline]**: `SoftwareCursorOverlay`'s resting heading was changed back to the y-down coordinate baseline `-3π/4` that matches `CursorMotion`, avoiding a visible mirrored arrow direction during vertical movement in tool sequences — like `TextEdit`'s — that use screenshot/CGWindow coordinates directly.
- **[Added the AppKit drawing conversion]**: `SoftwareCursorGlyphRenderer` still receives screen-space motion state, but now converts `rotation` and `dy` into y-up drawing state before the actual AppKit draw, replicating the boundary of `drawingAngle`/`drawingVector` in `CursorMotion`.
- **[Kept CursorMotion untouched]**: This pass only changed the `OpenComputerUseKit` runtime; the `experiments/CursorMotion` demo implementation was not modified.
- **[Added unit tests and docs]**: Added a drawing-state conversion unit test, and documented in the architecture docs the conversion point between runtime motion coordinates and AppKit drawing coordinates.

**Follow-up Files:**
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SoftwareCursorOverlay.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SoftwareCursorGlyphRenderer.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/ARCHITECTURE.md`
- `docs/histories/2026-04/20260420-2033-integrate-set-value-visual-cursor.md`

### 🔁 Follow-up (2026-04-21, align procedural pointer neutral axis)

- **[Fixed the side-leading orientation]**: The user reported again that the runtime cursor still did not lead with its tip but with its side; after re-checking, confirmed the motion rotation semantics were already aligned with `CursorMotion`, and the deviation came from the procedural pointer contour's own neutral axis not matching the official baseline of `-3π/4`.
- **[Added artwork neutral correction]**: `SoftwareCursorGlyphRenderer` now applies an additional fixed artwork correction around the pointer's own center, calibrating the procedural contour's natural axis to the forward direction of `CursorMotion`/the official baseline; the motion layer's heading/path logic stays unchanged.
- **[Kept the experimental track untouched]**: This pass again only changed the `OpenComputerUseKit` runtime; `experiments/CursorMotion` was not modified.
- **[Added unit tests and docs]**: Added a corrected-neutral-heading unit test, and synced the architecture docs to clarify this is a runtime-internal procedural contour calibration.

**Follow-up Files:**
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SoftwareCursorGlyphRenderer.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/ARCHITECTURE.md`
- `docs/histories/2026-04/20260420-2033-integrate-set-value-visual-cursor.md`
