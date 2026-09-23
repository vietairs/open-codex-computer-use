## [2026-04-19 13:20] | Task: Deepen the static model of official cursor motion

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Continue analyzing the official `Codex Computer Use.app`, focusing on the algorithm behind "calculates natural and aesthetic motion paths"; try to work out from the app how the curve and speed are computed.

### 🛠 Changes Overview
**Scope:** `docs/references/codex-computer-use-reverse-engineering/`, `docs/histories/`

**Key Actions:**
- **[Strengthen static-analysis evidence]**: recovered `SkyComputerUseService`'s `__swift5_types` / `__swift5_fieldmd` statically, no longer relying only on `strings` keyword hits.
- **[Confirm cursor path types]**: added field-level evidence to the docs for `ComputerUseCursor`, `Window`, `Style`, `CloseEnoughConfiguration`, `CursorNextInteractionTiming`, `CursorMotionPathMeasurement`, `Segment`, and `CursorMotionPath`.
- **[Confirm timing / spring types]**: added field-level evidence to the docs for `BezierAnimation`, `SpringAnimation`, `BezierFunction`, `BezierParameters`, `SpringParameters`, `VelocityVerletSimulation`, `Configuration`, and `AnimationDescriptor`.
- **[Correct an earlier inference]**: downgraded the earlier claim that mapped `ARC SIZE` directly to `arcHeight`, replacing it with a more conservative mapping to the cursor path's `arc` / control-point offset.
- **[Clarify the next-interaction gate]**: based on `CloseEnoughConfiguration(progressThreshold, distanceThreshold)` and `CursorNextInteractionTiming(closeEnough, finished)`, added a judgment on the timing mechanism that lets the next interaction start before the animation has fully finished.

### 🧠 Design Intent (Why)
The motion-model docs had previously mostly stayed at the stage of "here are the strings we saw, so here's what layers we infer exist." This round also parses out the Swift metadata, to move the curve and speed model from conceptual inference to field-level evidence, reducing the chance of guessing the official structure wrong in a later open-source implementation.

### 📁 Files Modified
- `docs/references/codex-computer-use-reverse-engineering/software-cursor-motion-model.md`
- `docs/histories/2026-04/20260419-1320-deepen-official-cursor-motion-analysis.md`
