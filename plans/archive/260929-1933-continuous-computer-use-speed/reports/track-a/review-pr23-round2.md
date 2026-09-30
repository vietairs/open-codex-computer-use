# PR #23 review, round 2 (delta 853fde6..e89601c)

Read-only. Scope: commit e89601c (13 files, +257/-100) plus the accuracy of the updated PR body. Items that were already known or accepted (cascadeGuide truncation, the x/y descendant-press fallback, review Lows L1-L4) are not raised again.

## Verification
- `swift test` (unsandboxed, `--scratch-path /private/tmp/claude-501/ocu-speed-build-review`) at e89601c: **594 tests, 2 skipped, 0 failures**, exit 0. The DecisionAdvisor lock-guard test passed this time. The count matches the PR body: 590 + 6 new - 2 removed.
- CI at e89601c: **5/5 pass** (audit-dependencies, check-docs, check-hygiene, repo-checks, swift).
- A Swift script confirmed that `JSONSerialization` maps `true` to an `NSNumber` that `as? Int` accepts as 1 (see S2).

## Round 1 closure
| Item | Status |
|---|---|
| I1 usage.md Mail example | **Closed.** The example now clicks the search field by index, types, then presses Return, all inside one `--calls` array after `get_app_state`. It says that CLI calls are stateless, and it gives the MCP variant. `--calls` exists. |
| I2 default click raise | **Closed.** `activateClickTarget`, `setBoolAttribute` and `canUseActivationOnlyClickFallback` are deleted, and so is the `allowActivationFallback` parameter. Grep shows the only `kAXRaiseAction`/`kAXMainAttribute` uses left are `clickPriority` (a read) and `InputSimulation.raiseAppWindowViaAccessibility`. That function is reached only from `prepareAppForGlobalPointerInput`, which is gated by an environment variable. `noBackgroundWindowMessage`, RELIABILITY.md and ARCHITECTURE.md are now true for default paths. |
| S1 click_count | **Closed.** `optionalClickCount` is shared by `click` (dispatcher:87) and `parseBatchStep` (:559). The range is 1...3. The upper bound is now `< Double(Int.max)`, so 2^63 no longer traps. The batch error carries the `step N:` prefix, and a test asserts this. |
| S2 batch focus probe | **Closed.** `backgroundFocusProbeOrder` filters with `canUseKeyboardTextFallback(role:subrole:roleDescription:)`. A test checks the probe against `makeTypeTextFocus(...).acceptsKeyboardText` for every record, which is the right way to prevent drift. The stale comments are fixed. |
| S3/S4 wording | **Closed** in the PR body ("type_text scope" and "Text-only action results"). |

## Focus questions answered

**What does `auto` do now for a window element (or another element with no press action)?** The code path is `click` (ComputerUseService.swift:812-825) calling `performAXClickSequence`, in this order:
1. **Preferred press on the window itself.** This does nothing: a window has no AXPress/AXConfirm/AXOpen and is not a list item.
2. **Descendant candidates.** These are elements up to 3 levels deep, sorted by priority and then by smallest frame. The smallest pressable descendant is pressed. This step is unchanged by the PR (see S3).
3. **Single call only: nearby hit-testing** at the window's centre and at its leading point. A pressable element there, such as a message row selected through `AXSelectedChildren`, is handled through accessibility. This step is also unchanged.
4. **Before:** AXRaise, then AXMain, then AXFocused, which returned "handled". **Now:** `performNonAXClickFallback` at `clickPoint(for:)`, which is the centre of the window frame (`localClickActionPoints` puts the centre first). The events are pid-posted `clickBackgrounded`, and an off-stage window is rejected.

Assessment:
- This is **the same treatment every other element with no press action already gets** (groups, split groups, scroll areas, static text): a pid-posted click at the element's centre. So it is consistent, not a new class of behaviour.
- In a single call, step 3 has already tried whatever sits at the centre through accessibility. The posted click therefore only lands where accessibility found nothing to press. In a batch there is no hit-testing, so the posted click can select a Mail message row at the centre. That marks the message read, but it is in-app, non-destructive, and the same thing a click at those x/y coordinates would do.
- This trades a visible reorder of windows across apps, which the locked rule forbids, for a click at the element the caller named. That is acceptable and not worse.
- Explicit `click_method=accessibility` on a window now throws the existing `"click_method 'accessibility' could not click element_index=N"`. That is correct and documented in ARCHITECTURE.md. The `app_post`/`sky_click`/`global` paths are untouched.
- The call site compiles with no leftover references, and there are no stale docs about the removed fallback outside docs/histories.

**Invariant tests: meaningful or overfitted?** They are meaningful as a tripwire:
- Reverting e89601c would fail `testWindowRaiseAndMainWindowWritesStayOnOptInPaths`, because `activateClickTarget` names `kAXRaiseAction`/`kAXMainAttribute` and is not on the allowlist.
- It would also fail the focus-write check (`setBoolAttribute(named: kAXFocusedAttribute` is on one line).
- `XCTAssertEqual(Set(sites), allowed)` also catches stale allowlist entries.
- They are not overfitted to strings in a way that produces false passes today.
- They do have real blind spots (S1).

**ElementRecord changes.**
- `ElementRecord` is a `final class` with no Equatable/Codable/Hashable conformance. The two new fields have `nil` defaults, so the descendant and hit-test `ElementRecord(...)` constructors compile unchanged and carry nil, which is fine because the probe only uses snapshot records.
- The fields are set only on the record. The rendered line text (`lineBody`) is built before the record and does not read them, so render output cannot change. The byte-identical claim holds by construction; it was not re-measured live here.
- `kAXRoleDescriptionAttribute` is already in `AXAttributePrefetch.renderAttributes`. Reading it adds **no AX round trip** when the prefetch succeeds. When the batched read fails, it adds one extra single read per node. That is the known L4 fallback cost and is not new in kind.

**click_count error surfacing.**
- Single call: `callToolAsResult` returns an `isError` result that contains `click_count`. This is tested with 11 invalid values, including NaN, infinity, 2^63, 1.5 and a string.
- Batch: the error has a `step 1:` prefix and mentions `click_count`. The batch test covers 5 values.
- One gap: the JSON `true` case (S2).

## Findings

### Critical
None.

### Important
None.

### Suggestion

**S1. The invariant tests have blind spots that the PR body's wording does not admit.** (`BackgroundOperationInvariantTests.swift:466-493`)
- The focus-write check needs `kAXFocusedAttribute` and a write token **on the same line**. A multi-line `AXUIElementSetAttributeValue(\n element, kAXFocusedAttribute ...)` passes unseen.
- The allowlist works per function. `ComputerUseService.swift:click` covers both `click` overloads, about 150 lines. A new `AXFocused` write on a window inside `click` would pass.
- These writes are not covered at all:
  - `kAXMainWindowAttribute` / `kAXFocusedWindowAttribute` written on the **app** element. These reorder windows exactly like AXMain.
  - `kAXFrontmostAttribute` = true, which activates the app without `.activate(`.
  - String literals such as `"AXFocused"` and `"AXFrontmost"`.
- Grep confirms that none of these writes exist today, so this is a hardening item, not a live bug.
- Fix:
  - Add `kAXMainWindowAttribute`, `kAXFocusedWindowAttribute`, `kAXFrontmostAttribute`, `"AXFrontmost"` and `"AXFocused\""` to the scanned tokens, restricted to write lines.
  - Move the text-field focus write into a named helper, or assert exactly one focus-write line in `click`, so the allowlist cannot silently absorb a second write.

**S2. A JSON `"click_count": true` is accepted as 1, and the test that says otherwise is a false pass.** (`ComputerUseToolDispatcher.swift` `positiveInt`)
- `value as? Int` runs before the `CFBooleanGetTypeID` guard. An `NSNumber` boolean from `JSONSerialization` bridges to `Int` 1 (verified), so the guard never runs for real MCP or CLI input.
- `testClickRejectsClickCountOutsideOneToThreeWithoutTrapping` passes `true` as a Swift `Bool`. A Swift `Bool` does not cast to `Int`, falls through to the `NSNumber` branch, and is rejected. So the test proves behaviour that production input does not have.
- The outcome is harmless: a single click. The same ordering is pre-existing for every `positiveInt` key.
- Fix: check for a CFBoolean first. Build the test arguments with `JSONSerialization.jsonObject` so they take the production path.

**S3. Context for the window-click question: the higher-risk step for a window target is the descendant press, not the removed fallback.** This was pre-existing, is unchanged by this delta, and was not verified live.
- For an `AXWindow` target, `descendantClickCandidates` presses the **smallest** priority-0 descendant within 3 levels.
- On a standard window that set includes the traffic-light AXCloseButton, AXMinimizeButton and AXZoomButton, which are about 14x16 each and carry AXPress.
- `isLikelySyntheticSideAction` does not filter them: it looks at the trailing band and at done/archive labels, and the traffic lights sit on the leading edge.
- So `click element_index=<window>` may close, minimize or zoom the window before the new centre-click fallback is ever reached.
- The known follow-up in the PR body ("only press children whose frame contains the point") covers x/y only.
- Fix, in the same follow-up: for element_index targets, skip window-chrome subroles (`AXCloseButton`, `AXMinimizeButton`, `AXZoomButton`, `AXFullScreenButton`) as descendant candidates. Alternatively, refuse window-role targets in `auto` with "click a control inside the window".

**S4. The tool schema still does not state the range.** `ToolDefinitions.swift:43` says `"Number of clicks. Defaults to 1"`. Agents learn the 1-3 limit only from an error. Suggested text: "Number of clicks, 1 to 3. Defaults to 1." The batch shares the same step args. This text is in the tool schema, so it costs nothing from the 2048-char instructions budget.

**S5. The PR body has stale facts.**
- "CI: 5/5 green at 853fde6; re-running at e89601c" should now say 5/5 green at e89601c.
- "Changes: 50 files, +5819 / −434" should now say 51 files, +6047 / −505, 26 commits (`git diff --shortstat origin/main...e89601c`).
- The claim "an invariant test fails if a raise or main-window write returns outside the opt-in global-pointer path" is true for window AXRaise/AXMain but not for app-level AXMainWindow/AXFrontmost (S1). Either qualify it or close S1.

## PR body accuracy (the rest was verified)
- Background operation: accurate for default paths.
- The click_count input checks, the batch type_text focus parity, 594 tests, and the Round 1 closure line all match the code and the local run.
- The known-limitations list includes the click_count behaviour change and the localized role description. It should also say that string values such as `"2"` are now refused; they were silently treated as 1 before.

## Verdict
**Approve.** There are no Critical or Important findings. The delta closes every round-1 item correctly, the removal of the raise keeps the locked rule, and the new behaviour for window targets matches how every other element with no press action is handled. S5 is a two-line PR body edit worth doing before merge. S1-S4 can be follow-ups; S3 fits naturally into the existing descendant-press follow-up.

## Unresolved questions
- S3: Does a live `click element_index=<window>` on Mail press a traffic-light button? It cannot be checked from an agent shell; it needs a session with Accessibility access.
- Has the new Mail batch example been run live exactly as written? The history note verifies the click-focus write for single calls and batch steps, but not this example end to end.
