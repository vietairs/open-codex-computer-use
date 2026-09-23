## [2026-09-22 10:36] | Task: Backfill a renderer-driven test for the compact view's index invariant

### 🤖 Execution Context
* **Agent ID**: `cortex -> fullstack-developer`
* **Base Model**: `claude-opus-5` (controller) / `claude-sonnet-5` (implementer)
* **Runtime**: `Claude Code, macOS 14+, swift test`

### 📥 User Query
> Fix H2 from PR #10's code review: the compact snapshot's `treeLineOffsets` invariant has zero test coverage,
> add a test driven by a real renderer.

### 🛠 Changes Overview
**Scope:** `packages/OpenComputerUseKit`

**Key Actions:**
- **[New test]**: `testTreeLineOffsetsMatchEveryElementRowFromARealRenderer` builds a snapshot via
  a real fixture renderer, asserting that every element index has a registered offset, and that
  `treeLines[treeLineOffsets[i]]`, with indentation stripped, starts exactly with `"i "`; it then
  renders once more with `.compactActionable`, confirming the compact lines match the registered
  lines row for row.
- **[Visibility adjustment]**: Removed `private` from `SnapshotBuilder.buildFixtureSnapshot`, making it
  module-internal, so the test target can drive the renderer directly via the existing `@testable import`.
  This is the only production code change in this round.
- **[Ordering assertion]**: Review overturned a claim from the first draft: that feeding elements in
  shuffled order would catch a missed sort. It does not hold: line text and indentation are determined
  solely by `element.index`, and offsets are always self-consistent with each other, so the row-by-row
  prefix check passes under any emission order; separately, compact itself re-sorts ascending anyway. The
  claim only actually holds once the offset is compared directly against its ascending position.
- **[Mutation verification]**: Both mutations failed as expected — changing the recording point to
  `lines.count` (introducing an off-by-one); and removing the renderer's `.sorted(by:)`, which reported
  `[2, 1, 3, 0]` not equal to `[0, 1, 2, 3]`. After reverting, the full suite was green again, confirming
  the test is not a no-op.

### 🧠 Design Intent (Why)
The entire value of the compact view rests on one premise: the number at the start of a compact line
is the full-tree `element_index`, and it is never renumbered. All 13 prior compact tests hand-wrote
`treeLineOffsets` literals, which effectively takes this premise as input rather than as the thing
under test — introduce an off-by-one at the recording point, or insert a line between `lines.append`
and the offset registration, and the whole suite would still be fully green, which is exactly the class
of defect this feature is supposed to guard against.

The end-to-end path through `FixtureBridge.writeState` + `SnapshotBuilder.build(for:)` was not taken,
because it would only additionally cover one dispatch hop, while requiring writes to an inter-process
shared file under `NSTemporaryDirectory()`, which could interfere with a developer's currently running
fixture app; and the genuinely at-risk invariant sits entirely inside `buildFixtureSnapshot`.

**Known coverage boundary:** this test only guards the fixture renderer, so H2 counts as only partially
closed. The real-AX `TreeRenderer` has its own separate offset-recording point inside
`AccessibilitySnapshot.swift`, which requires a real `AXUIElement` and Accessibility authorization to
drive, and therefore remains uncovered — and that is exactly the path that runs on a real app. Multi-line
spans (continuation lines with no index of their own, later merged by `compactActionableLines`) are
likewise uncovered, since the fixture renderer never produces span lines. The thorough fix would be to
extract an `appendIndexedLine(index:text:)` shared by both recording points; this was deliberately not
done in this round: it would touch production live-AX code, and this repo has no PR CI safety net.

### 📁 Files Modified
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
