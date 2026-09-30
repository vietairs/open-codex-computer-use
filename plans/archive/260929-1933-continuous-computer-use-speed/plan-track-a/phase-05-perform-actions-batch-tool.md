# Phase 05: `perform_actions` batch tool (decision 1, advisor corrections 1, 3, 4 and the final-snapshot correction)

- **Depends on:** 01 (the `finishAction` and capture policy) and 03 (`postActionSettleInterval`). Both edit `ComputerUseService.swift`.
- **Blocks:** phase 07 (guidance describes the tool) and phase 08.
- **Parallel-safe with:** 02, 04 and 06 Tasks 6.1–6.4. It is **not** parallel-safe with 06 Task 6.5, which also edits `ComputerUseService.swift`.
- **Roles:** Tester ≠ Implementer.
- **Effort:** 5.5h.
- **Commit (exactly one):** `feat(actions): add perform_actions to run a short action sequence in one call`
- Paths: `W`, `S` and `T` are as defined in phase 01. `SMOKE=apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`.

## Context (verified at afb60fa)

- The snapshot cache persists per service instance (`snapshotsByApp` `S/ComputerUseService.swift:460`, read at `:961-967`, single write point `:990-991`). One service lives per MCP connection (`S/MCPServer.swift:38-43`).
- The existing CLI `--calls` loop refreshes after every step (`S/ComputerUseToolDispatcher.swift:344-366`). Reusing it would renumber indices between steps. That is Proposal D, which was rejected, so the batch must not call `callTool` or `callToolAsResult`.
- `typeText` reads focus from the snapshot: `typeTextBySettingFocusedValueIfAvailable(_:in:)` `:1535` and `canTypeTextUsingKeyboardFallback(in:)` `:1556`. Their only callers are `typeText` `:884` and `:888`.
- Click coordinates come from `record.localFrame` plus `snapshot.windowBounds` (`clickPoint` `:1771`, `windowPointToGlobalPoint` `:1809`). The nearby hit-testing in `performAXClickSequence` (`:1160-1190`) maps hits back through `bestElement(containing:)` over the snapshot's frames.
- `clickActionSnapshotRecoveryPolicy` returns `.readOnly` for sky_click (`:29-31`).
- The lock guard runs only in `callTool` (`S/ComputerUseToolDispatcher.swift:62`).
- The argument helpers are `private` in the dispatcher (`:149-250`). An `extension ComputerUseToolDispatcher` **in the same file** can use them, so no access-level change is needed.
- Tool-count asserts that move from 9 to 10:
  - `T/OpenComputerUseKitTests.swift:256`
  - `T/OpenComputerUseKitTests.swift:2963-2966` (`guiTools`)
  - `T/DecisionAdvisorTests.swift:436-437` (name and count), `:448` (10 → 11), `:455-457` (name and count)
  - `SMOKE:199-200`
- Smoke suite (`SMOKE`, owned by Track A, user decision): `runFullSmoke` (`:190-300`) drives the fixture app through `MCPClient.callTool` (`:52-73`), which throws `SmokeError.message(<tool text>)` when `isError` is true. Fixture actions post to `FixtureBridge`: `type_text` always targets `fixture-input` and `press_key` always targets `fixture-key-capture` (`S/ComputerUseService.swift:878-879, 907-908`). The last step today is `10. drag` (`:288-297`).

## Locked semantics (acceptance criteria, not options)

1. **Upfront validation.** All steps are parsed and validated before any step runs. That covers types, the allowed tools, 1–10 steps, no `app` inside a step, the click-method preconditions, and every `element_index` existing in the pinned snapshot. On a validation error nothing runs, no snapshot is refreshed, and the call returns an error naming the 1-based step.
2. **Pinned snapshot resolves `element_index` only.** The pinned snapshot is the app's cached snapshot at batch start. Focus, window bounds and the target element's frame are read **live** for every step. The single-action focus path is unchanged in PR A (user decision 2026-09-29: single `type_text` keeps the snapshot focus).
3. **No nearby hit-testing inside a batch.** Batch steps call `performAXClickSequence(..., includeNearbyHitTesting: false, ...)`. The pinned neighbours' frames may be stale, so a step fails rather than clicking a neighbour. The non-AX fallback uses the live target point.
4. **Order.**
   - Before every step: check the lock.
   - Before every step after the first: sleep `postActionSettleInterval` to settle.
   - Run the step with no observation.
   - Stop at the first thrown error.
5. **One final state.**
   - The lock is re-checked first. If the Mac is locked, the final snapshot is **not** read.
   - Otherwise there is one `refreshSnapshot`, with `recoveryPolicy = mostRestrictiveRecoveryPolicy(steps)` and `capture = actionCapturePolicy(includeScreenshot)`.
   - The result is a single text item: the step lines, a blank line, then the final state text, followed by the image only if one is attached.
   - `isError` is true when any step failed, or the final state failed or was not read.
   - **If the final snapshot throws, the step lines are still returned**, followed by `Final state unavailable: <message>`. When the lock skipped the final read, the step lines are followed by `Final state not read: <message>`.
6. **Allowed step tools:** `click, type_text, press_key, set_value, scroll, perform_secondary_action`. `drag` is excluded because it is not on the locked list.
7. Step lines never echo typed text or set values.

## Signature

New file `S/BatchActionRunner.swift`:
```swift
enum ActionStep: Equatable {
    case click(elementIndex: String?, x: Double?, y: Double?, clickCount: Int, mouseButton: String, clickMethod: ClickMethod)
    case typeText(text: String)
    case pressKey(key: String)
    case setValue(elementIndex: String, value: String)
    case scroll(direction: String, elementIndex: String, pages: Double)
    case performSecondaryAction(elementIndex: String, action: String)

    static let allowedToolNames: [String] = ["click", "type_text", "press_key", "set_value", "scroll", "perform_secondary_action"]
    var toolName: String { get }
    var elementIndex: String? { get }
    /// "click element_index=12" | "click x=100 y=40" | "type_text" | "press_key key=Return" | "set_value element_index=3"
    /// | "scroll element_index=5 direction=down" | "perform_secondary_action element_index=7 action=AXShowMenu"
    var summary: String { get }
}

enum BatchStepOutcome: Equatable { case ok, failed(String), notRun }

struct BatchActionReport: Equatable {
    let steps: [ActionStep]
    let outcomes: [BatchStepOutcome]
    var hasFailure: Bool { get }
    /// "Step 1 click element_index=12: ok" / "Step 3 press_key key=Return: failed: <message>" / "Step 4 click element_index=40: not run"
    var stepLines: [String] { get }
}

enum BatchActionRunner {
    static let maxSteps = 10
    /// element_index values (as given) that are absent from `knownIndices`, in step order.
    static func unknownElementIndices(in steps: [ActionStep], knownIndices: Set<Int>) -> [String]
    static func mostRestrictiveRecoveryPolicy(for steps: [ActionStep]) -> SnapshotRecoveryPolicy  // .readOnly iff any click uses .skyClick
    /// Runs steps in order; beforeEachStep(i) then perform(i, step); the first throw (from either) marks step i failed
    /// with `errorText(error)` and every later step notRun. Never observes state.
    static func run(steps: [ActionStep],
                    beforeEachStep: (_ index: Int) throws -> Void,
                    perform: (_ index: Int, _ step: ActionStep) throws -> Void) -> BatchActionReport
    /// finalState: .success(result) | .failure(error) = "Final state unavailable: …" | nil + notReadReason = "Final state not read: …"
    static func result(report: BatchActionReport, finalState: Result<ToolCallResult, Error>?, notReadReason: String?) -> ToolCallResult
    /// The same text callToolAsResult would show for this error.
    static func errorText(_ error: Error) -> String
}
```

`S/ComputerUseService.swift`:
```swift
struct ActionContext {
    let includeScreenshot: Bool
    let pinnedSnapshot: AppSnapshot?           // non-nil only for batch steps
    var isBatchStep: Bool { pinnedSnapshot != nil }
    static func single(includeScreenshot: Bool) -> ActionContext
    static func batchStep(pinned: AppSnapshot) -> ActionContext
}
/// Batch step -> liveFocus() (called exactly once); single action -> snapshotFocus (liveFocus not called).
func typingTargetElement(context: ActionContext, snapshotFocus: AXUIElement?, liveFocus: () -> AXUIElement?) -> AXUIElement?
/// Batch geometry, never falling back to pinned values:
/// windowBounds = liveWindowBounds; if nil while pinnedWindowBounds != nil -> throw stateUnavailable("the target window is no longer on screen; call get_app_state")
/// localFrame   = needsElementFrame ? (liveLocalFrame ?? throw stateUnavailable("element_index \(elementIndex!) is no longer on screen; call get_app_state")) : nil
func batchStepGeometry(pinnedWindowBounds: CGRect?, liveWindowBounds: CGRect?, liveLocalFrame: CGRect?,
                       needsElementFrame: Bool, elementIndex: String?) throws -> (windowBounds: CGRect?, localFrame: CGRect?)

// ComputerUseService
func performActions(app query: String, steps: [ActionStep], includeScreenshot: Bool,
                    checkLock: () throws -> Void) throws -> ToolCallResult
// internal variants carrying the context (public single-action methods delegate with .single(includeScreenshot:)):
func click(app:elementIndex:x:y:clickCount:mouseButton:clickMethod:context: ActionContext) throws -> ToolCallResult
func performSecondaryAction(app:elementIndex:action:context:) throws -> ToolCallResult
func scroll(app:direction:elementIndex:pages:context:) throws -> ToolCallResult
func typeText(app:text:context:) throws -> ToolCallResult
func pressKey(app:key:context:) throws -> ToolCallResult
func setValue(app:elementIndex:value:context:) throws -> ToolCallResult
// OLD private func finishAction(query:includeScreenshot:recoveryPolicy:)
private func finishAction(query: String, context: ActionContext, recoveryPolicy: SnapshotRecoveryPolicy = .allowActivation) throws -> ToolCallResult
//   batch step -> returns ToolCallResult(content: []) and does NOT refresh
// OLD private func typeTextBySettingFocusedValueIfAvailable(_ text: String, in snapshot: AppSnapshot) throws -> Bool
private func typeTextBySettingFocusedValueIfAvailable(_ text: String, focusedElement: AXUIElement?) throws -> Bool
// OLD private func canTypeTextUsingKeyboardFallback(in snapshot: AppSnapshot) throws -> Bool
private func canTypeTextUsingKeyboardFallback(focusedElement: AXUIElement?) throws -> Bool
private func liveGeometrySnapshot(from pinned: AppSnapshot, elementIndex: String?) throws -> AppSnapshot
//   fixture mode -> pinned unchanged; otherwise reads the live window bounds for pinned.targetWindowID
//   (CGWindowListCopyWindowInfo([.optionIncludingWindow], id)) and the target record's live AXPosition/AXSize,
//   calls batchStepGeometry, and returns a copy of pinned (AppSnapshot memberwise init) with the live bounds and the
//   target ElementRecord rebuilt with the live localFrame. No new stored field on AppSnapshot.
```

`S/ComputerUseToolDispatcher.swift`:
```swift
// new case in callTool, after "set_value"
case "perform_actions":
    return try service.performActions(
        app: requireString("app", in: arguments),
        steps: try parseBatchSteps(arguments["actions"]),
        includeScreenshot: try optionalBool("include_screenshot", in: arguments) ?? false,
        checkLock: { try self.macSessionGuard.requireUnlocked(for: "perform_actions") })
// appended at END of file:
extension ComputerUseToolDispatcher {
    /// Throws ComputerUseError.invalidArguments; messages start with "actions" or "step N:".
    func parseBatchSteps(_ raw: Any?) throws -> [ActionStep]
}
```
Validation messages, used exactly:
- `actions must be an array of 1-10 steps`
- `step N: each step must be an object with "tool" and "args"`
- `step N: tool '<name>' is not allowed in perform_actions`
- `step N: args must not contain "app"; perform_actions acts on one app`
- For argument errors, `step N: ` followed by `BatchActionRunner.errorText` of the error the existing private helper throws (for example `ComputerUseError.missingArgument("text")` from `requireString`). Wrap the helper error; do not invent new wording.
- scroll direction and pages use the same rules as `scroll` (`S/ComputerUseService.swift:812-818`).
- Unknown index (checked upfront in `performActions` against the pinned snapshot; nothing runs): `step N: element_index <value> is not in the state you last received for this app; call get_app_state`, for the first unknown index in step order. The smoke case in Task 5.1 relies on the text containing `step N` and the value.

`S/ToolDefinitions.swift`: append a `perform_actions` `ToolDefinition` as the **last** element of `all`, with `defaultAnnotations()`, this description, and this schema:
```text
description: "Run a short, fully specified sequence of Computer Use actions on one app in a single call. Steps run in
order and stop at the first failure; the result has one line per step followed by one final app state. Every
element_index refers to the state you last received for this app. Allowed step tools: click, type_text, press_key,
set_value, scroll, perform_secondary_action. This tool is part of plugin `Computer Use`."
schema: {"type":"object","additionalProperties":false,"required":["app","actions"],"properties":{
  "app":{"type":"string","description":"App name or bundle identifier"},
  "actions":{"type":"array","minItems":1,"maxItems":10,"items":{"type":"object","additionalProperties":false,
     "required":["tool","args"],"properties":{"tool":{"type":"string","enum":[<ActionStep.allowedToolNames>]},
     "args":{"type":"object","description":"The same arguments as the single tool, without app"}}}},
  "include_screenshot":{"type":"boolean","description":<includeScreenshotPropertyDescription>}}}
```

## Data flow

```
perform_actions ─► callTool: requireUnlocked("perform_actions") ─► parseBatchSteps (all steps, no side effects)
  ─► service.performActions
       pinned = currentSnapshot(app) (cache hit in steady state)
       validate: unknownElementIndices(pinned) empty; click-method preconditions (validateClickMethod/validateSkyClickArguments)
       report = BatchActionRunner.run(steps,
                  beforeEachStep: { i in try checkLock(); if i > 0 { Thread.sleep(postActionSettleInterval) } },
                  perform: { _, step in _ = try <core action>(…, context: .batchStep(pinned)) })   // no refresh per step
       (try? checkLock()) succeeds ? finalState = Result { try finishAction(query, context: .single(includeScreenshot: includeScreenshot),
                                                                       recoveryPolicy: mostRestrictiveRecoveryPolicy(steps)) }
                                   : finalState = nil, notReadReason = lock message
       return BatchActionRunner.result(report, finalState, notReadReason)
```
The cache is written once, by the final refresh, through the single write point `:990-991`. The final state goes through `finishAction` with a single-action context, so `style: .actionResult` still appears only inside `finishAction` (the phase 01 invariant). The service-level env override lock (`MacOSAppAgentProxy.swift:507-540`, Track B-owned and read-only here) is held for the whole batch. Phase 07 documents that.

## Boundaries

```
TARGET:    S/BatchActionRunner.swift (new)
           S/ComputerUseService.swift (ActionContext, typingTargetElement, batchStepGeometry, performActions, the six
                                       internal context variants + delegating public methods, finishAction(context:),
                                       the two typing helpers' new signatures, liveGeometrySnapshot)
           S/ComputerUseToolDispatcher.swift (one new case + one appended extension; the existing cases stay untouched —
                                              do NOT route single actions through parseBatchSteps)
           S/ToolDefinitions.swift (append perform_actions as the last element of `all`)
           T/BatchActionRunnerTests.swift (new; Tester)
           T/OpenComputerUseKitTests.swift (:256 and :2963-2966 only; Tester)
           T/DecisionAdvisorTests.swift (:436-437, :448, :455-457 only; Tester)
           SMOKE (Track A owns it, user decision: :199-200 count 9 -> 10, plus one new step "11. perform_actions"
                  appended at the end of runFullSmoke; Tester)
READ-ONLY: S/MacSessionGuard.swift, S/ToolResult.swift, apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift
FORBIDDEN: calling callTool/callToolAsResult from the batch (Proposal D); refreshing between steps; a snapshot TTL;
           drag in batches; refactoring the 9 existing dispatcher cases (counsel: follow-up after both PRs);
           S/MCPServer.swift, skills/**, docs/** (phase 07); S/DecisionJev*.swift (phase 06);
           S/AccessibilitySnapshot.swift and S/AccessibilityAttributePrefetch.swift (phase 04);
           S/SoftwareCursorOverlay.swift (phase 02); every Track B file
```

## Tasks

### Task 5.1: Failing tests first (Tester)
- Write `T/BatchActionRunnerTests.swift` (class `BatchActionRunnerTests`) with every assertion listed below.
- Update the 5 tool-count sites:
  - `OpenComputerUseKitTests.swift:256` → `10`.
  - `:2963-2966`: append `"perform_actions"` to `guiTools` and assert `10`.
  - `DecisionAdvisorTests.swift`: rename `testToolDefinitionsAllStaysNineAndExcludesDecideNextAction` → `testToolDefinitionsAllStaysTenAndExcludesDecideNextAction` and assert `10`.
  - `DecisionAdvisorTests.swift:448` → `11`.
  - Rename `testToolDefinitionsListedWithNonLoopbackURLStaysAtNine` → `...StaysAtTen` and assert `10`.
  - `SMOKE:199-200` → `10` in both the guard and the message.
- Append one fixture batch step to `runFullSmoke`, after `10. drag` and before `print("Smoke suite completed.")`:
  ```text
  print("11. perform_actions")
  state = get_app_state(app); index = parseElementIndex(state); before = parseCounterValue(state)
  state = perform_actions(app, actions: [
      {tool: click,     args: {element_index: index["fixture-increment"]!.index}},
      {tool: type_text, args: {text: "-batch"}},
      {tool: press_key, args: {key: "Escape"}}])
  expect: parseCounterValue(state) == before + 1          (click ran)
  expect: state contains "-batch"                          (type_text reached fixture-input)
  expect: state contains "Last key: Escape"                (press_key ran)
  expect: state contains "Step 1 click element_index=", "Step 2 type_text: ok", "Step 3 press_key key=Escape: ok"
  bad index: perform_actions(app, actions: [
      {tool: click,     args: {element_index: index["fixture-increment"]!.index}},
      {tool: click,     args: {element_index: "99999"}},
      {tool: press_key, args: {key: "Tab"}}])
  expect: callTool throws SmokeError.message(text) whose text contains "step 2" and "99999"
          (a call that returns without throwing is a smoke failure; catch only that error, not your own expect)
  state = get_app_state(app)
  expect: parseCounterValue(state) == before + 1 and state contains "Last key: Escape"
          (the batch stopped: no step of the bad batch ran, so neither the click nor the Tab landed)
  ```
  This is the only end-to-end run of `perform_actions` through the dispatcher and the service before live Mail. It runs in phase 08 L1 (main loop, GUI), never inside a workflow.
- Verify (RED): `swift test --filter OpenComputerUseKitTests.BatchActionRunnerTests 2>&1 | tail -30` exits non-zero and contains `cannot find 'BatchActionRunner' in scope`.

### Task 5.2: Pure runner (Implementer)
- Create `S/BatchActionRunner.swift` exactly as specified in the Signature block.
- Verify: the build fails only on the dispatcher, service and context symbols the tests reference, **or** the filtered test's runner-only assertions pass. Record which. Run `swift build 2>&1 | grep -c "error:"` and report the count; this Verify is informational only.

### Task 5.3: Service context, live geometry and focus (Implementer)
- Steps:
  1. Add `ActionContext`, `typingTargetElement` and `batchStepGeometry`.
  2. Convert the 6 batchable public methods to delegate to internal `context:` variants. Change `finishAction` to take `context:`.
  3. In `typeText(context:)`, obtain the element with `typingTargetElement(context:snapshotFocus: snapshot.focusedElement, liveFocus: { <copy kAXFocusedUIElementAttribute of AXUIElementCreateApplication(pid)> })`. Pass it to the two helpers' new signatures.
  4. In batch steps, use `liveGeometrySnapshot` instead of `currentSnapshot` for coordinates, and pass `includeNearbyHitTesting: !context.isBatchStep`.
  5. Add `performActions` following the Data flow.
- Verify: `swift build 2>&1 | tail -5` exits 0.

### Task 5.4: Tool definition and dispatch (Implementer)
- Append the `ToolDefinition`, the dispatcher case, and the extension.
- Verify: `swift test --filter OpenComputerUseKitTests.BatchActionRunnerTests 2>&1 | tail -30` exits 0 and contains `with 0 failures`.

### Task 5.5: Regression and commit (Implementer)
- Verify, all of:
  - `swift test 2>&1 | tail -15` exits 0 and contains `with 0 failures`. It must also pass on a second consecutive run.
  - `grep -c 'callToolAsResult\|callTool(' $S/BatchActionRunner.swift` prints `0`.
  - `grep -c 'refreshSnapshot(' $S/BatchActionRunner.swift` prints `0`.
  - `grep -n 'snapshotsByApp\[' $S/ComputerUseService.swift` shows exactly one assignment line, the single write point.
  - Focus wiring (correction 1 is enforced in the wiring, not only in the helper): `grep -n 'typingTargetElement(' $S/ComputerUseService.swift` prints exactly 2 lines, the `func typingTargetElement(` declaration and one call inside `typeText(app:text:context:)`; `awk '/func typeText\(.*context: ActionContext/{f=1} f && /typingTargetElement\(/{print "inside"} f && /^    }$/{f=0}' $S/ComputerUseService.swift` prints exactly `inside`.
  - No typing helper receives the pinned focus: `grep -c 'focusedElement: snapshot.focusedElement' $S/ComputerUseService.swift` prints `0`.
  - The phase 01 invariant still holds: `grep -c 'style: .actionResult' $S/ComputerUseService.swift` prints `1`, inside `finishAction` (same `awk` as phase 01 Task 1.5).
  - `swift build --product OpenComputerUseSmokeSuite 2>&1 | tail -5` exits 0 (the new smoke step compiles; it is run only in phase 08 L1).
- Commit with the exact subject above and report the SHA.

## Acceptance

Command: `cd $W && swift test --filter OpenComputerUseKitTests.BatchActionRunnerTests`, plus the full `swift test`.

Assertions (write first). Recorded closures replace live AX, and fake elements come from `AXUIElementCreateApplication(4_242/4_243)`, the pattern at `T/OpenComputerUseKitTests.swift:1230`.

- **Stop on first failure.** 4 steps, where `perform` throws at index 1:
  - outcomes are `[.ok, .failed(msg), .notRun, .notRun]`;
  - `perform` is invoked exactly twice;
  - `beforeEachStep` is invoked for indices `[0, 1]` only.
- **Lock mid-run.** `beforeEachStep` throws at index 1:
  - step 2 is `.failed(<lock text>)`, and `perform` is never invoked for index 1;
  - later steps are `.notRun`.
- **Per-step lines.** The exact strings for one example of each tool: `Step 1 click element_index=12: ok`, `Step 2 type_text: ok`, `Step 3 press_key key=Return: failed: boom`, `Step 4 click element_index=40: not run`. The `type_text` line does not contain the typed text.
- **Result shape.**
  - `result(report:, finalState: .success(<text "STATE">), notReadReason: nil)` has content[0] text equal to `stepLines.joined("\n") + "\n\nSTATE"`.
  - `isError == report.hasFailure`.
- **Final-snapshot failure keeps the step lines.** `finalState: .failure(err)` gives text that starts with the step lines and contains `Final state unavailable: `, with `isError == true`.
- **Final state skipped when locked.** `finalState: nil, notReadReason: "macOS is locked"` gives text that contains `Final state not read: macOS is locked`, with `isError == true`.
- **Index resolution against the pinned snapshot.** `unknownElementIndices(in: [click "12", setValue "99", pressKey], knownIndices: [12, 40])` → `["99"]`.
- **Recovery policy.**
  - `mostRestrictiveRecoveryPolicy` over `[click .auto, click .skyClick]` → `.readOnly`;
  - over `[click .auto, typeText]` → `.allowActivation`.
- **Focus is read live (advisor correction 1). This test must fail if a batch uses the pinned focus.** `typingTargetElement(context: .batchStep(pinned: <snapshot with focusedElement = app(4242)>), snapshotFocus: app(4242), liveFocus: { count += 1; return app(4243) })`:
  - returns an element `CFEqual` to `app(4243)`;
  - `count == 1`.
  - For `.single(includeScreenshot: false)`, it returns `app(4242)` and `count == 0`.
- **Live geometry, never pinned.**
  - `batchStepGeometry(pinnedWindowBounds: A, liveWindowBounds: B, liveLocalFrame: F, needsElementFrame: true, elementIndex: "3")` → `(B, F)`.
  - With `liveWindowBounds: nil` and pinned `A` → throws.
  - With `liveLocalFrame: nil` and `needsElementFrame: true` → throws, and the text contains `element_index 3 is no longer on screen`.
- **Upfront parse.** Each case below uses the unlocked dispatcher and the app `NoSuchApp`. The app does not exist, which proves parsing happens before any service work.
  - `actions: []` → error `actions must be an array of 1-10 steps`.
  - 11 steps → the same error.
  - `[{tool: "drag", args: {...}}]` → `step 1: tool 'drag' is not allowed in perform_actions`.
  - `[{tool: "press_key", args: {key: "a"}}, {tool: "type_text", args: {app: "X", text: "a"}}]` → `step 2: args must not contain "app"`.
  - `[{tool: "press_key", args: {}}]` → text starts with `step 1: `.
- **Parse success.** `parseBatchSteps` of `[{click, {element_index: "12"}}, {type_text, {text: "combio"}}, {press_key, {key: "Return"}}]` equals `[.click(elementIndex: "12", x: nil, y: nil, clickCount: 1, mouseButton: "left", clickMethod: .auto), .typeText(text: "combio"), .pressKey(key: "Return")]`.
- **Registration.**
  - `ToolDefinitions.all.last?.name == "perform_actions"`.
  - Its `inputSchema["required"] == ["app", "actions"]`.
  - `actions.maxItems == 10`.
  - The `items.properties.tool.enum` equals `ActionStep.allowedToolNames`.
- **Existing tests edited in Task 5.1.** The count is 10 and `guiTools` includes `perform_actions`. The locked dispatcher refuses it with `macOS is locked`.

## Live measurement M5 (main loop)

- `MEASURE(C5, <SHA>, extras: batch)` against C4. There must be no single-call regression: `M_server(C5) ≤ 1.05 × M_server(C4)`.
- `batch` must exit 0. It first runs one probe round `[cmd+option+f, type_text combio]` with **no Return** (recorded as warm-up): its guard requires `Step 2 type_text: ok` and calls `require_search_value` on the batch result, so a batch whose typing outran Mail's focus change aborts before any Return can open and mark a message read. Then it runs 10 rounds of `[cmd+option+f, type_text combio, Return]`; each round's guard checks `Step 3 press_key key=Return: ok` **and** calls `require_search_value` on the batch result (the search field holds `combio`). A step reported `ok` was only posted; the value check proves where the text landed. This is the live check for the implicit-settle risk.
- If the batch guard fails because steps outran Mail, apply the pre-authorized settle raise from phase 03 (at most 0.3s) before escalating.
- Record the median time of `perform_actions` against the sum of the three single calls' medians.

## Risks

| Risk | L×I | Mitigation |
|---|---|---|
| Steps outrun the app, because the old 1.3s implicit settle is gone (predict: high) | M×H | The inter-step `postActionSettleInterval` plus live focus. M5 batch guard, which checks where the text landed (probe round without Return, then `require_search_value` every round). If it fails, raise the shared constant within the pre-authorized range (phase 03, ≤ 0.3s); beyond that, use the Failure Protocol. |
| A stale pinned frame clicks the wrong element | M×H | Live target frame and window bounds; nearby hit-testing off in batches. Unit-tested by the geometry tests. |
| A batch holding the env-override lock serializes other hosts | L×L | At most 10 steps; documented in phase 07 |
| Track B rebase friction (dispatcher, ToolDefinitions, the MCPServer :10 line) | M×L | Append-only placement. The plan.md seam table goes to the main loop. |

## Rollback

`git revert <C5>`. This also reverts the count edits. Phase 07 must be reverted first if it has landed, because its docs name the tool. Phases 01–04 and 06 are unaffected.

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
