## [2026-04-19 23:00] | Task: Add a StandaloneCursor built from the Python reconstruction script

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> We currently have a `swift run CursorMotion` version, but it feels pretty unsatisfactory. Build a new `StandaloneCursor` version based on the standalone `scripts/cursor-motion-re/reconstruct_cursor_motion.py` script and see how it looks.

### 🛠 Changes Overview
**Scope:** `Package.swift`, `experiments/StandaloneCursor/`, `README*`, `docs/`

**Key Actions:**
- **[Added a standalone target]**: Added a `StandaloneCursor` executable target, a `StandaloneCursorSupport` support module, and a corresponding test target to `Package.swift`, avoiding further changes to the currently messy `CursorMotion` code path.
- **[Swift-side reconstruction model]**: In `experiments/StandaloneCursor/Sources/StandaloneCursorSupport/StandaloneCursorModel.swift`, reconstructed the 20 candidates, `measure + score`, the selection policy, and the raw spring timeline (`response=1.4` / `dampingFraction=0.9` / `dt=1/240`) following the Python script.
- **[New standalone viewer]**: Added the `StandaloneCursor` app, which supports dragging the start/end points, switching candidates, replaying the path, and displays endpoint-lock / close-enough timing directly in the UI.
- **[Verification and docs]**: Added `StandaloneCursorSupportTests`, and filled in `experiments/StandaloneCursor/README.md`, the top-level README, `docs/ARCHITECTURE.md`, and the exec plan.

### 🧠 Design Intent (Why)
The existing `CursorMotion` leans more toward visual and interaction experimentation, and isn't well suited to continue carrying the goal of "directly cross-checking against the binary lift via the Python script." Making the new viewer a standalone target preserves the experimental freedom of the old lab on one hand, while providing a cleaner intermediate layer for further cross-checking scripts and eventual convergence back into the main runtime on the other.

### 📁 Files Modified
- `Package.swift`
- `experiments/StandaloneCursor/README.md`
- `experiments/StandaloneCursor/Sources/StandaloneCursor/StandaloneCursorApp.swift`
- `experiments/StandaloneCursor/Sources/StandaloneCursor/StandaloneCursorRootView.swift`
- `experiments/StandaloneCursor/Sources/StandaloneCursorSupport/StandaloneCursorModel.swift`
- `experiments/StandaloneCursor/Tests/StandaloneCursorSupportTests/StandaloneCursorSupportTests.swift`
- `README.md`
- `README.zh-CN.md`
- `docs/ARCHITECTURE.md`
- `docs/exec-plans/completed/20260419-standalone-cursor-from-python-reconstruction.md`
