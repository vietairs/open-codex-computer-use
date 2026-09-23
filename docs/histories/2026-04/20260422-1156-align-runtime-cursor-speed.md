## [2026-04-22 11:56] | Task: Align runtime overlay cursor movement speed

### Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5.4`
* **Runtime**: `Codex CLI on macOS + SwiftPM`

### User Query
> The overlay cursor movement speed in `open-computer-use` seems too fast; compare against the official speed and the adjustable speed in `Cursor Motion`.

### Changes Overview
**Scope:** `OpenComputerUseKit` cursor motion timing, docs, tests

**Key Actions:**
- **[Confirm the discrepancy]**: `Cursor Motion`'s default tier already aligns with the official `response=1.4 / damping=0.9` endpoint-lock time of `343 / 240 = 1.4291667s`, but the runtime still used the old distance-compression formula, actually landing at `0.23s+` in practice, causing mid-to-long-distance moves to be noticeably too fast.
- **[Align runtime timing]**: `OfficialCursorMotionModel.calibratedTravelDuration` now returns the recovered close-enough time directly, no longer compressing the wall-clock duration by path distance and curvature.
- **[Regression test]**: Added a test locking the runtime travel duration to equal the recovered endpoint-lock timing, to prevent distance compression from being reintroduced later.
- **[Docs sync]**: Updated the architecture doc and the reverse-engineered motion-model doc to reflect the default move duration aligning with `343 / 240`.

### Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/CursorMotionModel.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SoftwareCursorOverlay.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/ARCHITECTURE.md`
- `docs/references/codex-computer-use-reverse-engineering/software-cursor-motion-model.md`
- `docs/histories/2026-04/20260422-1156-align-runtime-cursor-speed.md`
