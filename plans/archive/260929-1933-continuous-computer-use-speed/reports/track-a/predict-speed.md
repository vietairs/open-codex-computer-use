# Predict: Track A (PR A speed), per-file change-set analysis

Input: the approved Proposal A, the 5 advisor corrections (outcome-lock decision 12), and decision 13 (batched AX attribute reads). Every claim was read in the Track A worktree at `afb60fa`, read-only. The code-review-graph was built at `afb60fa` (head matches). The `SnapshotBuilder.build` → `refreshSnapshot` chain is the only production path into the AX walk. Paths below are relative to `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/` (S/) or `.../Tests/OpenComputerUseKitTests/` (T/).

## Verdict: CAUTION

The design is sound and nothing blocks it. Five predictions below were missing from the brainstorm and counsel, and each needs a plan line:
- The removed post-action refresh was also an implicit ~1.3s settle between steps.
- Three hidden tool-count asserts exist.
- The AX walk has no automated coverage.
- The jev test suite would write to the real config directory.
- A fixture-based "no image" test would be vacuous.

## Per-file predictions

### S/ComputerUseService.swift (2074 lines, highest risk)
- **Blast radius.** There are 20 `refreshSnapshot(` call sites: 18 action tails, plus :479 (get_app_state) and :507 (decide). Every one gains a capture or observation argument, and the fixture branches (:642, :807, :828, :858, :880, :909, :929) must pass the context through as well. The single write point for `snapshotsByApp` stays at :990-991. Track B's find_elements hook depends on that, so do not add a second writer.
- **Implicit settle loss (new, high).** Today each step's `refreshSnapshot` gives the app ~1.3s to react before the next call. In a batch, the next step starts within milliseconds.
  - `pressKey` (:912-913) and the keyboard path of `typeText` (:901) have no sleep at all.
  - "Click the search field, type, Return" can therefore read focus live before Mail has moved it, which is exactly the failure in test-260929-1720 §Problems 2.
  - The runner needs one inter-step settle (the `postActionSettleInterval` constant). A live check must confirm that it is long enough on Mail.
- **Focus correction.** `typeTextBySettingFocusedValueIfAvailable` (:1535) and `canTypeTextUsingKeyboardFallback` (:1556) take the whole snapshot and read `snapshot.focusedElement`. To make the required unit test possible without AX, split out a pure `typingTarget(pinned:live:)` choice, or pass the element in explicitly. A fake `AXUIElementCreateApplication(4242)` element (the pattern at T/:1230) is enough to assert which element was chosen.
- **Stale frames.** `windowPointToGlobalPoint` (:1812) uses `snapshot.windowBounds`. `hitTestElement` and `bestElement(containing:)` in the AX click chain (:1160-1190) use the pinned frames. Live bounds must be read before any coordinate fallback in steps 2 and later.
- **Coordinate carry-forward.** `screenshotPixelSize(snapshot:)` (:1793) serves click x/y and also single `drag` (:862-863). Put the `lastScreenshotFrame` fallback there so that drag is covered too.
  - `decideNextAction` (:507) overwrites the cache. Once it builds with `.never`, the next x/y click would scale by 1× unless the fallback applies.
  - Existing latent bug: compact `get_app_state` captures a PNG that the agent never sees (:2069), and x/y clicks are later scaled by it. Decide whether compact should also use `.never`. That changes no output.
- **Recovery policy.** `clickActionSnapshotRecoveryPolicy` (:29-31) returns `.readOnly` for skyClick. The batch's final snapshot must use the most restrictive policy of any step. Otherwise a batch containing a skyClick can activate the app when a single skyClick call would not.
- **Sleep constant.** The literals have 4 distinct meanings: 0.15 settle, 0.1 after an AX set, 0.08 after activation, and 0.05 in the fallback loops. Unify only the 0.15s settles. The 0.15s sleeps inside `performAXClickSequence` (:1140-1205) gate click-success detection, so trimming them risks false "not handled" results and double clicks.

### S/AccessibilitySnapshot.swift (capture policy and multi-attribute reads)
- **Capture skip is clean.** `WindowCapture.resolve` (:600-641) takes bounds and windowID from `CGWindowListCopyWindowInfo` and only then calls `captureImage` (:639). A `captureImage: Bool` flag keeps window matching, recovery (:352-361) and bounds identical.
  - `whenTreeEmpty` needs `captureImage` (private static, :643) callable after the walk, because the PNG is read at :393, before the walk.
  - `AppSnapshot` has 6 memberwise construction sites (T/:3177, :3450, :3473, :3496; S/:411, :568). Keep the pixel size in the service's side map, not as a new stored field, and all 6 compile unchanged.
- **Batched reads (decision 13): the largest regression surface in PR A.**
  - Per node, `TreeRenderer.render` (:893-910) plus helpers makes roughly 15-20 IPCs: role, subrole, description, help, identifier, selected, expanded and enabled (:1243-1251), two `isSettable` calls (:1255, :1267: a duplicate, worth memoising), position and size (:1663-1664), actions, and children/rows.
  - Prefetch only the attributes that are read unconditionally. Today `AXValue` is read only after `isSettable` succeeds (:1267-1271). Prefetching it for every node would pull large web-area and text values and could make Mail slower.
  - `AXIsAttributeSettable` and `CopyActionNames` cannot be batched.
  - **Crash hazard.** `CopyMultipleAttributeValues` returns failed attributes as `kAXValueAXErrorType` AXValues, not as a missing entry. `copyElement` force-casts with `value as! AXUIElement` (:1296). Any prefetched element-typed attribute must map error sentinels to nil first.
  - `stringValue` and `boolValue` (:1330, :1355) already type-check, so they are safe once they are fed from the prefetch map.
- **No automated coverage.** `TreeRenderer` is private, and every snapshot test uses `buildFixtureSnapshot` or hand-built `AppSnapshot`s. A byte-identical rendered-text diff on live Finder, Mail and TextEdit (main loop, before and after) is the only guard, so the plan must list it as an acceptance step.

### New S/BatchActionRunner.swift and a new batch test file
- The closure seam (perform, observe) makes stop-on-failure, per-step lines, pinned-snapshot index resolution and upfront validation testable without the fixture app.
- Per-step lock checks need the dispatcher's `MacSessionGuard`, because `requireUnlocked` is called only in `callTool` (ComputerUseToolDispatcher.swift:62). The runner must receive the guard. It must not re-enter `callTool`, because that is Proposal D.
- Result shape: `primaryText` (ToolResult.swift:35) returns the first text item, and the CLI and smoke clients read it. Put the step lines and the final state in one text item, or put the steps first, and record the choice. When the final snapshot throws, the result must still carry the step lines with `isError=true`.

### S/ComputerUseToolDispatcher.swift, S/ToolDefinitions.swift (shared, append-only)
- `ActionStep.parse` duplicates about 40 lines of argument mapping (:81-126). That is allowed; routing the single-action cases through it is a follow-up. `validateClickMethod` reads `ProcessInfo` env (Service :606), the same as for single calls, so the batch adds no new env exposure.
- Put `perform_actions` in `all` (9→10). `computerUseServerInstructions(environment:)` then keeps comparing `listed.count > all.count` (MCPServer.swift:26) correctly.

### Tests with a hard-coded tool count (counsel named 2; there are 5)
- T/OpenComputerUseKitTests.swift:256 changes from 9 to 10.
- T/DecisionAdvisorTests.swift:437 changes from 9 to 10, and the test name `...AllStaysNine...` at :436 should be renamed.
- T/DecisionAdvisorTests.swift:448, the loopback listed count, changes from 10 to 11.
- T/DecisionAdvisorTests.swift:455-457 (`...StaysAtNine`) changes to 10.
- T/OpenComputerUseKitTests.swift:2963-2966: the locked-dispatcher `guiTools` list should gain `perform_actions`, which proves a batch is refused while locked.
- **Outside Track A's owned files:** `apps/OpenComputerUseSmokeSuite/.../main.swift:199` requires `tools.count == 9`. `scripts/run-tool-smoke-tests.sh` breaks unless it is updated.
- The instruction tests (T/:625, DecisionAdvisorTests :476/:507) compare against the Swift constant, not a literal, so rewording MCPServer.swift breaks nothing. Counsel's "update the constants" needs no test edit.

### S/MCPServer.swift
- Track A edits :8 (keeping "at the start of each assistant turn"), :10 (the tool list gains `perform_actions`), and :14. Line :16 stays byte-identical for Track B.

### S/SoftwareCursorOverlay.swift (CursorMotionModel.swift untouched)
- `animateMove` (:348) is `private static` and runs on main with a live panel, so the cap test cannot call it. Extract a pure `visualCursorTravelDuration(calibrated:)` that returns `min(calibrated, cap)` and test that.
- Tests T/:2639 and T/:2643-2660 keep passing because the model is unchanged. The brainstorm's "rewrite :2652" is superseded by correction 5.

### S/DecisionJevPrompt.swift, DecisionJevClient.swift, DecisionRemoteBackend.swift
- **Test pollution (new, high).** Tests build `DecisionJevLetterResolver` and `DecisionJevClient` through their default inits in 13 places (DecisionJevClientTests :41-367). If the disk directory defaults to the real `~/Library/Application Support/...`, `swift test` writes letter files there, and request-count asserts pass on the first run and fail on the second.
  - The disk directory must default to nil in both inits. Only production wiring (ComputerUseService.swift:589) passes the real path.
  - `resetCacheForTesting` must stay memory-only.
- **Partial progress.** `resolveLetters` (:81-101) holds progress in a local variable and throws it away when the deadline expires. To persist it, save the base `/tokenize` ids together with the resolved letters. The prefix check at :87 compares against the base tokens, so without them a resumed run cannot validate. Mark the table complete only after the distinctness check at :95.
- `readValidated` (:128) is generalized for reuse. Its existing tests in DecisionRemoteBackendTests must stay green without edits.

### Docs (Track A-owned regions)
- SKILL.md:14-16 and :39, and usage.md: add batching, `include_screenshot`, and a macOS-only note.
- docs/ARCHITECTURE.md needs updates in 4 places:
  - :67: action results are text-only.
  - :72: the cursor travel cap.
  - :145 and :158: these claim the Go runtimes match "the macOS main line"; add a caveat that they do not have `perform_actions`.
- AGENTS.md:43 requires a `docs/histories/` entry.

## Cross-track clash points
- MCPServer.swift :10 is edited by both tracks (B resolves it on rebase). ToolDefinitions and the dispatcher: both append.
- Tool counts: all 5 test sites plus the smoke suite's :199 move again in B (10→11). B's plan must restate every site.
- ComputerUseService.swift: A's `refreshSnapshot` signature change sits next to B's cache-merge hook. B's never-resetting index counter conflicts with A's final refresh, which renumbers from 0 and replaces the cache. B must merge after A's single write point.
- A's prefetch helper and B's private multi-attribute reader are deduplicated on B's rebase (parallel-tracks rule 6).

## What each acceptance criterion needs to be measurable

| Criterion | Needed before code |
|---|---|
| Turns 18→≤9 | A fixed prompt, the same mailbox state, and "turn" defined as an assistant message containing tool calls. Baseline is 18 (test-260929-1720). A live pre-check that "click search field, type, Return" works as one batch on Mail, because §Problems 1-2 show the click may not move keyboard focus. |
| Server median −30% | A direct-stdio replay harness with timestamps per request and response, n≥10 per tool, the combio call mix taken from the baseline transcript, run on the `afb60fa` build first. One commit per lever (capture skip, cursor cap, AX prefetch, settle), each built and measured, so no permanent env knobs are added. `OPEN_COMPUTER_USE_VISUAL_CURSOR=0` gives the cursor's upper bound. |
| jev warm ≤3s, cold no timeout | Wall-clock time of `decide_next_action` over stdio. Warm means a second in-process call. Cold means a new process after one success, and it must make 0 `/tokenize` calls. Unit tests count `/tokenize` calls with a fake transport; live, a metadata-only stderr count, with no URLs or keys. |
| Text-only default | Fixture snapshots never carry a PNG, so asserting "no image" through the fixture proves nothing. Test the pure `shouldCapture(policy:isOnscreen:treeEmpty:)` decision, and assert that `snapshotResult` omits the image when `include_screenshot=false`, using an `AppSnapshot` built with PNG data (the T/:3496 pattern). |
| Focus live | The pure typing-target test above. It fails if the pinned element is chosen. |
| Cursor cap | The pure duration test. CursorMotionModel.swift must show a 0-line diff (`git diff --stat`). |
| AX prefetch | A byte-identical live render diff (Finder, Mail, TextEdit) plus the per-lever timing. A sentinel-to-nil unit test built from a synthetic error AXValue. |

## Risk summary
| Risk | Severity | Early signal | Mitigation |
|---|---|---|---|
| Batch steps outrun the app with no implicit settle | High | Live Mail batch types into the message view | Inter-step settle, then live check |
| AX prefetch changes rendered text or crashes on an error sentinel | High | Live diff not identical; `as!` trap | Unconditional attributes only; nil-map sentinels |
| jev tests write to the real config directory | High | Second `swift test` run fails on request counts | Disk directory defaults to nil |
| Median misses −30% (type and key heavy) | Medium | Per-lever table below 30% | Decision 13 lever; report the mix |
| Smoke suite count breaks, file not owned by Track A | Medium | `run-tool-smoke-tests.sh` fails | Main loop assigns ownership |

## Unresolved questions
1. Does Track A own `apps/OpenComputerUseSmokeSuite/.../main.swift:199`? It is not in either track's owns list.
2. How long should the inter-step settle be? 0.15s may be too short for Mail's search-field focus, and the only evidence is live.
3. Should compact `get_app_state` and `decide_next_action` build with `.never`? It is output-neutral, but it touches decision 3's "get_app_state unchanged".
4. Where do the batch step lines go: the same text item as the final state, or a separate first item? This affects `primaryText` consumers.
5. What TTL should `resolved_at` use (counsel suggested 7 days)? It is still undecided.
