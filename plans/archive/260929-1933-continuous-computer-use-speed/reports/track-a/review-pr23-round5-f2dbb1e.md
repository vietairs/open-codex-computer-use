# Review: PR #23 round 5, commit f2dbb1e

Scope: `git show f2dbb1e` on top of 587761f. 4 files, +115/-22: `ComputerUseService.swift`, `WindowElementClickRefusalTests.swift`, `docs/RELIABILITY.md`, the history note.
Verification: `swift test --filter WindowElementClickRefusalTests` at f2dbb1e passed 13/13 (9 before, 4 new). I read `performActions` pre-validation, `lookupElement`, `BatchActionRunner.unknownElementIndices`, `descendantClickCandidates(for:)` and its two call sites (direct and hit-record), and `localFrame(of:)`. No live check was run.

Verdict: **Approve**. Critical 0, Important 0, Suggestion 0, Nit 2.

## Prior findings

### I1 (batch pre-check): fixed
- `batchWindowClickRefusal` runs in `performActions` after the click_method/sky_click loop and the unknown-index check, and before `BatchActionRunner.run`. So `[type_text, click <window>]` now throws before step 1 runs.
- Ordering is correct. An unknown index is reported first, which keeps that message. By the time the refusal runs, every index is known to parse and to exist, so a nil role from `roleForIndex` cannot hide a real window.
- Index parsing matches `lookupElement` (`Int(index)` then `snapshot.elements[...]`) and `unknownElementIndices`, and it uses the same pinned snapshot, so it sees the same record role that the per-step check sees.
- The per-step check in `click` (`:881`) remains as a backstop, as the history note says.
- Explicit methods are still allowed. `windowElementClickRefusal` gates on `.auto || .accessibility`, and `testBatchAllowsControlClicksAndExplicitPostingOnWindows` covers `app_post` on a window, an x/y click (the `elementIndex?` pattern skips it) and a non-window control.
- Message format `step N: element K is the window itself...` matches the other pre-validation errors.

### I2 (live target frame): fixed
- The target frame is now `localFrame(of: record.element, windowBounds: snapshot.windowBounds) ?? record.localFrame`. That is the same function and the same cached window origin used for candidate frames, so both sides of `intersects` share one coordinate space.
- Cost: 2 AX reads (position and size) per `descendantClickCandidates(for:)` call, which is negligible next to the child walk.
- Nil handling: a failed read falls back to the cached frame. If both are nil, the frame check is skipped and candidates are kept, the same as before.
- The hit-record path (`:1720`) goes through the same function, so it also gets the live frame read from `hitRecord.element`. That is consistent with the rest, and it is a no-op when the hit record is already live.
- `testFrameFilterUsesTheTargetFrameItIsGiven` proves that the pure filter respects whichever frame it is given (stale drops, live keeps). It does not prove the wiring, which is the accepted S3 style.

### S2 (docs vs matching): fixed, by narrowing the code
- `isTabCloseButton(identifier:description:)` now matches an identifier containing `_closeButton` (case-insensitive) or a description equal to `Close tab`. RELIABILITY.md and the history note say exactly that.
- Mail's hidden button (identifier `_closeButton`) still matches through the identifier branch, and `testTabCloseButtonsAreExcludedByIdentifierAndDescription` plus `x_closeButton` in the new test cover it.
- Title, help and value are no longer read. Label reads per actionable candidate drop from 5 to 2.

### S4 (redundant AXCloseButton): fixed
- The subrole branch is gone. Title-bar `AXCloseButton` is still dropped by `excludingWindowTitleBarButtons`, which runs first on the same list.

### S1 (English-only description): documented
- The history note states that the description match is English-only and that the identifier match is locale-independent. Accepted.

## New regressions
None found.
- The closure signature change (`labels:` to `closeButtonLabels:`) is internal. The only production caller and all tests were updated, and the package builds.
- `accessibilityLabels` is still used by `isLikelySyntheticSideAction`, so it is not dead.
- A target whose live frame reads as zero-size would make `intersects` behave the same as it did with a zero-size cached frame before. This is unchanged behaviour, so it is not raised.

## Nits (non-blocking)
- N1. The test name `testTitleBarCloseSubroleIsNotATabCloseButton` refers to a subrole, but the function no longer takes one. The test actually checks that a `Close` description is not treated as a tab close. A name such as `testPlainCloseDescriptionIsNotATabCloseButton` would say what it checks.
- N2. The history note's new sentence on window refusal is one unwrapped line, while the surrounding bullets wrap at about 120 columns. Cosmetic only.

## Not re-raised (accepted)
cascadeGuide truncation, x/y descendant fallback, review Lows L1-L4, perform_actions final-snapshot wording, S3 wiring tests.

## Unresolved questions
None.
