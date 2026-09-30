# Phase 05 — DecisionAdvisor, `decide_next_action` wiring, eval harness executable

Sequential. Depends on **04** (and transitively 01, 02). **Tests-first:** a tester agent writes `DecisionAdvisorTests.swift`
from the Acceptance list and confirms it fails. A different implementer agent (opus; this code is reachable from the
TCC-privileged app-agent) then writes the sources.
Worktree: `/Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/decision-model`.

## Goal

Compose phases 02 and 04 into one advisory call. Expose it as the read-only MCP tool `decide_next_action(app, goal)`, which
is listed and callable **only** when `OPEN_COMPUTER_USE_DECISION_MODEL_URL` is a valid loopback URL. Ship a dev-only
executable that replays captured snapshots through the exact same `DecisionAdvisor.advise` entry point, so phase 06
measures shipped code. Nothing in this phase actuates UI, and nothing spawns a process.

## Context (verified 2026-09-23, worktree @ 4ac1d5e)

- `tools/list` returns `ToolDefinitions.all` (`MCPServer.swift:79-85`). `initialize` returns the constant
  `computerUseServerInstructions` (`MCPServer.swift:3-20`, used at `:64`). tools/list and initialize bypass the dispatcher
  and the lock guard (`OpenComputerUseKitTests.swift:3151-3166`).
- In the app-agent, **every** MCP line (initialize, tools/list, and tools/call alike) is handled inside
  `AppAgentEnvironment.withOverrides(sanitizedPeerEnvironment(...))` (`MacOSAppAgentProxy.swift:405-414`). That function
  `setenv`s the peer's `OPEN_COMPUTER_USE_*` keys under a process-wide `NSLock` for the duration of `handle(line:)`
  and restores them afterwards (`:491-520`). The sanitizer passes every `OPEN_COMPUTER_USE_` key except the lock opt-in
  (`MacSessionGuard.swift:64-67`). So `ProcessInfo.processInfo.environment` read **inside** `handle(line:)` is the host's
  per-call value, and gating tools/list per call works without touching `apps/OpenComputerUse/**`.
- `StdioMCPServer` is constructed at `MacOSAppAgentProxy.swift:365` (`StdioMCPServer()`, one per socket connection) and
  `OpenComputerUseMain.swift:43` (`StdioMCPServer(service:)`, direct mode). It builds its dispatcher at `MCPServer.swift:24`.
  `ComputerUseToolDispatcher` is also constructed at `ComputerUseToolDispatcher.swift:310` (the CLI `call` path). All
  three keep compiling because only **defaulted** parameters are added.
- The dispatcher switch is at `ComputerUseToolDispatcher.swift:51-113`. `requireUnlocked(for:)` runs first (`:50`).
  `optionalBool`/`requireString` helpers are at `:130`, `:200`.
- `ComputerUseService` keeps a per-instance `snapshotsByApp` cache (`ComputerUseService.swift:450`). `getAppState`
  (`:462-472`) calls the private `refreshSnapshot(for:textLimit:treeLimits:recoveryPolicy:)` (`:849-874`). That is the
  call that makes later `element_index` values resolvable, so the decide path must go through it too.
  `snapshot.renderedText(style:)` exists for `.fullState` and `.compactActionable` (`AccessibilitySnapshot.swift:127`,
  `:304-309`).
- `readOnlyAnnotations()` and the schema helpers are `private` to `ToolDefinitions.swift` (`:180`), so the new definition
  must live in that file.
- `testToolDefinitionCount` asserts `ToolDefinitions.all.count == 9` (`OpenComputerUseKitTests.swift:255-257`). It must
  stay green: `all` keeps exactly the 9 base tools.
- The smoke suite asserts `tools.count == 9` (`apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift:199-201`)
  and passes the **whole inherited environment** to the server (`:348-352`). A user who exported the URL in their shell
  would get a false smoke failure, so this phase removes the key there.
- `FakeUnlockedSessionProvider` in the existing test file is `private` (`OpenComputerUseKitTests.swift:3680`). The new test
  file defines its own provider.
- `experiments/` already hosts dev-only executables declared in `Package.swift` (`CursorMotion`, `StandaloneCursor`,
  `Package.swift:27-34`, `:57-67`).
- The phase 04 transport throws `.transport` on the main thread. `DispatchQueue.sync` may run on the calling thread, so
  off-main execution must use `async` plus a semaphore.

## Signature

### New `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/DecisionAdvice.swift` (result types + JSON)
```swift
public struct DecisionOperationProbability: Equatable, Sendable {
    public let operation: DecisionOperation
    public let probability: Double
}

public struct DecisionTargetProbability: Equatable, Sendable {
    public let elementIndex: Int
    public let probability: Double
    public let rowText: String
}

public struct DecisionAdvice: Equatable, Sendable {
    public let operation: DecisionOperation
    /// Non-nil iff operation.needsTarget. Equals targetDistribution[0].elementIndex when non-nil.
    public let elementIndex: Int?
    public let operationMargin: Double            // top1 − top2 of operationDistribution
    public let targetMargin: Double               // top1 − top2 of targetDistribution (1.0 when one candidate)
    /// needsTarget ? min(operationMargin, targetMargin) : operationMargin
    public let margin: Double
    /// Exactly 7 entries in DecisionOperation.allCases order; sums to 1 ± 1e-9.
    public let operationDistribution: [DecisionOperationProbability]
    /// Every offered candidate exactly once, sorted by probability desc then elementIndex asc; sums to 1 ± 1e-9.
    public let targetDistribution: [DecisionTargetProbability]
    public let pagesQueried: Int                  // model calls made (1 for a single page; pages + 1 when paged)
    public let offeredCount: Int
    public let actionableCount: Int
    public let droppedByRule: [DecisionPruneRule: Int]
    public let latencyMilliseconds: Int
}

public extension DecisionAdvice {
    /// Tool result text. JSONSerialization with [.sortedKeys, .withoutEscapingSlashes]; probabilities and margins
    /// rounded to 4 decimals. Keys (exact): advisory(true), experimental(true), operation (raw value),
    /// element_index (int or null), margin, operation_margin, target_margin, recommended_min_margin,
    /// chosen_row_text (string or null — rowText of targetDistribution[0] when elementIndex != nil),
    /// operation_distribution [{operation, probability}] (7),
    /// target_distribution [{element_index, probability[, row_text]}] (row_text only on the first 3 entries),
    /// candidates {offered, actionable, pages_queried, dropped {<rule raw value>: count, only non-zero}},
    /// latency_ms, note (== DecisionAdvisor.resultNote).
    func resultJSON(recommendedMinMargin: Double) throws -> String
}
```

### New `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/DecisionAdvisor.swift`
```swift
public enum DecisionAdvisorError: Error, Equatable, LocalizedError {
    case disabled                 // env key absent
    case emptyGoal
    case noCandidates             // offeredIndices is empty after pruning
    case deadlineExceeded
}

public enum DecisionAdvisor {
    /// Smallest margin at which the offline eval measured >= 90% precision; 1.0 means "never auto-follow".
    /// Set from scripts/decision-model/eval-data/summary.json. Start value here: 1.0.
    public static let recommendedMinMargin: Double
    public static let overallDeadline: TimeInterval          // 12
    /// One-line reminder embedded in every result.
    public static let resultNote: String
    /// Host-side cascade guide. Appended to the MCP `initialize` instructions only when the tool is enabled.
    /// skills/open-computer-use/references/decision-model.md carries the same text verbatim.
    public static let cascadeGuide: String

    public static func advise(
        goal: String,
        appName: String,
        renderedFull: String,
        renderedCompact: String,
        client: DecisionModelClient,
        maxPages: Int = DecisionCandidateBuilder.defaultMaxPages,
        now: () -> Date = Date.init
    ) throws -> DecisionAdvice
}
```
`cascadeGuide` text (exact, a single string with `\n` line breaks):
```
decide_next_action (experimental, advisory): a local model proposes the next operation and target from the current app state. It never acts.
- Follow the advice only when margin >= recommended_min_margin AND the operation is non-destructive (not send, delete, purchase, submit, sign in/out, or anything externally visible) AND chosen_row_text matches your intent.
- Otherwise call get_app_state and decide yourself. Low margin means the model is unsure.
- Pass your own sub-goal in plain words. Never paste screen text into goal.
- element_index values are valid for the next click, set_value, or scroll on the same app, exactly like get_app_state.
```
`resultNote` = `"Advisory only; the server never acts. Follow only when margin >= recommended_min_margin and the operation is non-destructive; otherwise call get_app_state and decide yourself."`

**Normative `advise` algorithm:**
1. `goal` trimmed empty → `.emptyGoal`. `start = now()`.
2. `set = DecisionCandidateBuilder.build(goal:renderedFull:renderedCompact:maxPages:)`. `set.offeredIndices` empty → `.noCandidates`.
3. Before **each** model call: `now().timeIntervalSince(start) > overallDeadline` → `.deadlineExceeded`.
4. **One page:** `r = client.readout(goal:appName:page:)`. Operation distribution = `r.operation`. Target probability of
   the candidate with label L = `r.target.probabilities[L]`.
5. **k > 1 pages:** call each page in page order (`r_p`). Winner `w_p` = the candidate labelled `r_p.target.chosenLabel`.
   Stage-2 page = `DecisionCandidatePage(labels: Array(labelAlphabet.prefix(k)), candidates: winners sorted by ascending elementIndex)`.
   `r2 = client.readout(goal:appName:page: stage2)`. Operation distribution = `r2.operation`. Combined target
   probability of candidate c on page p = `P2(w_p) × P1_p(c)`.
6. Chosen target = argmax of the target distribution (ties → lower elementIndex). `elementIndex` = chosen iff the argmax
   operation `needsTarget`, else nil. Chosen operation = argmax of the operation distribution (ties → allCases order).
7. `latencyMilliseconds` = `Int((now() − start) × 1000)`. `droppedByRule` counts `set.dropped` values.

### Changed `ToolDefinitions.swift` (additive; `all` is unchanged)
```swift
public extension ToolDefinitions {      // declared inside ToolDefinitions.swift so private helpers are reachable
    static let decideNextAction: ToolDefinition
        // name "decide_next_action"; annotations readOnlyAnnotations(); inputSchema objectSchema(
        //   properties: ["app": string "App name or bundle identifier",
        //                "goal": string "Your current sub-goal in plain words. Never paste screen text here."],
        //   required: ["app", "goal"])  (additionalProperties false via objectSchema)
        // description starts "Experimental, read-only advisor." and states: returns operation, element_index, margin and
        // full distributions; never performs an action; available only when OPEN_COMPUTER_USE_DECISION_MODEL_URL is set.
    /// all + [decideNextAction] iff DecisionModelEndpoint.fromEnvironment(environment) returns non-nil without throwing.
    static func listed(environment: [String: String]) -> [ToolDefinition]
}
```

### Changed `MCPServer.swift`
Old: `public init(service: ComputerUseService = ComputerUseService())`; the `computerUseServerInstructions` constant is
used directly, and tools/list maps `ToolDefinitions.all`.
New:
```swift
public init(
    service: ComputerUseService = ComputerUseService(),
    environment: @escaping @Sendable () -> [String: String] = { ProcessInfo.processInfo.environment }
)
func computerUseServerInstructions(environment: [String: String]) -> String
    // == the existing constant byte-for-byte when the tool is not listed; else constant + "\n\n" + DecisionAdvisor.cascadeGuide
```
The `let` constant keeps its text but is renamed `baseComputerUseServerInstructions`. initialize uses the function.
tools/list uses `ToolDefinitions.listed(environment: environment())`. The dispatcher is built as
`ComputerUseToolDispatcher(service: service, environment: environment)`. Callers `MacOSAppAgentProxy.swift:365` and
`OpenComputerUseMain.swift:43` are unchanged, because the parameter is defaulted.

### Changed `ComputerUseToolDispatcher.swift`
Old: `public init(service: ComputerUseService = ComputerUseService(), guard macSessionGuard: MacSessionGuard = MacSessionGuard())`
New: the same, plus a trailing `environment: @escaping @Sendable () -> [String: String] = { ProcessInfo.processInfo.environment }`.
Caller `:310` is unchanged. New switch case, placed after `get_app_state`:
```swift
case "decide_next_action":
    return try service.decideNextAction(
        app: requireString("app", in: arguments),
        goal: requireString("goal", in: arguments),
        environment: environment()
    )
```
(The existing lock guard at `:50` applies unchanged: this call reads AX.)

### Changed `ComputerUseService.swift` (one new public method, placed after `getAppState`)
```swift
public func decideNextAction(
    app query: String,
    goal: String,
    environment: [String: String],
    transport: DecisionModelTransport = URLSessionDecisionModelTransport()
) throws -> ToolCallResult
```
Order (normative; each step happens before any later step's side effects):
1. `DecisionModelEndpoint.fromEnvironment(environment)`. nil → `throw ComputerUseError.stateUnavailable(DecisionAdvisorError.disabled.errorDescription!)`,
   where the text names the env key and `scripts/decision-model/start-sidecar.sh`. A thrown `DecisionModelError` →
   `ComputerUseError.invalidArguments("OPEN_COMPUTER_USE_DECISION_MODEL_URL: <description>")`.
   **No AX and no network before this step.**
2. `goal` trimmed empty → `ComputerUseError.invalidArguments("goal must not be empty")`.
3. `let snapshot = try refreshSnapshot(for: query)` (defaults, the same as a default `get_app_state`, so the eval captures
   match).
4. Run `DecisionAdvisor.advise(goal:appName: snapshot.app.name, renderedFull: snapshot.renderedText(style: .fullState), renderedCompact: snapshot.renderedText(style: .compactActionable), client: DecisionModelClient(endpoint:transport:))`
   **off the main thread**: if `Thread.isMainThread`, run it via `DispatchQueue.global(qos: .userInitiated).async`
   plus a `DispatchSemaphore` wait. Never use `.sync`.
5. `DecisionAdvisorError` / `DecisionModelError` → `ComputerUseError.message("decide_next_action: <description>")`.
   Success → `ToolCallResult.text(advice.resultJSON(recommendedMinMargin: DecisionAdvisor.recommendedMinMargin))`.

### Changed `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
`smokeServerEnvironment()` (`:348-352`) additionally does
`environment.removeValue(forKey: "OPEN_COMPUTER_USE_DECISION_MODEL_URL")`. The count assertion at `:199` stays `== 9`.

### New dev-only executable `experiments/DecisionModelEval/Sources/DecisionModelEval/main.swift`
`Package.swift`: add product `.executable(name: "DecisionModelEval", targets: ["DecisionModelEval"])` and target
`.executableTarget(name: "DecisionModelEval", dependencies: ["OpenComputerUseKit"], path: "experiments/DecisionModelEval/Sources/DecisionModelEval")`.
CLI contract:
```
swift run DecisionModelEval (--prune-only | --url http://127.0.0.1:<port>)
  stdin : JSONL, one object per line: {"id": str, "goal": str, "app": str, "renderedFull": str, "renderedCompact": str}
  stdout: JSONL, one object per input line, same order:
          {"id", "offered_indices": [int], "dropped": {"<index>": "<rule>"}, "actionable_count": int,
           "advice": <parsed resultJSON object> | null, "error": str | null, "wall_ms": int}
  --prune-only: DecisionCandidateBuilder.build only; advice null; no network.
  --url: endpoint via DecisionModelEndpoint.fromEnvironment([environmentKey: url]) (same loopback enforcement);
         transport URLSessionDecisionModelTransport; DecisionAdvisor.advise per line.
  All work runs on a background Thread; the main thread only waits (semaphore). Exit 0 unless stdin is not JSONL (exit 2)
  or the URL is rejected (exit 3). Per-item model errors go in "error" and do not abort the run.
  No AX, no AppKit, no file writes.
```

Code comments, test names, and commit messages describe invariants and behaviour only. They never carry plan names,
phase numbers, or audit labels. Phase 06 is the only later phase allowed to change `recommendedMinMargin`, and it
changes only that literal.

## Boundaries

```
TARGET:    packages/OpenComputerUseKit/Sources/OpenComputerUseKit/DecisionAdvice.swift                 (new)
           packages/OpenComputerUseKit/Sources/OpenComputerUseKit/DecisionAdvisor.swift                (new)
           packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ToolDefinitions.swift                (additive)
           packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MCPServer.swift                      (see Signature)
           packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseToolDispatcher.swift      (init param + 1 case)
           packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift             (1 new method)
           packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/DecisionAdvisorTests.swift        (new)
           apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift                (1 line)
           experiments/DecisionModelEval/Sources/DecisionModelEval/main.swift                          (new)
           Package.swift                                                                               (1 product + 1 target)
READ-ONLY: DecisionCandidates.swift (02), DecisionPrompt.swift + DecisionModelClient.swift (04), MacSessionGuard.swift,
           apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift, OpenComputerUseKitTests.swift
FORBIDDEN: AccessibilitySnapshot.swift; DecisionCandidates.swift, DecisionPrompt.swift, DecisionModelClient.swift and their
           tests (a needed change there is a STOP → Failure Protocol, never a quiet edit);
           apps/OpenComputerUse/** (proxy/agent env plumbing already works; do not touch the sanitizer or withOverrides);
           OpenComputerUseKitTests.swift (testToolDefinitionCount must stay `== 9` untouched);
           adding decide_next_action to ToolDefinitions.all; any actuation (click/type/press) from the decide path;
           spawning llama-server or any Process from Swift; any file under scripts/** (phases 01/03/06);
           apps/OpenComputerUseLinux/**, apps/OpenComputerUseWindows/** (non-goal); docs/** and skills/** (phase 07);
           any new third-party dependency
```

## Steps

1. The tester writes `DecisionAdvisorTests.swift` (assertions below), then runs `swift test --filter DecisionAdvisorTests`,
   which must fail to compile or fail. They commit nothing yet.
2. The implementer writes `DecisionAdvice.swift` and `DecisionAdvisor.swift` until the advisor assertions pass.
3. Wire `ToolDefinitions`, `MCPServer`, the dispatcher, and the service until the wiring assertions pass.
4. Smoke-suite env line; `Package.swift` + `DecisionModelEval`.
5. Run the full acceptance. Commit with explicit `git add <TARGET paths>`.

## Acceptance

Command: `swift test --filter DecisionAdvisorTests`, then `swift test` (the whole suite, including `testToolDefinitionCount`,
stays green), then `swift build --product DecisionModelEval` and `swift build --product OpenComputerUseSmokeSuite`.

Assertions (write first; they must fail before the sources exist). Test helpers inside the test file:
`ScriptedTransport: DecisionModelTransport` records every `(url, body)` and answers each request by reading the labels
out of the request's `grammar` and returning a synthetic `/completion` JSON built from per-call scripted logprob maps.
`makeCompletion(op: [String: Double], target: [String: Double])` builds the same `completion_probabilities` shape as
the pin (`scripts/decision-model/fixtures/readout-pin.json`). There is also a local `UnlockedProvider: MacSessionStateProvider`.

Advisor:
- Single page (5 candidates), scripted op `{" A": -0.05, " B": -3}`, target favouring the row `button Save`: `operation == .click`;
  `elementIndex` == the Save row's index; `pagesQueried == 1`; the transport saw exactly 1 request; operation
  distribution has 7 entries in allCases order summing to 1 ± 1e-9; target distribution has 5 entries sorted desc, summing
  to 1 ± 1e-9; `margin == min(operationMargin, targetMargin)`.
- Non-targeted op (scripted `" E"` = press_key argmax) → `elementIndex == nil`, `margin == operationMargin`, and the
  target distribution is still complete.
- Paging: 120 synthetic rows (reuse phase 02's 120-row shape) → 3 pages + 1 stage-2 call = 4 requests; `pagesQueried == 4`;
  the stage-2 request grammar has exactly 3 target labels (`" A" | " B" | " C"`); target distribution has 120 entries,
  sums to 1 ± 1e-9, and its argmax equals the product rule's argmax computed independently in the test.
- Empty goal → `.emptyGoal` with 0 requests. Compact text with no actionable rows → `.noCandidates` with 0 requests.
- Deadline: a `now` closure that advances 13 s per call → `.deadlineExceeded` before the second request.
- `resultJSON` round-trips through `JSONSerialization`: the top-level key set equals exactly the 14 keys listed in the
  Signature; `advisory == true`; `experimental == true`; `recommended_min_margin` equals the argument; only the first 3
  `target_distribution` entries carry `row_text`; `candidates.dropped` omits zero counts; all probabilities have ≤ 4 decimals.

Wiring (no AX, no network — the app name used is `"NoSuchApp-decision-test"`):
- `ToolDefinitions.all.count == 9` and `!all.contains { $0.name == "decide_next_action" }`.
- `listed(environment: [:])` names == `all` names; `listed(["OPEN_COMPUTER_USE_DECISION_MODEL_URL": "http://127.0.0.1:39501"])`
  has 10 entries, the last is `decide_next_action` with `readOnlyHint == true` and `required == ["app","goal"]`;
  `listed(url: "http://10.0.0.1:1")` has 9 entries (an invalid URL does not list the tool).
- `StdioMCPServer(service:environment: { [:] })`: the tools/list response contains no `decide_next_action`; the initialize
  `instructions` equal `baseComputerUseServerInstructions` byte-for-byte.
- `StdioMCPServer(... environment: { [key: "http://127.0.0.1:39501"] })`: tools/list contains `decide_next_action`; the
  instructions end with `DecisionAdvisor.cascadeGuide`.
- Dispatcher with `UnlockedProvider` and environment `[:]`: `callTool("decide_next_action", {app: NoSuchApp…, goal: "x"})`
  throws a `ComputerUseError` whose description contains `OPEN_COMPUTER_USE_DECISION_MODEL_URL` and **not** `appNotFound`.
  This proves the env check precedes app resolution.
- Same with the URL `http://10.0.0.1:1` → the description contains `OPEN_COMPUTER_USE_DECISION_MODEL_URL` and not `appNotFound`.
- Same with a loopback URL and goal `"   "` → the description contains `goal must not be empty`.
- Same with a loopback URL and a valid goal → the description contains `appNotFound`. Resolution is reached; no network
  happens because resolution fails first.
- The existing `testToolDefinitionCount`, `testMCPServerStillHandlesInitializeWhenLocked`, and the whole 233+ baseline
  pass unchanged.

Harness (exact commands, from the worktree root):
```
printf '%s\n' "$(node -e 'const s=require("./scripts/decision-model/eval-data/fixture-snapshots/fixture-01.json");console.log(JSON.stringify({id:"t1",goal:"increment the counter",app:s.app,renderedFull:s.renderedFull,renderedCompact:s.renderedCompact}))')" \
  | swift run DecisionModelEval --prune-only
# exit 0; exactly one JSON line; offered_indices non-empty; advice null; error null
echo '{"id":"t2","goal":"x","app":"A","renderedFull":"","renderedCompact":""}' | swift run DecisionModelEval --url http://10.0.0.1:1 ; test $? -eq 3
```
(If phase 03's fixture snapshot does not exist yet, the executor uses a synthetic compact string instead. It records that
in the report and does not fabricate a fixture file.)

Live listing check (best-effort; a known environment limitation is recorded, not worked around):
```
swift build --product OpenComputerUse
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","clientInfo":{"name":"t","version":"0"},"capabilities":{}}}' '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
  | env OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY=1 OPEN_COMPUTER_USE_DECISION_MODEL_URL=http://127.0.0.1:39501 .build/debug/OpenComputerUse mcp | grep -c decide_next_action   # ≥ 1
```
If the binary exits 141 or produces no output, record "debug binary not runnable from an agent session (known)" in the
report. The `StdioMCPServer` unit tests above cover the same code path. The real decide call on a deployed app is a
handover step in phase 07, not a gate here.

## Success criteria

All assertions pass; the full `swift test` is green with the same pre-existing count plus the new tests; both products build.
`git diff --stat` touches only TARGET. Each new source file is ≤ 300 lines. The edits to `ComputerUseService.swift` are
≤ 40 lines, and to `ToolDefinitions.swift` ≤ 40.

## Risks and rollback

- Holding the env-override lock during HTTP: every call from a host with any `OPEN_COMPUTER_USE_*` override already
  serializes on `AppAgentEnvironment.lock` (`MacOSAppAgentProxy.swift:492-499`). A decide call extends that by ≤ 12 s.
  Accepted and documented in phase 07. Do not "fix" it here, because the file is FORBIDDEN.
- Rollback: `git revert` this phase's commit. The server returns to 9 tools with no network path, and phases 02/04's files
  become unused but harmless.

## Contract Rules

1. Implements to the SIGNATURE exactly. A signature that cannot work is a STOP, not a redesign — report it through the Failure Protocol.
2. Edits only within TARGET. Discovering that the change genuinely requires a FORBIDDEN file is a STOP with that finding, never a quiet widening.
3. Writes the acceptance assertions first where the plan says tests-first, confirms they FAIL, then implements until they pass.
4. Never weakens an assertion, never marks a test skipped, and never stubs an implementation to make one pass. A passing suite obtained this way is the specific failure this whole contract is built to prevent — cheap tiers reward-hack checkable specs more than strong ones do, so the escalation path exists precisely for the moment the spec looks unsatisfiable.
5. On any failed Verify, follows the `## Failure Protocol` already in the phase file. That is the backchannel; using it is correct behaviour, not an admission of failure.

## Failure Protocol

On any failed Verify or Acceptance step (non-zero exit, failed assertion, or output that differs from what is specified
here), the executor stops reasoning about the fix on its own. It spawns the `kongming` agent with: this phase file's path,
the exact failing command and its full output, `git diff -- <TARGET files>`, and the approaches already tried. It waits
for the advice, applies it within TARGET only, and re-runs the failed step. If `kongming` is unavailable, or its advice
needs a FORBIDDEN file or a changed Signature, the executor STOPS and reports `Status: BLOCKED` with the evidence. It never
silently retries the same approach and never weakens an assertion to get green.
