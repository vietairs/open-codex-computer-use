## [2026-10-15 14:45] | Task: Skip the per-step read-back settle in perform_actions

### 🤖 Execution Context
* **Agent ID**: `hvn-implementer`
* **Base Model**: `Claude Sonnet 5.5`
* **Runtime**: `local macOS repository workspace`

### 📥 User Query
> Port the upstream idea of not paying the action read-back cost for actions whose result is discarded, adapted to the fork's `perform_actions`.

### 🛠 Changes Overview
**Scope:** `OpenComputerUseKit` (`ComputerUseService`) and its tests.

**Key Actions:**
- **Per-step settle removed**: A batch step already returned an empty result (no snapshot), but each action still slept 0.1 to 0.15 s inside its body "for the read-back", and the batch slept 0.15 s again before the next step. Those in-action waits now go through `pauseBeforeReadBack`, which does nothing for a batch step (`readBackSettleInterval` returns 0). Single tool calls keep every wait unchanged.
- **One wait before the final state**: `performActions` sleeps one settle interval after the last step and before the lock check and final state read, so the last action still gets a redraw window. The between-step wait is unchanged.
- **Final state unchanged**: the batch still ends with one `finishAction` that refreshes the snapshot (so element indices are renumbered exactly as before) and returns the final state.
- **Test**: `testBatchStepSkipsTheReadBackSettleAndSingleActionKeepsIt` pins that a batch step waits 0 s while a single action keeps its 0.1 s and 0.15 s waits.

### 🧠 Design Intent (Why)
A batch of n steps paid up to 2n-1 settle waits although nothing is observed between steps. It now pays n: n-1 between steps plus one before the final read.

The list-selection wait inside the AX click path (`selectContainingListItem`) is left as is: it is a selection settle rather than a read-back wait, and a batch step still has the between-step wait after it.

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/BatchActionRunnerTests.swift`
