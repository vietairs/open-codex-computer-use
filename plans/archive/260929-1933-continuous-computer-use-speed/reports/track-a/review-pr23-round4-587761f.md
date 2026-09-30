# Review: PR #23 round 4, commit 587761f

Scope: `git show 587761f`, 5 files, +265/-5. `ComputerUseService.swift`, `Errors.swift`, new `WindowElementClickRefusalTests.swift`, `docs/RELIABILITY.md`, history note.
Verification: `swift test --filter WindowElementClickRefusalTests` at 587761f passed, 9/9. I read the click, finishAction, performActions, performAXClickSequence, descendant-candidate and localFrame code paths. I did not run a live check.

Verdict: **Request changes**. Critical 0, Important 2, Suggestion 4.

## Checked and OK

- **Refusal placement, single click.** It runs right after `lookupElement` and before `clickPoint`, `moveVisualCursor` and any press or post. It does not touch `app_post`, `sky_click`, `global` or x/y. The fixture branch does not apply it, which is fine because that path is test-only.
- **Refusal placement, batch.** `performBatchStep` calls `click(...)`, so the refusal runs at the same point for each step. Nothing is pressed for the refused step. See I1 for what already ran before it.
- **Error rewrite is narrow.**
  - It lives only in `finishAction`, which every call site reaches only after the input was delivered (click, secondary action, scroll, drag, type_text, press_key, set_value).
  - The pre-action `currentSnapshot`/`refreshSnapshot` (`ComputerUseService.swift:1442`) and get_app_state (`:663`, `:691`) are unchanged.
  - The match is exact: `case .stateUnavailable` plus the `-10005` prefix. A `.message` carrying the same text passes through, and a test covers that.
  - The fixture `Raise` secondary action reaches finishAction without input, but that path is fixture-only, so it is not a concern.
  - The perform_actions final-state wording is the known gap and is not raised again.
- **Visible pressable controls are kept.** Candidates that are actionable, framed inside the target and not labelled as a close button pass through in their original order, and a test covers this. Candidates with no frame are kept. That is correct, because dropping them would regress targets whose children do not report a frame.
- **No focus or raise writes were added**, so the BackgroundOperationInvariant surface is unchanged.

## Important

### I1. A perform_actions window refusal fires mid-batch, which breaks the batch's own "no half-applied batch" rule
`ComputerUseService.swift:1225` says: "Validate every step before any of them runs, so a bad step never leaves a half-applied batch." The pre-validation loop checks click_method, sky_click arguments and unknown indices, but not the window refusal. So `[type_text "foo", click <window idx>]` types "foo" and only then refuses step 2 (`BatchActionRunner.run` stops at the first failure).

The refusal depends only on `record.role` in the pinned snapshot and the step's `clickMethod`, both known before any step runs, so it belongs in the pre-validation loop. Suggested fix:
```swift
if let elementIndex, let record = pinned.elements[elementIndex],
   let refusal = windowElementClickRefusal(role: record.role, method: clickMethod, elementIndex: elementIndex) {
    throw ComputerUseError.invalidArguments("step \(offset + 1): \(refusal)")
}
```
Move the unknown-index check first, or fold it in. Keep the per-step check in `click` as defense in depth. Also correct the history note's claim that single clicks and `perform_actions` steps "share that path": they do, but only per step, not up front.

This still fails closed and nothing wrong is pressed, which is why it is Important and not Critical. It does break a documented invariant, and the fix is about five lines.

### I2. The frame filter compares a cached target frame with live candidate frames, so it can drop every legitimate descendant after a move or scroll
In `descendantClickCandidates(for:snapshot:)`, `targetFrame: record.localFrame` comes from the cached snapshot. The candidate frames come from `localFrame(of: child, windowBounds: snapshot.windowBounds)`, which is the live global position minus the cached window origin.

For a single `click` (no pinned snapshot), `actionSnapshot` returns the cached `snapshotsByApp` entry. If the window moved, or the target's scroll container scrolled, between get_app_state and the click, every live child frame shifts by that delta while the target frame stays stale. Once the delta exceeds the target's size, `!frame.intersects(targetFrame)` drops every framed descendant. A 24-pt-tall row that scrolls 30 pt is enough.

- **Before this commit:** the AX press reached the right child no matter where it was, because AX presses are position-independent.
- **Now:** the filter drops those children. `auto` then falls through to `performNonAXClickFallback` at the stale target point, which can post a click on whatever now sits there. `accessibility` fails.

That turns a correct background press into a possible misclick, against the fail-closed rule. Batch steps are less exposed, because `liveGeometrySnapshot` refreshes the target frame.

Fix: read the target frame live in the same space as the children, falling back to the cached one:
```swift
targetFrame: record.element.flatMap { localFrame(of: $0, windowBounds: snapshot.windowBounds) } ?? record.localFrame
```
Add a pure test with the target frame offset by more than its own size from its children. The same test should cover the hit-record path, which already passes a live `hitRecord.localFrame`, so that path is fine.

## Suggestions

- **S1. Tab-close matching is English-only by description.** `"Close tab"` is a localized AX description. `_closeButton` is an identifier and survives other locales, but only if that app actually sets it. The Mail live proof covers en-US only. With the window refusal in place, this filter now matters mainly for non-window container targets and hit-record scans, so the exposure is small. Note it in the history note as a known limit, rather than widening the matching heuristically.
- **S2. Docs are slightly narrower than the code.**
  - `isTabCloseButton` matches `_closeButton` as a substring and `Close tab` exactly, in any of title, description, help, value or identifier. It also matches subrole `AXCloseButton`, which the title-bar filter already drops, so that check is redundant.
  - RELIABILITY.md says "identifier `_closeButton` or description `Close tab`". Either reword it to "a label containing `_closeButton` or equal to `Close tab`", or narrow the code to identifier and description only. I prefer narrowing the code, which also cuts two AX reads per actionable candidate. Label reads are currently five per actionable candidate, repeated later by `isLikelySyntheticSideAction`.
- **S3. The wiring is not tested; only the pure predicates are.** No test proves that the refusal runs before `moveVisualCursor` or the press, or that `finishAction` wraps the refresh error. This matches the repo's pure-function test style, and the live check at 587761f covered the single-click path. If I1 is fixed, add a pure test for the batch pre-validation, since that is reachable without AX.
- **S4. `isTabCloseButton` treats `AXCloseButton` as a tab close button.** Naming only: drop that branch (the title-bar filter already owns it) or rename the function to `isCloseButton`.

## Not re-raised (accepted)
cascadeGuide truncation, x/y descendant fallback, review Lows L1-L4, perform_actions final-snapshot wording.

## Unresolved questions
- Did the live Mail debug show both `AXIdentifier=_closeButton` and `AXDescription=Close tab` on the hidden button, or only one? That decides whether S1 matters in practice.
