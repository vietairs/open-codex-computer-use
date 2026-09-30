# Review loop round 1 — `fix/tree-line-offsets-invariant-test` (PR #12, `af24c6b`)

Read-only review. No repo files edited. Mutation experiments were run on a *copy* of the package in
the session scratchpad (minimal `Package.swift` with kit + test target only), never in the worktree.

## Scope

- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift` (1 line: `private` drop)
- `packages/OpenComputerUseKitTests/OpenComputerUseKitTests.swift` (+95: 1 test + 1 helper)
- `docs/histories/2026-09/20260922-1036-h2-tree-line-offsets-invariant-test.md` (+41)

## Blockers

None. The test is genuine, not vacuous, and the production change is inert.

## Findings

### F1 (Medium, non-blocking) — the "non-ascending input catches a dropped sort" claim is false

Stated three times: test comment (`// Deliberately non-ascending: catches a regression that dropped
the renderer's sort.`), PR body ("so a regression that dropped the renderer's sort also fails"), and
the history record ("catches a regression that dropped the renderer's sort" intent).

Empirically false. In the scratchpad copy I replaced

```swift
for element in state.elements.sorted(by: { $0.index < $1.index }) {
```

with `for element in state.elements {` and re-ran:

- `swift test --filter testTreeLineOffsetsMatchEveryElementRowFromARealRenderer` → **passed**.
- Full suite on the mutated copy → 240 executed, 1 failure, and that failure is
  `testSoftwareCursorGlyphLoadsCursorMotionReferenceImage` (missing CursorMotion resource — an
  artifact of my reduced manifest, unrelated). So *nothing* in the suite guards the sort.

Why it cannot catch it: the rendered row text depends only on `element.index` (including the indent,
`count: element.index == 0 ? 0 : 1`), never on position in `lines`; `lineOffsets[element.index] =
lines.count - 1` stays self-consistent under any iteration order; and `compactActionableLines()`
emits rows in ascending index order regardless. Unsorted input therefore permutes `treeLines`
(a real, user-visible defect in `.fullState`) while every assertion in the new test still holds.

Cheapest real fix — one assertion that pins offsets to positions, catching both the off-by-one and
the sort:

```swift
XCTAssertEqual((0...3).compactMap { snapshot.treeLineOffsets[$0] }, [0, 1, 2, 3])
```

Absent that, drop the claim from the comment, PR body, and history record rather than leaving three
places asserting coverage that does not exist.

### F2 (Low) — `expectedBody` is weaker than the comment says, but not tautological

The comment claims "a broken sort or a dropped offset registration both fail this comparison".
Half right:

- broken sort: does not fail it (see F1);
- dropped registration: verified it *does* fail — mutating the recording site to skip index 2 fails
  three assertions, including the `expectedBody` comparison, because the compact span-join then
  folds index 2's row into index 1's (`"1 AXTextField … — 2 AXStaticText Status …"`), which
  `expectedBody` does not contain.

On the tautology question you flagged: `expectedBody` is derived from `treeLineOffsets` +
`treeLines`, i.e. the same data `compactActionableLines()` reads, so it *cannot* detect a wrong
offset — a uniformly shifted offset moves both sides together. The assertion that actually carries
the off-by-one guarantee (and that made your `lines.count` mutation fail) is the
`line.hasPrefix("\(index) ")` loop. `expectedBody` still earns its place: it pins compact ordering,
the span-join, and the absence of a spurious `(focused)` suffix. Worth correcting the comment so a
future reader does not over-trust it.

### F3 (Low) — `.prefix(4)` hides over-inclusion

Slicing to exactly 4 rows means a regression that adds a *fifth* compact row (e.g. a filter change
letting a synthetic row through) is invisible. Comparing the full body to `expectedBody` without
`prefix` would need the trailing `""` + focused-summary lines handled; `prefix(expectedBody.count + 1)`
or asserting the row count separately would close it. Minor.

## Verified as claimed

- **Fixture mode keeps all four elements**: `isActionableForCompactView` returns `true` unconditionally
  for `mode == .fixture`, and `buildFixtureSnapshot` builds `ElementRecord`s with the default
  `isSyntheticText: false`, so the `isSyntheticText` early-out never fires. All four survive.
- **The `(focused)` marker reasoning in the test comment is correct**: fixture records carry
  `element: nil`, so `focusedElementIndex()` returns `nil` (guard on `focusedElement`), compact
  appends no suffix, and the marker in the row comes from `buildFixtureSnapshot`'s `focusSegment`.
- **PR "known coverage limit" framing is honest**: the live-AX path really does have a second,
  independent recording site (`renderer.lineOffsets` fed into `AppSnapshot` at
  `AccessibilitySnapshot.swift:420`) that this test does not touch. "Partially closed" is accurate.
- **Visibility drop is inert** — I agree with your judgement not to run separate security /
  breaking-change passes. `enum SnapshotBuilder` is already module-internal and unexported;
  `private` → internal widens reachability only inside `OpenComputerUseKit`, and
  `buildFixtureSnapshot` has exactly one new caller (the test). Nothing crosses the module boundary,
  no public API moves. `@testable import` does not reach `private`, so the drop was necessary rather
  than convenience.
- **Brittleness**: acceptable. The test asserts a row *prefix* and compares compact output against
  rows taken from the same snapshot, so it does not hard-code frame/format strings; a legitimate
  change to row formatting moves both sides. `stripFixtureIndent` duplicates the production
  `stripLeadingIndent` rather than calling it — fine, and it means a break in the production stripper
  would surface as a mismatch rather than being masked.

## History record vs `docs/HISTORY_GUIDE.md`

Compliant: path `docs/histories/2026-09/`, filename `20260922-1036-task-slug.md`, all template
sections present, user query compressed, no local paths, no secrets, no raw logs. One content issue
only — it repeats the false sort claim from F1. `📁 Files Modified` omits the history file itself,
which matches the existing records in that directory.

## Unresolved questions

1. Fix F1 by adding the offset-position assertion (guards the sort for real), or by deleting the
   claim from three places? Adding it is one line and strictly more coverage.
2. Does the sort in `buildFixtureSnapshot` matter enough to guard, given fixtures are
   developer-authored? It affects `.fullState` row order, which agents read.
