# H2 fix: renderer-driven treeLineOffsets invariant test

## Executed
- Worktree: `/Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/tree-line-offsets-invariant-test` (branch `fix/tree-line-offsets-invariant-test`)
- Status: completed

## Files modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift` — `buildFixtureSnapshot` dropped `private` → module-internal (1 line changed, matches the pre-approved approach; no behavior change).
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift` — added `testTreeLineOffsetsMatchEveryElementRowFromARealRenderer` plus a small `stripFixtureIndent` helper (92 lines added), inserted after `testFullStateViewIsUnchangedByCompactSupport` (~line 1262).

## What the test does
Builds a `FixtureAppState` with 4 elements (title-only, value-carrying + focused, title-only static text, title + secondary actions), fed to `FixtureAppState.elements` in non-ascending index order (3, 1, 0, 2) to also exercise the renderer's internal sort. Calls the real `SnapshotBuilder.buildFixtureSnapshot(app:state:)` directly — no hand-authored `treeLineOffsets`. Asserts:
1. `treeLineOffsets.keys == {0,1,2,3}` (nothing silently unregistered).
2. For every index `i`, `treeLines[treeLineOffsets[i]!]` stripped of leading indent starts with `"\(i) "` — the core off-by-one guard.
3. End-to-end: `renderedText(style: .compactActionable)`'s element rows match exactly what's derivable from `treeLines`/`treeLineOffsets` for indices 0...3, proving the compact path consumes the same offsets correctly.

Two things surfaced only by driving the real renderer (documented in code comments so a future reader isn't puzzled): fixture snapshots carry no `AXUIElement`, so `focusedElementIndex()` (identity-based) never matches and compact falls back to ascending order instead of hoisting the focused row; the `(focused)` marker on a fixture row comes from `buildFixtureSnapshot` embedding it inline, not from a suffix `compactActionableLines` appends. The first test draft assumed focus-hoisting and a suffix (copied from the hand-authored `makeSnapshot` tests, which fake an `AXUIElement`) and failed against the real renderer; fixed by asserting the fixture-mode reality instead of the accessibility-mode behavior.

## Test counts
- Before (baseline, main): 239 tests, 0 failures, 2 skipped.
- After (this branch, full `swift test`): 240 tests, 0 failures, 2 skipped.

## Mutation test
- Mutated `lineOffsets[element.index] = lines.count - 1` → `lines.count` (off-by-one) at the offset-recording site.
- Ran only the new test: **FAILED** — 3 `XCTAssertTrue` mis-registration failures, a `XCTFail` for a missing index-3 offset, and the process crashed with `Fatal error: Index out of range` when `compactActionableLines` indexed `treeLines` with the bad offset.
- Reverted the mutation; `git diff` on the source file now shows only the intended `private` removal — confirmed via `git diff packages/.../AccessibilitySnapshot.swift`.
- Re-ran the full suite: back to 240/0/2 (green).

## Unresolved questions
None.

Status: DONE
Summary: Added one renderer-driven test proving the treeLineOffsets invariant end-to-end (fixture render → offsets → compact view); it fails hard (assertion failures + crash) on the off-by-one mutation and the suite is green at 240/0/2 with the mutation reverted.
