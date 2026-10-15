## [2026-10-15 14:45] | Task: Skip unused read-back waits in perform_actions

### 🤖 Execution Context
* **Agent ID**: `hvn-implementer`
* **Base Model**: `Claude Sonnet 5.5`
* **Runtime**: `local macOS repository workspace`

### 📥 User Query
> Port the upstream idea of not paying the action read-back cost for actions whose result is discarded, adapted to the fork's `perform_actions`.

### 🛠 Changes Overview
**Scope:** `OpenComputerUseKit` (`ComputerUseService`) and its tests.

**Key Actions:**
- **Which waits go**: A batch step returns an empty result (no snapshot), so a wait that exists only to let the app redraw before a read-back is pure cost. In the code that is the 0.15 s wait of the fixture-app `scroll` and `press_key` paths. Those now go through `pauseBeforeReadBack`, which does nothing for a batch step. Real `press_key`, `scroll` and non-accessibility clicks never had such a wait.
- **Which waits stay**: Steps that write through accessibility keep their own settle inside a batch, exactly as before: accessibility clicks (the 0.15 s after a successful AX click, including an x/y click that resolves to an AX element), `perform_secondary_action` (0.15 s), `set_value` (0.1 s) and `type_text` when it writes the field value through accessibility (0.1 s), plus the fixture-app `click`, `type_text` and `set_value` equivalents. The 0.15 s wait between steps is unchanged. The wait inside `selectContainingListItem` and the 0.05 s waits in AX scrolling are unchanged too.
- **One wait before the final state**: `performActions` sleeps one settle interval (0.15 s) after the last step, before the lock check and the final state read, so the last action always gets a redraw window.
- **Final state unchanged**: the batch still ends with one `finishAction` that refreshes the snapshot (element indices are renumbered exactly as before) and returns the final state. Single tool calls keep every wait unchanged.
- **Injectable sleep**: `ComputerUseService` takes a sleep handler (same shape as the dispatcher's `sleepHandler`) used by every settle wait of an action or batch, so tests record the schedule instead of sleeping.
- **Tests**: `BatchActionRunnerTests` runs fixture-snapshot batches with a recording sleep handler. It pins that a key-press batch waits only between steps plus once before the final read (a one-step batch has exactly one wait, so deleting the final wait fails), that a value-writing step keeps its own settle inside a batch, and that a single action keeps its wait.

### 🧠 Design Intent (Why)
A batch of n steps paid up to 2n-1 settle waits although nothing is observed between steps. The first version of this change also removed the in-step settle of accessibility-routed steps, which shortened the gap before the next step (AX click 0.30 s to 0.15 s, `set_value` or accessibility `type_text` 0.25 s to 0.15 s) with no live run to back it. This version keeps those waits, so the gap before the next step after such a step is unchanged.

Net effect: a batch of steps that only send input (key presses, real scrolls, non-accessibility clicks) now pays one extra 0.15 s wait before the final read compared with before, because those steps had no wait of their own and the final read had none either. Batches ending in an accessibility-routed step pay the same in-step wait as before plus the new final wait. This is slower but safer than before, and it is the cost of guaranteeing the last action a redraw window.

No live run was performed: neither the Mail batch from the usage reference nor a click-then-type batch in a web or Electron app was exercised. The behavior is covered by unit tests on the fixture path only.

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/BatchActionRunnerTests.swift`
