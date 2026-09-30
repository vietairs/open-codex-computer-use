# Phase 01: Capture policy, text-only action results, carrying the coordinate frame forward (lever L1)

- **Depends on:** phase 00, whose baseline must exist before this commit is measured.
- **Blocks:** phases 03, 04 and 05.
- **Parallel-safe with:** 02 and 06. Their files are disjoint. See the parallel rule in plan.md.
- **Roles:** Tester (writes tests only) ≠ Implementer (writes source only).
- **Effort:** 3h.
- **Commit (exactly one):** `perf(snapshot): skip window capture for text-only action results`
- Worktree: `W=/Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/continuous-computer-use-speed`. Paths below are relative to `W`. `S=packages/OpenComputerUseKit/Sources/OpenComputerUseKit`, `T=packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests`.

## Context (verified at afb60fa)

- Capture runs inside every snapshot build. `WindowCapture.resolve` calls `captureImage` for onscreen windows (`S/AccessibilitySnapshot.swift:639`), and `buildAccessibilitySnapshot` encodes the PNG before the walk (`:393`).
- Every action tail calls `snapshotResult(for: try refreshSnapshot(for: query), style: .actionResult)`. There are 16 action tails: `S/ComputerUseService.swift:644, 774 (multi-line; its `style:` is on :778), 791, 808, 829, 851, 859, 871, 881, 886, 898, 902, 910, 914, 931, 958`; `grep -c 'style: .actionResult'` prints 16 at afb60fa. `:774` is the click tail with a recovery policy, and `:871` is the drag tail wrapped by `appendingDragDeliveryNote`.
- `snapshotResult` attaches the PNG for every style except compact (`:2066-2073`).
- x/y coordinates are scaled by the cached snapshot's PNG pixel size (`screenshotPixelSize(snapshot:)` `:1793`). Its callers are `screenshotPixelToWindowPointInSnapshot` `:1785`, which serves click x/y at `:712`, and `screenshotToGlobalPoint` `:1775`, which serves drag at `:862-863` and hit-testing at `:1300`. When there is no PNG, `screenshotPixelScale` falls back to 1×1 (`:232-245`).
- `hitTestElement` (`:1298-1300`) receives **window** points from both of its callers: `clickCandidates(at: point)` `:1063`, where `point` is already the window point computed at `:712`, and the nearby hit-test loop `:1160-1161`, which iterates window-local `clickActionPoints`. It nevertheless sends them through `screenshotToGlobalPoint`, which scales them again as if they were screenshot pixels (a latent double scaling at base). The nearby loop runs for single `element_index` clicks whenever the direct AX press fails (`includeNearbyHitTesting: true` at `:669` and `:686`). Once `screenshotPixelSize` throws on a frame mismatch (below), that path would fail an element_index click after a text-only result plus a resize or a new window. The fix is to call `windowPointToGlobalPoint` (`:1809`) directly.
- `decideNextAction` builds a snapshot only to read text (`:507`).
- Decision 3: action results are text-only; a screenshot is attached on request or when the AX tree is empty; get_app_state is unchanged. Decision 11: text-only must also skip SCScreenshotManager.

## Data flow after this phase

```
action call ─► dispatcher parses include_screenshot (default false)
            ─► service action body (unchanged) ─► finishAction(query, includeScreenshot, recoveryPolicy)
                 ─► refreshSnapshot(capture: include ? .always : .whenTreeEmpty)
                      ─► SnapshotBuilder.build(capture:) ─► WindowCapture.resolve(captureImage: policy == .always)
                           ─► walk ─► if .whenTreeEmpty and records.isEmpty and onscreen: capture now
                 ─► snapshotResult(style: .actionResult, includeScreenshot)
                      ─► image attached iff shouldAttachScreenshot(...) ─► if attached: record ReturnedScreenshotFrame[pid]
get_app_state  ─► refreshSnapshot(capture: .always)  (unchanged output: text + image; compact: text)
decide_next_action ─► refreshSnapshot(capture: .never)
x/y click / drag ─► screenshotPixelSize ─► resolveScreenshotPixelSize(snapshot PNG ?? carried frame ?? nil | throw)
hitTestElement (window point) ─► windowPointToGlobalPoint   (no screenshot scaling; never throws a frame mismatch)
```

## Signature

`S/AccessibilitySnapshot.swift` (new, internal):
```swift
enum SnapshotCapturePolicy: Equatable, Sendable {
    case always         // capture before the walk (today's order): get_app_state, cache-miss builds
    case never          // SCScreenshotManager is never called: decide_next_action
    case whenTreeEmpty  // walk first; capture only if the walk produced zero element records
}
enum WindowImageCaptureTiming: Equatable { case beforeWalk, afterWalkIfTreeEmpty, skip }
func windowImageCaptureTiming(policy: SnapshotCapturePolicy, isOnscreen: Bool) -> WindowImageCaptureTiming
// !isOnscreen -> .skip for every policy; .always -> .beforeWalk; .whenTreeEmpty -> .afterWalkIfTreeEmpty; .never -> .skip
```

Changed signatures. Old → new; every caller is listed.
```swift
// OLD static func build(for:textLimit:treeLimits:recoveryPolicy:) throws -> AppSnapshot
static func build(for app: RunningAppDescriptor, textLimit: SnapshotTextLimit = .defaults,
                  treeLimits: AccessibilityTreeLimits = .defaults,
                  recoveryPolicy: SnapshotRecoveryPolicy = .allowActivation,
                  capture: SnapshotCapturePolicy = .always) throws -> AppSnapshot
// caller: ComputerUseService.refreshSnapshot (:977) only

// private struct WindowCapture gains `let isOnscreen: Bool` (its only constructor call is in resolve, :640)
// OLD static func resolve(for pid: pid_t, titleHint: String?) -> WindowCapture?
static func resolve(for pid: pid_t, titleHint: String?, captureImage: Bool = true) -> WindowCapture?
// callers: SnapshotBuilder.build (:352, :360), both pass `captureImage: capture == .always`
func capturingImage() -> WindowCapture   // new: returns self with image captured now if isOnscreen && image == nil
```

`S/ComputerUseService.swift` (file scope, internal):
```swift
struct ReturnedScreenshotFrame: Equatable {
    let windowID: CGWindowID?
    let windowSize: CGSize
    let pixelSize: CGSize
}
let screenshotFrameMismatchMessage =
    "x/y coordinates refer to a screenshot of a different window or window size. Call get_app_state, or repeat the action with include_screenshot=true, and read coordinates from the new screenshot."
func resolveScreenshotPixelSize(snapshotPixelSize: CGSize?, windowID: CGWindowID?, windowBounds: CGRect?,
                                lastReturned: ReturnedScreenshotFrame?) throws -> CGSize?
// 1. snapshotPixelSize != nil                                   -> snapshotPixelSize   (today's behaviour)
// 2. lastReturned == nil                                        -> nil (scale 1: no screenshot of this app was returned)
// 3. lastReturned.windowID == windowID && lastReturned.windowSize == windowBounds?.size -> lastReturned.pixelSize
// 4. otherwise                                                  -> throw ComputerUseError.stateUnavailable(screenshotFrameMismatchMessage)
func actionCapturePolicy(includeScreenshot: Bool) -> SnapshotCapturePolicy   // true -> .always, false -> .whenTreeEmpty
func shouldAttachScreenshot(style: SnapshotTextStyle, includeScreenshot: Bool, treeIsEmpty: Bool) -> Bool
// .compactActionable -> false; .fullState -> true; .actionResult -> includeScreenshot || treeIsEmpty
```

`ComputerUseService` members:
```swift
private var lastReturnedScreenshotFrames: [pid_t: ReturnedScreenshotFrame] = [:]  // sibling of snapshotsByApp (:460), same per-service lifetime
public func click(app:elementIndex:x:y:clickCount:mouseButton:clickMethod: ClickMethod = .auto, includeScreenshot: Bool = false) throws -> ToolCallResult
public func performSecondaryAction(app:elementIndex:action:includeScreenshot: Bool = false) throws -> ToolCallResult
public func scroll(app:direction:elementIndex:pages:includeScreenshot: Bool = false) throws -> ToolCallResult
public func drag(app:fromX:fromY:toX:toY:includeScreenshot: Bool = false) throws -> ToolCallResult
public func typeText(app:text:includeScreenshot: Bool = false) throws -> ToolCallResult
public func pressKey(app:key:includeScreenshot: Bool = false) throws -> ToolCallResult
public func setValue(app:elementIndex:value:includeScreenshot: Bool = false) throws -> ToolCallResult
private func finishAction(query: String, includeScreenshot: Bool, recoveryPolicy: SnapshotRecoveryPolicy = .allowActivation) throws -> ToolCallResult
private func refreshSnapshot(for:textLimit:treeLimits:recoveryPolicy:capture: SnapshotCapturePolicy = .always) throws -> AppSnapshot
private func snapshotResult(for snapshot: AppSnapshot, style: SnapshotTextStyle, includeScreenshot: Bool = false) -> ToolCallResult
private func screenshotPixelSize(snapshot: AppSnapshot) throws -> CGSize?                     // OLD: non-throwing
private func screenshotPixelToWindowPointInSnapshot(snapshot: AppSnapshot, point: CGPoint) throws -> CGPoint  // OLD: non-throwing; callers :712 (add try), :1778
// hitTestElement(at:in:) keeps its signature; its body changes from
//   try screenshotToGlobalPoint(snapshot: snapshot, x: Double(point.x), y: Double(point.y))
// to
//   try windowPointToGlobalPoint(snapshot: snapshot, point: point)
// so screenshotToGlobalPoint's only callers are drag's two lines (:862-863).
```
The public signature changes are source-compatible, because each new parameter is defaulted. The only in-repo callers are the dispatcher cases (`S/ComputerUseToolDispatcher.swift:81-126`).

## Boundaries

```
TARGET:    S/AccessibilitySnapshot.swift   (SnapshotBuilder.build, buildAccessibilitySnapshot, WindowCapture, new enums/function)
           S/ComputerUseService.swift      (action tails, refreshSnapshot, snapshotResult, screenshotPixelSize chain,
                                            getAppState :479 keeps .always, decideNextAction :507 -> .never, new file-scope items,
                                            hitTestElement :1300 -> windowPointToGlobalPoint)
           S/ToolDefinitions.swift         (add "include_screenshot" boolean to click, drag, perform_secondary_action,
                                            press_key, scroll, set_value, type_text; nothing else)
           S/ComputerUseToolDispatcher.swift (pass include_screenshot in those 7 cases only)
           T/ActionResultScreenshotPolicyTests.swift (new; Tester only)
READ-ONLY: S/ToolResult.swift, S/FixtureBridge.swift, T/OpenComputerUseKitTests.swift (patterns: makeFixtureSnapshotWithScreenshot :3494,
           FakeUnlockedSessionProvider)
FORBIDDEN: any change to get_app_state output (full: text+image; compact: text only) or to the compact capture;
           a snapshot TTL/freshness check in currentSnapshot (:961-967) — counsel "What to avoid";
           a new stored field on AppSnapshot (6 memberwise construction sites must compile unchanged);
           a second writer of snapshotsByApp (single write point :990-991 stays);
           S/SoftwareCursorOverlay.swift, S/CursorMotionModel.swift (phase 02); S/DecisionJev*.swift, S/DecisionRemoteBackend.swift (phase 06);
           S/MCPServer.swift, skills/**, docs/** (phase 07); T/OpenComputerUseKitTests.swift, T/DecisionAdvisorTests.swift (phase 05);
           Track B files: MacOSAppAgentProxy.swift, OpenComputerUseMain.swift, MCPAppRuntime.swift, MacSessionGuard.swift
```

## Tasks

### Task 1.0: Regression baseline (Implementer)
- Goal: find out whether the test suite is green at the base commit.
- Steps: `cd $W && git log -1 --format=%h` must print `afb60fa`. Then run `swift test 2>&1 | tail -15`.
- Verify: exit code 0, and the output contains `with 0 failures`. If it is not green, apply the Failure Protocol. Do not "fix" pre-existing failures.

### Task 1.1: Failing tests first (Tester)
- Goal: `T/ActionResultScreenshotPolicyTests.swift` (class `ActionResultScreenshotPolicyTests`) pins every rule in the Signature block.
- Steps: write the assertions listed under Acceptance, and nothing else. Use `AXUIElement`-free inputs only.
- Verify (expected RED): `swift test --filter OpenComputerUseKitTests.ActionResultScreenshotPolicyTests 2>&1 | tail -30` exits non-zero, and the output contains `cannot find 'windowImageCaptureTiming' in scope` or `cannot find 'resolveScreenshotPixelSize' in scope`. A green run here is itself a failure.

### Task 1.2: Capture policy in the builder (Implementer)
- Target: `S/AccessibilitySnapshot.swift`.
- Steps:
  1. Add the enums and `windowImageCaptureTiming`.
  2. Add `isOnscreen` to `WindowCapture`, the `captureImage:` parameter to `resolve`, and `capturingImage()`.
  3. Add the `capture:` parameter to `build`, and pass `captureImage: capture == .always` at both `resolve` calls.
  4. Thread `capture` into `buildAccessibilitySnapshot`. When the timing is `.afterWalkIfTreeEmpty` and `renderer.records.isEmpty`, take the PNG from `windowCapture.capturingImage().pngDataIfAvailable()` after the walk. Otherwise keep today's `windowCapture.pngDataIfAvailable()`.
- Verify: `swift build 2>&1 | tail -5` exits 0.

### Task 1.3: Service tails, the carried frame, and decide (Implementer)
- Target: `S/ComputerUseService.swift`.
- Steps:
  1. Add the file-scope items and `lastReturnedScreenshotFrames`.
  2. Add `capture:` to `refreshSnapshot` and forward it to `build`.
  3. Add `finishAction`. Replace every action tail listed in Context with `finishAction(query:includeScreenshot:recoveryPolicy:)`. Keep the click tail's `clickActionSnapshotRecoveryPolicy(for: clickMethod)`, and keep drag's `appendingDragDeliveryNote` wrapper.
  4. Add `includeScreenshot` to the 7 public action methods.
  5. In `snapshotResult`, attach the image only when `shouldAttachScreenshot(style:includeScreenshot:treeIsEmpty: snapshot.elements.isEmpty)` is true. When the image is attached, record `ReturnedScreenshotFrame` under `snapshot.app.pid`, taking the pixel size from the PNG header with the existing decoding code.
  6. Route `screenshotPixelSize(snapshot:)` through `resolveScreenshotPixelSize`, and make the chain `throws`.
  7. In `decideNextAction` (`:507`), call `refreshSnapshot(for: query, capture: .never)`.
  8. In `hitTestElement` (`:1300`), replace the `screenshotToGlobalPoint` call with `try windowPointToGlobalPoint(snapshot: snapshot, point: point)`. Both callers pass window points (see Context), so this removes the double scaling and keeps the frame-mismatch throw off the element_index path.
- Verify: `swift build 2>&1 | tail -5` exits 0.

### Task 1.4: Schema and dispatcher (Implementer)
- Targets: `S/ToolDefinitions.swift` and `S/ComputerUseToolDispatcher.swift`.
- Steps:
  1. Add one private constant, `includeScreenshotPropertyDescription = "Attach a window screenshot to the result. Defaults to false: action results are text-only unless the accessibility tree is empty."`.
  2. Add `"include_screenshot": booleanProperty(description: includeScreenshotPropertyDescription)` to the 7 action schemas.
  3. In the 7 dispatcher cases, pass `includeScreenshot: try optionalBool("include_screenshot", in: arguments) ?? false`, placed before the service call's other parameters are evaluated.
- Verify: `swift test --filter OpenComputerUseKitTests.ActionResultScreenshotPolicyTests 2>&1 | tail -30` exits 0 and contains `with 0 failures`.

### Task 1.5: Regression and commit (Implementer)
- Verify:
  - `swift test 2>&1 | tail -15` exits 0 and contains `with 0 failures`.
  - `git diff --stat afb60fa -- $S/CursorMotionModel.swift $S/MCPServer.swift` prints nothing.
  - `style: .actionResult` appears only inside `finishAction`: `grep -c 'style: .actionResult' $S/ComputerUseService.swift` prints `1`, and
    `awk '/func finishAction\(/{f=1} /style: \.actionResult/{print (f ? "inside" : "OUTSIDE")} f && /^    }$/{f=0}' $S/ComputerUseService.swift` prints exactly one line, `inside`. (A grep for `refreshSnapshot(for: query), style: .actionResult` would miss the multi-line click tail.)
  - Only drag calls `screenshotToGlobalPoint`: `grep -n 'try screenshotToGlobalPoint(' $S/ComputerUseService.swift` prints exactly 2 lines, the `let start =` and `let end =` lines inside `drag`, and `grep -c 'screenshotToGlobalPoint' $S/ComputerUseService.swift` prints `3` (the definition plus those 2).
- Then run `git add -A packages && git commit` with the exact subject above, and report the SHA.

## Acceptance

Command: `cd $W && swift test --filter OpenComputerUseKitTests.ActionResultScreenshotPolicyTests`

Assertions (write these first; they must fail before the change and pass after):
- `windowImageCaptureTiming`:
  - `(.always, true)` → `.beforeWalk`
  - `(.whenTreeEmpty, true)` → `.afterWalkIfTreeEmpty`
  - `(.never, true)` → `.skip`
  - `(.always, false)`, `(.whenTreeEmpty, false)` and `(.never, false)` → `.skip`
- `actionCapturePolicy(includeScreenshot: false)` → `.whenTreeEmpty`, and `(true)` → `.always`.
- `shouldAttachScreenshot`:
  - `(.actionResult, false, false)` → false (the text-only default)
  - `(.actionResult, true, false)` → true
  - `(.actionResult, false, true)` → true (empty tree)
  - `(.fullState, false, false)` → true (get_app_state unchanged)
  - `(.compactActionable, true, true)` → false
- `resolveScreenshotPixelSize`:
  - A snapshot PNG of 800×600 with any `lastReturned` → 800×600.
  - Nil PNG and nil `lastReturned` → nil.
  - Nil PNG with `lastReturned(windowID 7, windowSize 400×300, pixel 800×600)`, called with windowID 7 and bounds 400×300 → 800×600.
  - The same `lastReturned` with bounds 500×300 → throws, and the error text equals `screenshotFrameMismatchMessage`.
  - The same `lastReturned` with windowID 8 → throws.
- `ToolDefinitions.all`:
  - Each of `click, drag, perform_secondary_action, press_key, scroll, set_value, type_text` has `inputSchema["properties"]["include_screenshot"]["type"] == "boolean"`.
  - `get_app_state` and `list_apps` do not have it.
- Dispatcher: using `ComputerUseToolDispatcher(guard: MacSessionGuard(provider: FakeUnlockedSessionProvider()))`, `callToolAsResult(name: "press_key", arguments: ["app": "NoSuchApp", "key": "a", "include_screenshot": "maybe"])` has `isError == true`, and its `primaryText` contains `include_screenshot must be a boolean`. This proves the argument is parsed before any app resolution.

## Lever measurement M1 (main loop, after the commit)

Run `MEASURE(C1, <SHA>, extras: gas)` from phase 00, comparing against B0.
- Expected attribution: all four action tools drop by the capture, encode and transfer cost, and the `parts` of action results are `['text']` only.
- `get_app_state` full stays within ±5% of B0 and its `parts` still include `image`. Compact stays within ±5%.
- A regression in `get_app_state` full is a Failure-Protocol event.

## Risks

| Risk | L×I | Mitigation |
|---|---|---|
| An x/y click after a text-only result scales by 1× and misses (brainstorm §1.3) | H×H if unmitigated | The carried frame plus a fail-closed mismatch, pinned by the tests above |
| `whenTreeEmpty` capture runs after recovery, and the window has moved | L×L | `capturingImage()` uses the already-resolved window id and bounds |
| Latent double scaling in `hitTestElement` (`:1300` passes window points to `screenshotToGlobalPoint`); with the new throwing `screenshotPixelSize` it would also fail element_index clicks after a text-only result plus a resize | H×H if unmitigated | Fixed here (Task 1.3 step 8, user decision): `hitTestElement` calls `windowPointToGlobalPoint` directly. Pinned by the Task 1.5 invariant that only drag calls `screenshotToGlobalPoint`. On Retina this is a behaviour fix: hit-tests previously landed at half-scaled points. |

## Rollback

`git revert <C1>`. Phase 05 must be reverted first if it has landed, because it builds on `finishAction`. Phases 02, 04 and 06 revert independently. Phase 03 touches the same file but not the same symbols, so revert it only if `git revert` reports a conflict.

## Contract Rules
1. Implements to the SIGNATURE exactly. A signature that cannot work is a STOP, not a redesign —
   report it through the Failure Protocol.
2. Edits only within TARGET. Discovering that the change genuinely requires a FORBIDDEN file is a
   STOP with that finding, never a quiet widening.
3. Writes the acceptance assertions first where the plan says tests-first, confirms they FAIL, then
   implements until they pass.
4. Never weakens an assertion, never marks a test skipped, and never stubs an implementation to
   make one pass. A passing suite obtained this way is the specific failure this whole contract is
   built to prevent — cheap tiers reward-hack checkable specs more than strong ones do, so the
   escalation path exists precisely for the moment the spec looks unsatisfiable.
5. On any failed Verify, follows the `## Failure Protocol` already in the phase file. That is the
   backchannel; using it is correct behaviour, not an admission of failure. The escalation names
   the failure's class: a missed edge case, a wrong or incomplete fix, a misread requirement
   (including a wrong reading of an ambiguous one), or a wrong domain rule. The first two are
   fixed by more verification. The last two are not fixed by more effort or by a retry: they need
   the outcome re-locked or the rule looked up, so name the class in the escalation instead of
   retrying.

## Failure Protocol
If any Verify step does not meet its stated pass condition, STOP this phase.
Do not improvise a fix, retry blindly, or reason around the failure.
Spawn the `kongming` subagent for next-step counsel and pass:
- the phase and task id,
- what you attempted (the steps you ran),
- the exact command and its full output,
- the pass condition it failed to meet.
Apply kongming's guidance, then re-run the Verify step.
If `kongming` cannot be spawned in this environment, STOP and report the same
failure evidence to the user. Never continue by self-reasoning.
