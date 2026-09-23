## [2026-09-22 01:24] | Task: Add a compact actionable view to get_app_state

### 🤖 Execution Context
* **Agent ID**: `claude-code (cortex pipeline, --auto --counsel)`
* **Base Model**: `claude-opus-5`
* **Runtime**: `Claude Code, macOS 27.2`

### 📥 User Query
> Research adapting `open-computer-use` using the classifier approach from openjev / browser-use jev-ultrafast, and after approval, execute through to a mergeable state. After proposal review, Phase 1 (P0) was determined to be "a zero-ML, trimmed, actionable candidate table."

### 🛠 Changes Overview
**Scope:** `packages/OpenComputerUseKit`

**Key Actions:**
- **Added a compact view**: `SnapshotTextStyle` gained `compactActionable`, which renders only elements that expose an accessibility action, flattens indentation, and prioritizes the focused element.
- **Index stability**: Added `treeLineOffsets` (element index → its line position in `treeLines`); the compact view directly reuses the line already rendered by the full tree, so `element_index` stays fully consistent with the full tree, and action tools need no changes at all.
- **Omit the screenshot**: `snapshotResult` does not attach a PNG in compact mode, otherwise the token-saving purpose would be canceled out by the screenshot.
- **Tool contract**: `get_app_state` gained an optional `compact` boolean parameter; the dispatcher gained a fault-tolerant `optionalBool` (accepting bool / "true" / "false" / 1 / 0).
- **Tests**: Added 5 unit tests covering filtering, index preservation, indentation flattening, the explicit message when there are no actionable elements, and that full-tree behavior is unchanged.

### 🧠 Design Intent (Why)
This is P0 of the local decision-model proposal, and also its prerequisite: trimming a 1200-node AX tree down to actionable candidates is where the difficulty lies for subsequent constrained-choice read-out. Making it a standalone feature that doesn't depend on any model lets us capture the token and latency benefit first, and lets us verify whether the trimming itself drops correct targets, without introducing a sidecar, weight downloads, a hardware bar, or a change in trust boundary.

Deliberately **not** deduplicating same-named rows: two "Delete" buttons in a list are different targets — dropping the correct target is far worse than printing one extra near-duplicate row.

### 🔁 Fixes after code review

An opus-tier code review found four issues, all fixed and covered with tests (test count 228 → 233):

- **Nondeterministic focused-element lookup**: an `AXUIElement` can correspond to both a real row and a synthetic-text row generated for it, and `Dictionary.values` is unordered, so the same UI element could match a synthetic row with no action — one that doesn't enter the compact view — on different runs, causing the focused element to be neither promoted nor marked. Fixed by skipping synthetic records and taking the minimum matching index.
- **Actionability check too narrow**: `set_value` only requires `AXValue` to be writable, not any action, so filtering by `rawActions` alone would drop the very text field the agent actually needs to type into; in fixture mode, `rawActions` stores secondary actions while dispatch happens by identifier, causing the same misjudgment. Fixed by relaxing the check to also account for role (text-input types) and fixture identifiers.
- **Sort predicate did not satisfy strict weak ordering**: returned `true` when both sides equal `focusedIndex`. Currently unreachable, but changed to a partition-based construction to avoid triggering a standard-library trap later.
- **`optionalBool` silently swallowed invalid values**: `compact: "yes"` would silently return the full tree plus screenshot — i.e., the most expensive answer to the "cheapest" request. Fixed to throw `invalidArguments`, consistent with the other parsers in the same file.

### ⚠️ Known Gaps
`compact` is currently only implemented in the macOS Swift runtime. The Linux / Windows Go runtimes each maintain their own tool schema and do not yet support this parameter. It won't be rolled out to all three runtimes until P0's benefit has been measured.

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseToolDispatcher.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ToolDefinitions.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/ARCHITECTURE.md`
- `docs/exec-plans/active/20260922-local-decision-model-mcp-tool.md`
