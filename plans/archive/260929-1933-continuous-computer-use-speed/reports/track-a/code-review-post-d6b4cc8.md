# Code review: d6b4cc8..3e306ce (feat/continuous-computer-use-speed)

VERDICT: PASS (0 Critical, 0 High; 2 Medium, 4 Low, 3 Info)

## Scope
- Worktree: `.claude/worktrees/continuous-computer-use-speed`, 9 commits (5a9fe38, 7623262, 2eccb18, d7a1cce, a713b8c, f3cd53a, 3bed7f3, e35897f, 3e306ce)
- 33 files, +2620/-239. Source: AccessibilitySnapshot, ComputerUseService, new BackgroundFocusResolution / ClickTextEntryFocus / TypeTextDelivery / StageManagerOffStageWindow / AccessibilityReadBackend, MCPServer, ToolDefinitions, dispatcher, AppDiscovery, Errors
- Verification: full `swift test` run with a scratch path outside the worktree: 586 tests, 0 failures, 2 skipped (live-AX skips). The worktree was not modified.

## Pass 1: critical checks (all clear)
- **Focus stealing:** removed recovery activate / `open -b` / AXRaise / unminimize / AXMain (5a9fe38). Launch sets `activates = false`. type_text no longer activates (7623262). The only remaining `.activate(` is the gated global-pointer path (InputSimulation.swift:55). BackgroundOperationInvariantTests pins this. The click focus write (ComputerUseService.swift:873) is an AXFocused write only.
- **Fail-open coordinates:** every pointer-event sink (performScrollEvent :2379, performDragEvent, performNonAXClickFallback :2430, performExplicitMouseClick) and the x/y click and drag entries call `rejectCoordinateInputWhenOffStage`. If a window goes off stage after an on-stage snapshot, the live bounds become the thumbnail size, so the existing stale-frame check still fails closed.
- **Render drift in 3e306ce:** walked every changed read:
  - `webAreaAncestorPosition` keeps the outermost web area. All three recursive `render(` sites pass it.
  - `visibleRows` early break returns the same first 20 visible rows in the same order. `outlineRowSummary` counts are unchanged.
  - `formattedValueSegment` / `formattedURLSegment` use the role already read. On a role-read failure this compares "AXUnknown" instead of nil, which gives the same result for the StaticText and WebArea checks.
  - `shouldSkipChild` uses the parent role from the prefetch, which has the same nil semantics as before.
  - The golden, batched-vs-single, and round-trip pins pass. No drift found.
- **Thread safety:** `@TaskLocal` backend defaults to `.live`. There is no global mutation, and nothing is cached across builds.
- **Crashes:** the only force casts in the touched code are `as! AXValue` in resolveLocalFrame (pre-existing, guarded by the sentinel drop in the prefetch). No new unguarded subscripts: `pool[0]` is guarded because `usable` is non-empty, and `hintedPosition` comes from `firstIndex`.

## Medium

### M1. type_text "fail closed on a non-text focus" branch is unreachable; a refused write on any settable-value focus posts keys
- **Where:**
  - TypeTextDelivery.swift:49-58 (`.setFocusedValue` branch: `guard focus?.acceptsKeyboardText == true`)
  - ComputerUseService.swift:527-530 (`canUseKeyboardTextFallback` returns true whenever `isValueSettable`)
  - `typeTextFocus` builds `acceptsKeyboardText` from that function
- **Why the branch is dead:** `TypeTextFocus(isValueSettable: true, acceptsKeyboardText: false)` never occurs in production. TypeTextDeliveryTests.swift:67 (`testRefusedValueWriteOnNonTextElementFailsClosed`) tests only that impossible state, so it proves nothing about production behavior.
- **Failure scenario:**
  1. d7a1cce's background focus fallback makes the snapshot focus the deepest AXFocused non-container. It can be a settable-value non-text control (slider, stepper, some custom list/table controls).
  2. type_text calls setValue, which writes `baseValue + text` into that control.
  3. If the write is refused, keys are posted to the pid, reaching whatever the first responder is. For example, type-select in a list moves the selection.
  4. Before this range, this state went to the (removed) activation path.
- **Why it matters:** docs/RELIABILITY.md:55 ("posts keys only when a text control holds focus") and usage.md:112 ("fails instead of typing into whatever else has focus") overstate the guarantee.
- **Fix:** compute `acceptsKeyboardText` from role / roleDescription only, for example by calling `canUseKeyboardTextFallback(role:roleDescription:isValueSettable: false)` inside `typeTextFocus`. Then decide whether the setValue route should also require a text-entry role (`backgroundFocusTextEntryRoles` plus the "text field"/"text area" role descriptions). Add a test that goes through `typeTextFocus` inputs, not a hand-built `TypeTextFocus`.

### M2. With decide_next_action enabled, the cascade guide is still cut at the 2048-char host limit
- **Where:** MCPServer.swift:29 (`base + "\n\n" + DecisionAdvisor.cascadeGuide`) and DecisionAdvisor.swift:55-61
- **What happens:** the base text is 1899 chars (measured), so only about 147 chars of the ~620-char guide stay visible: the first sentence. The safety bullets are lost: follow only when margin >= recommended_min_margin and the action is non-destructive, and never paste screen text into goal.
- **Mitigation / regression status:** `resultNote` still carries the margin rule in every result. This is not a regression: before 3bed7f3 the whole guide was cut. The commit's claim that instructions fit the host limit holds only for the base text.
- **Test gap:** ServerInstructionsGuidanceTests checks only the base text.
- **Fix:** either shorten base + guide to fit 2048 together, or move the guide's safety bullets into the `decide_next_action` tool description. Add a test that asserts `computerUseServerInstructions(environment: <advisory enabled>).count <= 2048`, or at least that the margin rule falls inside the visible prefix.

## Low

### L1. Skipping `AXModal == false` windows lets x/y clicks land on a window absent from the screenshot (e35897f)
- **Where:** AccessibilitySnapshot.swift:847 (`covering = pool[..<hintedPosition].first { !isNonModal }`), :864
- **Failure scenario:**
  1. A layer-0 window of 20,000 px² or more that reports `AXModal == false` sits in front of the AX root and overlaps it. The field-verified case is Mail's search suggestions.
  2. The capture is `desktopIndependentWindow` (the AX root only), so the screenshot shows the content under that window.
  3. The agent picks x/y in the overlapped area. The pid-posted events hit-test to the front window, so the click lands on the suggestion list instead of what the screenshot shows.
- **Why Low:** before this commit, the covering window replaced the whole snapshot (a tree/screenshot mismatch plus a stale-frame refusal), which is worse for the common case. Floating panels (layer > 0) were never considered anyway.
- **Fix (optional):** record skipped overlapping window frames on the snapshot and refuse x/y points inside them, or add a note line naming the uncaptured overlapping window.

### L2. element_index click or scroll on an off-stage window can fail with an "x/y coordinates" message and skip the text-field focus write
- **Where:** ComputerUseService.swift:822-841 (auto click falls through to `performNonAXClickFallback`) and :2430 / :2379 (reject)
- **Failure scenario:**
  1. The window is off stage and a text field has no AXPress, so no descendant or activation candidate handles the click.
  2. The pointer fallback throws `offStageCoordinateInputMessage`, which says "x/y coordinates cannot target this window ... Use element_index actions instead", although the caller already used element_index.
  3. The throw happens before `focusTextEntryAfterClick` (:873), so the AXFocused write that would have worked never runs.
- **Safety:** fail-closed, but it contradicts the off-stage note ("element_index actions still work").
- **Fix:** when `snapshot.isOffStage` and the call used element_index, skip the pointer fallback, still run the focus write for text entry, and return a specific message when nothing handled the click. Use an element-oriented error text in the scroll path.

### L3. Mid-batch transition to off stage is not detected for element-step pointer fallbacks
- **Where:** ComputerUseService.swift:1263-1267. `isOffStage` comes from the pinned snapshot, and live bounds are the thumbnail after the transition.
- **Failure scenario:** an element step whose AX click falls back to pid-posted mouse events computes a point from thumbnail-sized live bounds. The events go to the app, not to the Stage Manager strip, so there is no activation, but the click can land on the wrong element.
- **Fix:** in batch geometry, call `liveOffStageWindow` (or compare the live window-server area with the pinned AX area) and refuse pointer fallbacks when the ratio falls below the threshold.

### L4. Wider multi-attribute request raises the cost of whole-call failures (3e306ce)
- **Where:** AccessibilityAttributePrefetch.swift:9-20 (renderAttributes grew from 11 to 21 attributes, including AXRows, AXContents and AXVisibleChildren)
- **Failure scenario:** an AX server that fails the whole `AXUIElementCopyMultipleAttributeValues` call on an unsupported attribute (instead of returning a per-slot sentinel) now pays two failed multi calls per node: the render fetch, then the `childListAttributes` fetch inside `children(of:)`. Both fall back to the single reads that follow. This is correct but slower than before the change on such apps.
- **Fix (optional):** when the render prefetch returned nil, skip the second fetch in `children(of:)` (pass a flag, or cache "multi unsupported" for the build).

## Informational
- **I1.** BackgroundOperationInvariantTests pins only `.activate(`. `activateClickTarget` (ComputerUseService.swift:1700-1716: AXRaise, AXMain and AXFocused on window-role targets) and `raiseAppWindowViaAccessibility` (InputSimulation.swift:373-377) are pre-existing and documented in the test header. They are still reachable in the default auto click path through `allowActivationFallback: true` when a window-role record is clicked. This is outside this diff, but RELIABILITY.md:52 ("no app activation ... on the normal path") is literally true while AXRaise can still reorder windows.
- **I2.** `recoverVisibleWindow` now only unhides. `NSRunningApplication.unhide()` does not activate, but the unhidden windows reappear. This is intended and documented in ARCHITECTURE.md:67.
- **I3.** Focus-related tests are pure-function level:
  - The live wiring of `liveFocusedElement(pinned:)` (ComputerUseService.swift:1367-1379) and of the snapshot fallback is covered only by source-text checks.
  - With FakeAccessibilityTree now available, a render test with `focusedElement == nil` and a focused field would pin the "deepest non-container wins" behavior end to end. The golden already carries `goldenFocusCandidates`, so this is partly covered.

## Docs check
- ARCHITECTURE.md:67 and RELIABILITY.md:55-58 match the new recovery, launch, off-stage and read-batching behavior, except the M1 overstatement.
- skills/open-computer-use/SKILL.md step 8 and references/usage.md:90, 111-112 match the off-stage and click-then-type flow, except the M1 overstatement.
- The `set_value ""` change is consistent with the Go runtimes, which already accept "" (`requiredString` only trims).

## Recommended actions
1. M1: derive `acceptsKeyboardText` without `isValueSettable`, gate setValue on a text role, replace the phantom test, then correct RELIABILITY.md:55 and usage.md:112 wording if behavior stays.
2. M2: add the combined-instructions length test, and trim the guide or move its safety bullets into the tool description.
3. L2: handle an element_index click on an off-stage window without the pointer fallback, and keep the focus write.
4. L1, L3 and L4 are optional follow-ups.

## Unresolved questions
- Is typing into a settable non-text focus (M1) ever intended, for example combo-like custom controls reporting a non-text role? If so, keep it but document it.
- Should the cascade guide be kept in the instructions at all, given the per-result `resultNote`?
