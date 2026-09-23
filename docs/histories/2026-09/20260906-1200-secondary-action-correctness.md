## [2026-09-06 12:00] | Task: Fix secondary action mapping

### 📥 User Query
> Extract the macOS secondary-action correctness change on its own, support Safari's custom action description, and fix the raw/display action mismatch after filtering.

### 🛠 Changes Overview
**Scope:** OpenComputerUseKit macOS accessibility snapshot and action execution

**Key Actions:**
- **Action rendering**: Parses the AppKit `Name:...` action descriptor and outputs a meaningful short name.
- **Name collisions**: When short names collide, shows the raw descriptor, guaranteeing every output selector maps uniquely back to its action.
- **Action execution**: Kept exact-match compatibility for raw AX actions; short-name matching now uses the same role-filtered raw actions set, and rejects ambiguous short names.
- **Regression tests**: Cover Safari close-tab, filter alignment, invalid descriptors, and ambiguous names.

### 🧠 Design Intent (Why)
*Rendering and execution must share the same filtering and naming semantics, otherwise the compacted action array will get misaligned with the raw action index and execute the wrong action.*

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/ARCHITECTURE.md`
- `docs/releases/feature-release-notes.md`

### PR #62 review follow-up

- The user asked for the fix commit to be added directly on the PR branch.
- Synced the latest main, resolved the feature release note conflict, and kept both the app-name resolution and secondary-action entries.
- Added conflict detection between short names and other raw AX actions, including actions filtered out by the renderer, with the comparison rule matching the executor's case-insensitive exact lookup. On conflict, outputs the full descriptor, keeping explicit raw-action invocation compatibility.
- Regression tests cover a hidden `AXPress`, a visible `AXRaise`, case differences, both action orderings, and the execution mapping for every output selector.
- Validation: the new regression test failed before the fix and passed after; `swift test` ran 161 tests, 0 failures, 1 Chrome live test skipped by default config; `make check-docs` and `git diff --check` both passed. No live Safari verification was performed.
