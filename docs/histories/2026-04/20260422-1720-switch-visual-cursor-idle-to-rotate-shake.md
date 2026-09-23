## [2026-04-22 17:20] | Task: Change the visual cursor idle state to a slight rotational shake

### Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5.4`
* **Runtime**: `Codex CLI on macOS + SwiftPM`

### User Query
> when cursor is waiting for the new move, the animation is left and right horizontally shake, actually, I wanna it makes a tiny rotate shake

### Changes Overview
**Scope:** `OpenComputerUseKit` visual cursor runtime, end-to-end smoke, tests, architecture docs

**Key Actions:**
- **[Tighten idle pose]**: Pinned the visual cursor's idle target back to the resting tip while it waits for the next move, no longer applying left/right or up/down positional shake.
- **[Keep rotate wobble]**: The idle state now only keeps a very small angle offset, making the idle state feel more like "rotating slightly in place" rather than horizontal shaking.
- **[Regression coverage]**: Added a unit test targeting the idle pose, and added a visual cursor idle smoke test to `OpenComputerUseSmokeSuite`, verifying "tip anchored + rotation changes" across processes via an observation file.
- **[Amplitude increase]**: Based on later real-device feedback, raised the idle rotation amplitude from an almost imperceptible level to one that stays tiny but is clearly noticeable to the eye.

### Design Intent
What the user wanted fixed wasn't the move path, but how the cursor looks when it's resting at the target point waiting for the next action. The runtime at the time was still adding a mostly-horizontal small drift on top of the tip position during idle, so it looked more like side-to-side shaking. This change tightens the idle state to "fixed position + small rotational wobble," making the feedback more consistent and aligned with how the repo describes the lab/runtime's goals elsewhere. Later, based on real-device feedback, the amplitude was raised from a nearly-invisible level to a more perceptible range, so the user wouldn't barely notice the rotation.

### Files Modified
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SoftwareCursorOverlay.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/run-tool-smoke-tests.sh`
- `docs/ARCHITECTURE.md`
- `docs/histories/2026-04/20260422-1720-switch-visual-cursor-idle-to-rotate-shake.md`
