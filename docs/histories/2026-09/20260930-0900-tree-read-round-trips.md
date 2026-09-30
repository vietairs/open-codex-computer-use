## [2026-09-30 09:00] | Task: cut the accessibility round trips of a snapshot build

### 🤖 Execution Context
* **Agent ID**: fullstack-developer
* **Base Model**: Claude Opus 5.5 (claude-opus-5-5)
* **Runtime**: Claude Code, worktree `feat/continuous-computer-use-speed`

### 📥 User Query
> Every action call costs about as much as `get_app_state` on Mail (~1.8 s), because the post-action snapshot walks
> the whole accessibility tree. Remove repeated tree reads without changing the rendered text or `element_index`
> numbering, with no caching across calls and no focus changes.

### 🛠 Changes Overview
**Scope:** `packages/OpenComputerUseKit` (Sources + Tests), `docs/ARCHITECTURE.md`.

**Key Actions:**
- **Where the time went**: a CPU sample of 20 back-to-back `get_app_state` calls on Mail showed the snapshot thread
  blocked in `mach_msg` for 96% of its samples, waiting on single-attribute reads served by Mail's main thread. 71% sat
  under message-row text flattening (role, children and value read one at a time for every node below each row's
  cells) and 20% under the visible-row filter (position and size read separately for every row of the table).
- **Batched reads**: row-text flattening and generic text summaries read role, value, title and children of each node
  in one multi-attribute round trip. The render batch also carries the title, role description, placeholder and child
  lists, and the known role is passed on instead of being read again (child listing, Apple-menu filter, URL and value
  segments, web-area depth).
- **Visible rows**: each row's frame is one round trip, and the scan stops once the first 20 visible rows are found.
  The kept rows are the same: they were always the first 20 visible rows in row order.
- **Read seam**: the tree walk's accessibility calls go through `AccessibilityReadBackend` (live in production). Tests
  bind an in-memory tree for one closure and count calls per node.

### 🧠 Design Intent (Why)
The cost is round trips to the target app, not work in this process, so the change reduces their number. Every
value is still read during the build that uses it; nothing survives to the next call. A golden test pins the rendered
lines and element records of a Mail-like tree captured before the change, and the same tree rendered with batched
reads and with single reads must match. On that tree the walk went from 1836 to 468 round trips.

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilityReadBackend.swift` (new)
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilityAttributePrefetch.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/FakeAccessibilityTree.swift` (new)
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/TreeRenderReadCostTests.swift` (new)
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/AXAttributePrefetchTests.swift`
- `docs/ARCHITECTURE.md`
