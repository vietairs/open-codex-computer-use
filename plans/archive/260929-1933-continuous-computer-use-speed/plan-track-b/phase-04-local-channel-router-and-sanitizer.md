# Phase 04: local channel router, tool handlers, sanitizer strip

Depends on: phases 01, 02, 03. Blocks: 06, 07. Parallel group G3 (alone). Risk: High (this is the gate between the
host and a code-execution surface; a passthrough bug breaks every MCP call). Effort 5h.

## Execution constants

- `WT=/Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/fast-macos-channels`; run as `cd "$WT" && ...`.
- Test hygiene (binding): no plan ids in names/comments/commits; range-check before subscripting; tests never read or
  write stdin/stdout of the test process (use `run(input:output:forward:)`); tests inject `MacSessionGuard` with a
  file-private fake provider (the existing `FakeUnlockedSessionProvider` at `T/OpenComputerUseKitTests.swift:3680` is
  `private`, so declare your own in the new test file); tests inject a temp-dir `ScriptAuditLog`; the only real child
  processes allowed are `/usr/bin/osascript` with scripts that send no Apple Events, and temp executable scripts.
- Roles: tester writes Task 4.1; a different implementer does Task 4.2 and never edits tests.

## Verified source facts

- `proxyMCP` is a strict serial loop, one line in, at most one line out; it drops a missing/`NSNull` response
  (`apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift:121-137`, agent side `:420-423`).
- `StdioMCPServer.handle` returns nil for notifications (`K/MCPServer.swift:100-109`, `:128-129`); `run()` skips blank
  lines (`:46-54`). The router loop must copy both behaviours.
- The dispatcher's lock guard runs before the switch (`K/ComputerUseToolDispatcher.swift:61`), the unknown-tool error
  comes at `:128-129` as `unsupportedTool` (`K/Errors.swift:7,17-18`). Refusal tests therefore need an UNLOCKED guard.
- `MacSessionLockPolicy.sanitizePeerEnvironment` (the owner is the `MacSessionLockPolicy` enum, `K/MacSessionGuard.swift:47`,
  not `MacSessionGuard`) keeps every `OPEN_COMPUTER_USE_*` key except the lock opt-in (`K/MacSessionGuard.swift:64-68`);
  it has exactly two callers, proxy `MacOSAppAgentProxy.swift:157` and agent `:454`. Both pick up the new clause.
- The "Avoid falling back to AppleScript" line is `K/MCPServer.swift:16`, inside `baseComputerUseServerInstructions`.
- Encoding convention: `JSONSerialization.data(withJSONObject:options: [.withoutEscapingSlashes])` (`K/MCPServer.swift:178`).

## Task 4.1 (tester): failing tests first

- Goal: `T/LocalChannelRouterTests.swift` covering routing, passthrough, patching, handlers, fail-closed agent paths and
  the sanitizer.
- Verify (RED is the pass condition): `cd "$WT" && swift build --build-tests 2>&1 | tail -40` exits non-zero and the
  output contains `error:` and `LocalChannelRouter`.

## Task 4.2 (implementer): make them pass

- Target files: new `K/LocalChannelGuidance.swift`, `K/LocalChannelToolHandlers.swift`, `K/LocalChannelRouter.swift`;
  edit `K/MacSessionGuard.swift` (`sanitizePeerEnvironment`, :64-68, plus its doc comment).
- Steps:
  1. `LocalChannelGuidance.swift`: `appleScriptAvoidanceInstructionLine` must equal `K/MCPServer.swift:16` byte-for-byte:
     `Avoid falling back to AppleScript during a computer use session. Prefer Computer Use tools as much as possible to complete tasks.`
     `scriptFirstInstructionGuide` (replaces that line when enabled) says, in order: when the app's scripting dictionary
     covers the task, prefer `run_script` (check terms with `get_scripting_dictionary`); the turn-start
     `get_app_state` that the instructions above require applies to UI work, and a turn that only uses `run_script`
     skips it; for UI work, after that turn-start `get_app_state`, use `find_elements` plus element-targeted actions;
     after a script changed the UI, use `find_elements` to locate the control you need next rather than re-reading the
     whole tree; call `get_app_state` again only when neither fits or to verify; keep queries small
     (one mailbox, first N results) because a timed-out script keeps running inside the target app; scripts act without
     the visible cursor, so ask the user before sending, deleting or purchasing; script text is logged and the
     shell-verb filter is not a security boundary.
  2. `LocalChannelPolicy.isEnabled`: trim + lowercase value of `environmentKey` in {`1`, `true`, `yes`, `on`}.
  3. `LocalChannelToolDefinitions.all`: five `ToolDefinition`s in this order: `run_script` {app*, source*, language enum
     [applescript, javascript], timeout_s integer 1-60}; `get_scripting_dictionary` {app*, term}; `open_url` {url*};
     `run_shortcut` {name*, input, timeout_s}; `list_shortcuts` {}. `additionalProperties: false`. Annotations:
     run_script/open_url/run_shortcut `destructiveHint: true, openWorldHint: true`; the other two
     `readOnlyHint: true, idempotentHint: true, destructiveHint: false, openWorldHint: false`. Descriptions end with
     `This tool is part of plugin \`Computer Use\`.` and `run_script`'s says it is opt-in and logged.
  4. `LocalChannelToolHandlers.call(name:arguments:)` never throws; every failure becomes `ToolCallResult.text(_, isError: true)`.
     Decision 8 says every script text is logged, so the three audited tools (`run_script`, `open_url`, `run_shortcut`)
     write the `.request` entry BEFORE any other check that could reject the call; the two read-only tools start with
     the lock guard.
     - `get_scripting_dictionary`, `list_shortcuts`, unknown names: first `guard.requireUnlocked(for: name)`.
     - `run_script`, in this order:
       1. Read `source` (string, non-empty) and `app` (string, may be empty). Missing or empty `source` -> error; nothing
          to log.
       2. Audit `.request` with the full source and `target_app = app`. If `record` throws -> error
          `script audit log unavailable: <reason>; refusing to run unlogged scripts.` and nothing else runs.
       3. `guard.requireUnlocked(for: name)`; on a throw, audit `.result` with outcome `rejected:locked` and return the
          lock message.
       4. Validate the rest (app non-empty, language default applescript, timeout_s optional 1...60); on failure audit
          `.result` with outcome `rejected:invalid-arguments` and return the validation error.
       5. Filter: `.rejected(p)` -> audit `.result` with outcome `rejected:filter:<p>`, return error `run_script rejected
          by the script policy filter (matched "<p>"). The filter is best-effort friction, not a security boundary.`
          and nothing runs.
       6. Timeout = `OsascriptChildRunner.effectiveTimeout(requested:isFirstContactWithTarget:firstContactFloor:)` with
          `contactedTargets` (lowercased app) and the `firstContactMinimumTimeout` from init as the floor. Run. Audit
          `.result` (payload nil, sha, exit, duration, outcome `ok|error <n>|timeout`).
       A `.result` audit failure (any of steps 3-6) is written to stderr but does not change the returned result. Insert the app into
       `contactedTargets` unless the outcome was -1743 or a timeout. Success text: `resultText` then a blank line and
       `[run_script exit=0 duration_ms=<n> truncated=<bool>]`. Error text: `userFacingMessage` if any, else
       `errorMessage`, plus the same bracket line; timeout text names the timeout and the "keeps running in the app" caveat.
     - `get_scripting_dictionary`: `locateAppBundle(app)` nil -> error `app not found`; else `lookup.summary`.
     - `open_url`: read `url` (non-empty string) -> audit request (payload = url) -> refuse on audit failure -> guard ->
       `launcher.openURL` -> audit result (`ok`, `rejected:<reason>`, `rejected:locked` or `error`).
     - `run_shortcut`: read `name` -> audit request (payload = name + "\n" + input) -> refuse on audit failure -> guard
       -> run -> audit result.
     - `list_shortcuts`: `launcher.listShortcuts(timeout: 20)`.
     - Unknown name -> error `unsupported local tool`.
  5. `LocalChannelRouter.route(line:forward:)`:
     - Disabled: `return try forward(line)`. No parsing at all.
     - Enabled: parse; if not a JSON object -> `forward(line)` unchanged (batch arrays pass through).
     - `tools/call` with `params.name` in `LocalChannelToolNames.all` -> handlers, encode `{jsonrpc, id, result}`; never
       call `forward`.
     - `initialize` -> forward, then in `result.instructions` replace `appleScriptAvoidanceInstructionLine` with
       `scriptFirstInstructionGuide`; if the line is absent, append `"\n\n" + guide`. If the forwarded response is nil
       or unparsable, return it unchanged.
     - `tools/list` -> forward, append `LocalChannelToolDefinitions.all.map(\.asDictionary)` to `result.tools`.
     - Anything else -> `forward(line)`.
     - Re-encode patched responses with `[.withoutEscapingSlashes]`.
     - Error handling: an error thrown by `forward` propagates unchanged (the existing relay behaviour when the agent
       socket fails). Nothing on the local side may propagate: a local `tools/call` whose `arguments` is missing or not
       an object is passed to the handlers as `[:]` (they return an `isError` result); any error while encoding a local
       result becomes the JSON-RPC error `{"jsonrpc":"2.0","id":<id>,"error":{"code":-32603,"message":"<text>"}}`. A
       local `tools/call` without an `id` produces no output. For `initialize` / `tools/list`, a forwarded response that
       is nil, unparsable, an `error` response, or lacks `result.instructions` (string) / `result.tools` (array) is
       returned unchanged.
  6. `run(input:output:forward:)`: loop `while let line = input()`, skip whitespace-only lines, write `response + "\n"`
     only when non-nil. `run(forward:)` = the same with `readLine(strippingNewline: true)` and
     `FileHandle.standardOutput.write`.
  7. Handlers are built lazily on the first local call, so a disabled router never creates the log directory.
  8. `MacSessionGuard.swift`, `MacSessionLockPolicy.sanitizePeerEnvironment`: filter becomes
     `key.hasPrefix("OPEN_COMPUTER_USE_") && key != environmentKey && key != LocalChannelPolicy.environmentKey`; extend
     the doc comment: the scripting opt-in is read only by the relay from its own launch environment and never crosses
     the socket.
- Verify:
  1. `cd "$WT" && swift test --filter LocalChannelRouterTests 2>&1 | tail -30` exits 0 and prints `with 0 failures`.
  2. `cd "$WT" && swift build && swift test 2>&1 | tail -15` exits 0 and prints `with 0 failures`.

## Signature

```swift
// K/LocalChannelGuidance.swift
let appleScriptAvoidanceInstructionLine: String
let scriptFirstInstructionGuide: String

// K/LocalChannelToolHandlers.swift
public enum LocalChannelPolicy {
    public static let environmentKey: String   // "OPEN_COMPUTER_USE_ENABLE_SCRIPTING"
    public static func isEnabled(environment: [String: String]) -> Bool
}

public enum LocalChannelToolNames {
    public static let runScript: String               // "run_script"
    public static let getScriptingDictionary: String  // "get_scripting_dictionary"
    public static let openURL: String                 // "open_url"
    public static let runShortcut: String             // "run_shortcut"
    public static let listShortcuts: String           // "list_shortcuts"
    public static let all: Set<String>
}

public enum LocalChannelToolDefinitions {
    public static let all: [ToolDefinition]           // 5, order above
}

public final class LocalChannelToolHandlers {
    public init(
        environment: [String: String],
        guard macSessionGuard: MacSessionGuard = MacSessionGuard(),
        auditLog: ScriptAuditLog = ScriptAuditLog(),
        scriptRunner: OsascriptChildRunner? = nil,          // nil -> OsascriptChildRunner(baseEnvironment: environment)
        dictionaryLookup: ScriptingDictionaryLookup = ScriptingDictionaryLookup(),
        launcher: ShortcutAndUrlLauncher? = nil,            // nil -> ShortcutAndUrlLauncher(baseEnvironment: environment)
        locateAppBundle: @escaping (String) -> URL? = ScriptingDictionaryLookup.locateAppBundle,
        firstContactMinimumTimeout: TimeInterval = OsascriptChildRunner.firstContactMinimumTimeout
    )
    public func call(name: String, arguments: [String: Any]) -> ToolCallResult
}

// K/LocalChannelRouter.swift
public final class LocalChannelRouter {
    public typealias Forward = (String) throws -> String?
    public let isEnabled: Bool
    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        makeHandlers: (() -> LocalChannelToolHandlers)? = nil   // nil -> LocalChannelToolHandlers(environment: environment)
    )
    public func route(line: String, forward: Forward) throws -> String?
    public func run(input: () -> String?, output: (String) -> Void, forward: Forward) throws
    public func run(forward: Forward) throws
}

// K/MacSessionGuard.swift (existing; body-only change)
public enum MacSessionLockPolicy {
    public static func sanitizePeerEnvironment(_ environment: [String: String]) -> [String: String]
}
```

## Boundaries

```
TARGET:    K/LocalChannelGuidance.swift, K/LocalChannelToolHandlers.swift, K/LocalChannelRouter.swift,
           K/MacSessionGuard.swift (sanitizePeerEnvironment only), T/LocalChannelRouterTests.swift
READ-ONLY: K/MCPServer.swift, K/ToolDefinitions.swift, K/ComputerUseToolDispatcher.swift, K/ToolResult.swift,
           phase 01-03 sources, apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift
FORBIDDEN: adding any local tool to ToolDefinitions.all/listed or a case to ComputerUseToolDispatcher (that would put
           script execution in the agent); editing K/MCPServer.swift (phase 07 owns it); editing
           K/OpenComputerUseCLI.swift (amendment 3: CLI fails closed already); linking the router into StdioMCPServer;
           reading the flag from a per-call/peer environment; editing app-target files (phase 06);
           editing T/OpenComputerUseKitTests.swift or T/DecisionAdvisorTests.swift (phase 05 owns count sites)
```

## Acceptance

Command: `cd "$WT" && swift test --filter LocalChannelRouterTests`
Assertions (write first; must fail before, pass after):

Flag unset (T1)
- `testFlagUnsetRouterIsBytePassthrough`: for an `initialize`, `tools/list`, `tools/call run_script`, a notification
  and a batch array line, `route` returns exactly the string the fake `forward` returned; `forward` received the
  identical line exactly once per call.
- `testFlagUnsetInitializeKeepsAppleScriptLine`: `StdioMCPServer(service:environment: { [LocalChannelPolicy.environmentKey: "1"] })`
  `initialize` instructions contain `appleScriptAvoidanceInstructionLine` (the agent never patches), and
  `baseComputerUseServerInstructions.contains(appleScriptAvoidanceInstructionLine)`.
- `testFlagValuesParse`: `1`, `true`, ` YES `, `on` enable; `0`, `false`, ``, `nonsense`, absent do not.

Flag set
- `testToolsListAppendsFiveLocalTools`: forwarded list of 2 tools -> response has 7, last five names in order.
- `testInitializeSwapsAppleScriptLineForGuide`: forwarded instructions = base text -> patched text lacks the AppleScript
  line, contains `scriptFirstInstructionGuide` in full (not only a phrase the base text already has, such as
  `Ask the user before`), and everything before/after the swapped line is unchanged.
- `testLocalToolsAreNeverForwarded`: `forward` calls `XCTFail` and returns nil; `makeHandlers` is injected with a
  temp-dir audit log, a marker `scriptRunner`, and a launcher whose `shortcutsExecutablePath` is a temp marker script and
  whose `opener` records calls (no real `/usr/bin/shortcuts`, no `NSWorkspace`); `tools/call` for each of the 5 names
  yields a JSON-RPC result with the request id.
- `testCaseVariantToolNameIsForwarded`: `tools/call` with `params.name == "Run_Script"` -> `forward` receives the
  identical line once and the handlers are never built.
- `testForwardedErrorResponsesPassThroughUntouched`: for `initialize` and `tools/list`, a forwarded
  `{"jsonrpc":"2.0","id":1,"error":{...}}` and a forwarded result without `instructions` / `tools` come back
  byte-identical.
- `testMalformedLocalCallBecomesToolError`: `tools/call run_script` with `arguments: "x"` (not an object) and with no
  `arguments` -> a JSON-RPC `result` with `isError: true` and the request id; `route` does not throw.
- `testLocalCallWithoutIdProducesNoOutput`: `tools/call list_shortcuts` without `id` through `run(input:output:forward:)`
  writes nothing and does not throw.
- `testBatchArrayIsForwardedUntouched`: a batch containing a run_script call is forwarded byte-identical.
- `testNotificationProducesNoOutput`: `run(input:output:forward:)` with a blank line and a notification whose forward
  returns nil writes nothing.
- `testFilterRejectionIsLoggedAndNeverSpawns`: `scriptRunner` executable is a temp script that creates a marker file;
  source `do shell script "id"` -> `isError`, text contains `script policy filter` and `not a security boundary`; marker
  absent; the audit file holds a `request` entry whose `payload` is the source and a `result` entry whose `outcome`
  starts with `rejected:filter`.
- `testAuditFailureRefusesScript`: audit directory is a symlink; same marker runner; source `return 1` -> `isError`,
  text contains `audit log`; marker absent. Same result for source `do shell script "id"` (the audit check comes first).
- `testOpenUrlAndShortcutAreAuditedAndRefusedWhenLogUnsafe`: launcher with a recording `opener`, resolvers mapping
  `https://example.com` to a fake Safari `.app`, and a marker `shortcutsExecutablePath`. With a safe temp audit dir:
  `open_url` and `run_shortcut` each leave one `request` and one `result` entry (`kind` `open_url` / `run_shortcut`).
  With a symlinked audit dir: both return `isError` with `audit log`, the `opener` was never called and the marker is
  absent.
- `testRunScriptEndToEnd`: real osascript, `return 1 + 1` -> text starts with `2` and contains `exit=0`; JavaScript
  `1 + 1` -> `2`; the audit file holds the source; captured stderr lacks the source.
- `testFirstContactFloorAppliesOnce`: `firstContactMinimumTimeout: 3`, `delay 30` with `timeout_s: 1` for a fresh app
  times out with duration in 2.5-10s (floor applied); a second call for the same app after a successful `return 1`
  times out with duration < 10s AND at least 1.0s shorter than the first call (floor not applied again). The relative
  check keeps the floor distinguishable on a slow shared CI runner, where fixed upper bounds flake.
- `testLockedGuardBlocksLocalTools` (T15): locked fake provider -> every local tool returns the lock message; marker
  runner not spawned.

Fail-closed agent paths (T2, T3, T16) with an UNLOCKED guard
- `testAgentDispatcherRefusesEveryLocalToolWhenUnlocked`: `ComputerUseToolDispatcher(service: ComputerUseService(),
  guard: MacSessionGuard(provider: <unlocked fake>, policy: .blockWhileLocked)).callToolAsResult(name:arguments:)` for
  each of the 5 names -> `isError`, text contains `unsupportedTool("<name>")`, text does not contain `macOS is locked`.
- `testCallRunScriptFailsClosedThroughCLIRunner`: `runOpenComputerUseCall(.single(toolName: "run_script",
  argumentsJSON: #"{"app":"Mail","source":"return 1"}"#, argumentsFile: nil), guard: <unlocked guard>)` ->
  `hasToolError == true` and the JSON text contains `unsupportedTool`.
- `testListedNeverContainsLocalTools`: `ToolDefinitions.listed(environment: [LocalChannelPolicy.environmentKey: "1"])`
  and `ToolDefinitions.all` contain none of the 5 names.
- `testSanitizerDropsScriptingFlag`: `MacSessionLockPolicy.sanitizePeerEnvironment([flag: "1", "OPEN_COMPUTER_USE_DEBUG": "1",
  "OPEN_COMPUTER_USE_ALLOW_LOCKED": "1"])` == `["OPEN_COMPUTER_USE_DEBUG": "1"]`.

## Rollback

Revert the phase commit. The new files are unreferenced until phase 06; the `MacSessionGuard.swift` clause reverts to
the prior filter (the flag would then reach the agent again, where it is inert because no dispatcher case exists).

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
