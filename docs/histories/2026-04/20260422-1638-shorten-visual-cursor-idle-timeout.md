## [2026-04-22 16:38] | Task: Adjust visual cursor dwell duration

### Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5.4`
* **Runtime**: `Codex CLI on macOS + SwiftPM`

### User Query
> let's optimize the cursor status, currently it will disappeared immediately once it reach the target place, but I wanna it keep float there, only vanish if there is no new move after 30s

### Changes Overview
**Scope:** `OpenComputerUseKit` visual cursor runtime, tests, architecture docs

**Key Actions:**
- **[Idle timeout adjustment]**: Changed the idle cleanup window after visual cursor interaction to `30s`, letting the cursor keep dwelling at the target point and wait for subsequent actions after arriving.
- **[Regression test sync]**: Updated the timeout constant test, preventing the dwell duration from later being changed shorter or longer again without explicit confirmation.
- **[Documentation sync]**: Updated `docs/ARCHITECTURE.md` to state that the current open-source runtime's idle-hide condition has converged to "cleanup only after 30 seconds with no new action".

### Design Intent
This round's goal is not to change the motion curve, but to change the overlay's visibility lifecycle. After the cursor reaches the target point, it should continue resting in place in an idle pose, giving the user a clear "just acted here" signal; it only hides once there has been no new move / click / set_value for a period of time. Here the waiting window is converged to 30 seconds, balancing trackability during consecutive operations against the distraction of long-lived leftover state.

### Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SoftwareCursorOverlay.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/ARCHITECTURE.md`
- `docs/histories/2026-04/20260422-1638-shorten-visual-cursor-idle-timeout.md`
