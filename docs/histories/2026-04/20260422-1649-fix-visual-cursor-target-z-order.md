## [2026-04-22 16:49] | Task: Fix visual cursor target z-order

### Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5.4`
* **Runtime**: `Codex CLI on macOS + SwiftPM`

### User Query
> the virtual cursor current z index is above the target app, but under the current active app, but if I invoke the target app manually, the virtual cursor will behind the target app, fix this, make the virtual cursor always on top of target app

### Changes Overview
**Scope:** `OpenComputerUseKit` visual cursor overlay ordering, tests, architecture docs

**Key Actions:**
- **[Ordering refresh]**: adjusted `SoftwareCursorOverlay`'s ordering logic so that, while visible, the overlay continuously reasserts that it should sit above the target window, rather than ordering only once when the target window changes.
- **[Regression coverage]**: added unit tests for two cases — "forced reordering" and "no repeated reordering for a stable window" — to prevent regressing back to one-time ordering.
- **[Docs sync]**: updated `docs/ARCHITECTURE.md` to record the behavior "still stays above the target window even after the user manually activates the target app" back into the architecture description.

### Design Intent
This wasn't about adjusting the cursor's visual appearance, but fixing the persistent layering relationship between the overlay and the target window. The root cause was that the existing implementation only called `order(.above, relativeTo:)` once, when `activeTargetWindow` changed; when the user subsequently activated the target app manually, the system reordered that app's windows, but the overlay never reasserted its ordering position, so it ended up dropping behind the target window. After the fix, as long as the overlay remains visible, it continuously reasserts its ordering relative to the target window, keeping it "always on top of the target app."

### Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SoftwareCursorOverlay.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/ARCHITECTURE.md`
- `docs/histories/2026-04/20260422-1649-fix-visual-cursor-target-z-order.md`
