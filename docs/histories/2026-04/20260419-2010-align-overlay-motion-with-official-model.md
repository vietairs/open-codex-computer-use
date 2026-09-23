## [2026-04-19 20:10] | Task: Align the mainline overlay with the official cursor motion

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Based on the existing reverse-engineering analysis, adjust the current mainline implementation so the visual cursor's path and speed behavior get as close as possible to the official look.

### 🛠 Changes Overview
**Scope:** `packages/OpenComputerUseKit/`, `docs/exec-plans/`, `docs/ARCHITECTURE.md`, `docs/histories/`

**Key Actions:**
- **[New mainline motion core]**: Added an independent `CursorMotionModel.swift` in `OpenComputerUseKit`, formally wiring the already-confirmed `CursorMotionPath`, `CursorMotionPathMeasurement`, the 20 official candidates, score selection, and `VelocityVerlet` spring progress into the mainline package.
- **[Replace overlay move implementation]**: Switched `SoftwareCursorOverlay`'s move logic from the old single-segment cubic + `easeInOut` to the official candidate pool + spring progress; kept the existing target-window hit strategy, but now only as a tie-break on top of the official candidate set.
- **[Refactor the visual dynamics layer]**: Removed the patch-style `terminal settle`, and turned the mainline overlay into a two-layer model — "the path layer supplies the target point, and visual dynamics continuously advances the visible tip / angle / fog" — with move / pulse / idle sharing the same state.
- **[Add tests and docs]**: Added mainline unit tests covering the total candidate count, the best candidate for a reference sample, `closeEnoughTime`, and the visual dynamics behavior where "the visible tip keeps overshooting after the target stops, and the angle briefly retains inertia before settling"; updated the architecture doc and execution plan status to match.
- **[Fix heading/offset layering]**: Later, based on binary evidence for the layering of `SoftwareCursorStyle.angle` and `CursorView._animatedAngleOffsetDegrees`, fixed the pose model in both the mainline and the standalone lab so the main heading tracking no longer collapses into just a small wiggle by mistake.

### 🧠 Design Intent (Why)
This isn't another experimental demo — it's landing the already binary-confirmed geometry and spring shape into the actual runtime, to shrink the gap with the official visual behavior. It later turned out the mainline discrepancy no longer mainly came from path candidates, but from lacking an independent pose/render state layer, so the implementation was upgraded from an "end-of-path special-case patch" to a "path target + visual dynamics" two-layer model. Separately, the official transaction-level real duration mapping still isn't fully recovered, so the final wall-clock duration still relies on local calibration, to avoid making the animation look distorted by slowing it down directly.

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/CursorMotionModel.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SoftwareCursorOverlay.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/ARCHITECTURE.md`
- `docs/exec-plans/completed/20260419-overlay-official-cursor-motion-alignment.md`
- `docs/exec-plans/completed/20260419-visual-cursor-pose-dynamics-refactor.md`
- `docs/histories/2026-04/20260419-2010-align-overlay-motion-with-official-model.md`
