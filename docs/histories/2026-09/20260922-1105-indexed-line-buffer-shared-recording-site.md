## [2026-09-22 11:05] | Task: Give both tree renderers one shared index-recording site

### 🤖 Execution Context
* **Agent ID**: `claude-code (controller, no delegation)`
* **Base Model**: `claude-opus-5`
* **Runtime**: `Claude Code, macOS 14+, swift build + swift test`

### 📥 User Query
> Do the appendIndexedLine helper now, and docs in english only.

Follow-up to PR #12, which added a renderer-driven test for the `treeLineOffsets`
invariant but covered only the fixture renderer, leaving the live-AX path unguarded.

### 🛠 Changes Overview
**Scope:** `packages/OpenComputerUseKit`

**Key Actions:**
- **[New type]**: `IndexedLineBuffer` owns `lines` and `offsets` as `private(set)` state and
  exposes two appends. `appendIndexedLine(index:_:)` appends a row and registers its offset in
  the same call; `appendSpanLine(_:)` appends a row that owns no index and belongs to the element
  above it. The pair `lines.append(...)` / `lineOffsets[index] = lines.count - 1` now exists in
  exactly one place, inside `appendIndexedLine`, instead of once per renderer — so no call site
  has a gap between the two statements for a later edit to insert a row into.
- **[Both call sites converted]**: `SnapshotBuilder.buildFixtureSnapshot` and the live-AX
  `TreeRenderer` now append through this one buffer. `TreeRenderer` replaced its own `lines` and
  `lineOffsets` fields with a `buffer`, and the two `AppSnapshot` construction sites read
  `buffer.lines` / `buffer.offsets`.
- **[Span rows made explicit]**: the table-row continuation rows, which previously appended
  straight into `lines`, now call `appendSpanLine`, so "this row intentionally registers no
  offset" is stated in the code rather than inferred from the absence of a line.
- **[New test]**: `testSpanRowsDoNotShiftTheOffsetsOfTheIndexedRowsAroundThem` drives the buffer
  directly with a span row landing between two indexed rows. Both renderers share this
  implementation, so the live-AX renderer's recording *rule* is now tested; its *call sites* are
  not. Review confirmed the limit empirically: making the table-row loop register an offset, or
  making the primary row stop registering one, both leave the full suite green. Covering those
  needs a seam that lets a test drive `TreeRenderer` without a real `AXUIElement`, which this
  change does not add.
- **[Mutation verified]**: changing the registration to `lines.count` fails the new test with
  `[2: 5, 0: 1, 1: 4]` against `[0: 0, 1: 3, 2: 4]`. Reverted from a scratchpad copy, then the
  full suite: 241 executed, 0 failures, 2 skipped (240 before this change).

### 🧠 Design Intent (Why)
The compact view's entire value rests on one promise: the number leading a compact row is the
element's full-tree index, never a renumbering. Enforcing that promise with two adjacent statements
means every renderer has to re-implement it correctly, and a reviewer has to notice a row appended
between them. Making it one call removes the failure mode instead of testing for it.

Driving `TreeRenderer` end to end was not an option: it needs a real `AXUIElement` and
Accessibility authorization, and no fake exists in this repo. Sharing the implementation is what
brings any part of the live path under test, since the tested buffer is literally the code it runs
— but only the part inside the buffer. Which method each call site picks stays untested.

**Known inconsistency, behavior preserved, not introduced here:** `renderSyntheticText` consumes an
index, prints that index at the head of its row, and creates an `ElementRecord` for it, but has
never registered an offset. It is now an explicit `appendSpanLine` with a comment. Registering one
would terminate the parent element's span, and since synthetic text is never ordered into compact
on its own, its text would disappear from the compact view; folding it into the parent keeps it,
at the cost of a stray index number appearing mid-row. Note that
`testCompactViewHoistsFocusedElementAndIgnoresItsSyntheticTwin` hand-authors offsets for a
synthetic index, so it models an arrangement the renderer does not actually produce. That test
still passes and still tests what it was written to test (focused-element hoisting); the divergence
is recorded here rather than resolved, because deciding it is a compact-view behavior question, not
a refactor.

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/histories/2026-09/20260922-1105-indexed-line-buffer-shared-recording-site.md`
