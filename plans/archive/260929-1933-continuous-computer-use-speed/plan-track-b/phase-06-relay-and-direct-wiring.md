# Phase 06: relay and direct-mode wiring, smoke suite

Depends on: phases 04 and 05. Parallel group G4 (with phase 07; disjoint files). Blocks: 08.
Risk: High (the only phase that changes the live relay loop; the app target has no test target, `Package.swift`).
Effort 1.75h.

## Execution constants

- `WT=/Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/fast-macos-channels`; run as `cd "$WT" && ...`.
- `A=apps/OpenComputerUse/Sources/OpenComputerUse`; `S=apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite`.
- The app target cannot be reached by `swift test` (only `OpenComputerUseKitTests` and `StandaloneCursorSupportTests`
  exist). All behaviour is already unit-tested in the Kit (phase 04); this phase keeps each app change to one call into
  the router. End-to-end coverage is split, and the plan does not claim more than this:
  - The smoke suite (main loop, phase 10) always sets `OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY=1` (`S/main.swift:348-352`),
    so it exercises DIRECT mode only: the `MCPAppRuntime` path by default (the visual cursor defaults to on,
    `K/SoftwareCursorOverlay.swift:27-33`) and the `server.run()` replacement at `A/OpenComputerUseMain.swift:49` only
    when `OPEN_COMPUTER_USE_VISUAL_CURSOR=0` is set (Task 6.1 step 3).
  - The RELAY (`proxyMCP` / `relayMCPLine`) is covered live by phase 10 step 4 (relay-vs-direct response diff, flag
    unset) and by the phase 10 harness (flag set).
  The smoke suite needs the Dev.app TCC grant; never run it from a workflow.
- Never start the app agent, never run the built binary against real apps, never call MCP tools.
- Roles: tester does Task 6.1 (smoke assertions); a different implementer does Task 6.2.

## Verified source facts

- Relay loop: `A/MacOSAppAgentProxy.swift:121-137` (`proxyMCP`). Agent socket created without CLOEXEC at `:553`.
- Agent launch environment carries only the lock key (`:100-106`); this phase must not change that.
- Direct paths: `A/OpenComputerUseMain.swift:44-50` (`MCPAppRuntime.run(server:)` or `server.run()`), and
  `A/MCPAppRuntime.swift:94-104` (`processStandardIO` calls `server.run()`).
- `.call` is proxied to the agent and fails closed there for local tools (phase 04 tests); no CLI change (amendment 3).
- Smoke suite asserts `tools.count == 9` at `S/main.swift:199-200`; it launches `serverURL mcp` with
  `smokeServerEnvironment()` (`:191`).

## Task 6.1 (tester): smoke assertions first

- Target: `S/main.swift` only.
- Steps:
  0. `smokeServerEnvironment()` (`:347-352`): also `removeValue(forKey: "OPEN_COMPUTER_USE_ENABLE_SCRIPTING")` and
     `removeValue(forKey: "OPEN_COMPUTER_USE_DECISION_MODEL_BACKEND")` (`K/DecisionRemoteBackend.swift:22`), next to the
     existing `DECISION_MODEL_URL` removal (`:351`), so a shell that exported the scripting flag or the remote decision
     backend cannot break the flag-unset count (an exported remote backend would add `decide_next_action`).
  1. `:199-200`: expect 10 tools (flag unset) and additionally assert that none of `run_script`,
     `get_scripting_dictionary`, `open_url`, `run_shortcut`, `list_shortcuts` is listed and that `find_elements` is.
  2. Add `runScriptingChannelSmoke(serverURL:)` called from the full smoke after the existing steps: a second
     `MCPClient` whose environment is `smokeServerEnvironment()` plus `OPEN_COMPUTER_USE_ENABLE_SCRIPTING=1`;
     assert `tools/list` has 15 tools, `initialize` instructions do not contain
     `Avoid falling back to AppleScript`, and `run_script {"app":"OpenComputerUseFixture","source":"return 1 + 1"}`
     returns text starting with `2`. (`return 1 + 1` sends no Apple Event.)
  3. Run `runScriptingChannelSmoke` twice: once with the environment above (MCPAppRuntime path) and once with
     `OPEN_COMPUTER_USE_VISUAL_CURSOR=0` added (the `server.run()` replacement at `A/OpenComputerUseMain.swift:49`). Print
     which path each run covered.
- Verify: `cd "$WT" && swift build --product OpenComputerUseSmokeSuite 2>&1 | tail -20` exits 0. (The run is phase 10;
  there is no runnable red state for this target, which is stated here on purpose.)

## Task 6.2 (implementer): wire the router

- Steps:
  1. `A/MacOSAppAgentProxy.swift`: replace the body of `proxyMCP(client:)` with
     `try LocalChannelRouter().run { line in try relayMCPLine(line, client: client) }`, and add
     `relayMCPLine` holding the old request/response code: send `["kind": "mcp", "line": line, "environment":
     proxiedEnvironment()]`, return `response["response"] as? String` (NSNull -> nil).
  2. Same file, `AppAgentSocketClient.connect`: right after `socket(AF_UNIX, SOCK_STREAM, 0)` succeeds, call
     `fcntl(fd, F_SETFD, FD_CLOEXEC)`; on failure close the fd and return nil.
  3. `A/OpenComputerUseMain.swift:49`: `try server.run()` -> `try LocalChannelRouter().run { server.handle(line: $0) }`.
  4. `A/MCPAppRuntime.swift:96`: `try server.run()` -> `try LocalChannelRouter().run { self.server.handle(line: $0) }`
     (match the existing property access; do not change actor isolation).
  5. Leave `connectOrLaunchAgent`'s `configuration.environment` untouched.
- Verify:
  1. `cd "$WT" && swift build 2>&1 | tail -20` exits 0.
  2. `cd "$WT" && grep -c "LocalChannelRouter()" apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift apps/OpenComputerUse/Sources/OpenComputerUse/OpenComputerUseMain.swift apps/OpenComputerUse/Sources/OpenComputerUse/MCPAppRuntime.swift`
     prints `:1` for each of the three files.
  3. `cd "$WT" && grep -n "FD_CLOEXEC" apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift` prints
     exactly one line.
  4. `cd "$WT" && grep -n "configuration.environment" apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift`
     prints exactly one line containing `MacSessionLockPolicy.environmentKey`.
  5. `cd "$WT" && grep -rn "server.run()" apps/OpenComputerUse/Sources/OpenComputerUse/` prints nothing.
  6. `cd "$WT" && swift test 2>&1 | tail -15` exits 0 and prints `with 0 failures`.

## Signature

```swift
// A/MacOSAppAgentProxy.swift, inside enum MacOSAppAgentProxy (unchanged signature)
private static func proxyMCP(client: AppAgentSocketClient) throws
// new
private static func relayMCPLine(_ line: String, client: AppAgentSocketClient) throws -> String?

// Kit API consumed (phase 04)
public final class LocalChannelRouter {
    public init(environment: [String: String] = ProcessInfo.processInfo.environment,
                makeHandlers: (() -> LocalChannelToolHandlers)? = nil)
    public func run(forward: (String) throws -> String?) throws
}
```

## Boundaries

```
TARGET:    A/MacOSAppAgentProxy.swift (proxyMCP, new relayMCPLine, AppAgentSocketClient.connect),
           A/OpenComputerUseMain.swift (:49), A/MCPAppRuntime.swift (:96),
           S/main.swift (:199-200, smokeServerEnvironment :347-352, one new function)
READ-ONLY: every K/ file, Package.swift
FORBIDDEN: K/OpenComputerUseCLI.swift and any `.call` routing change (amendment 3); passing the scripting flag in the
           agent launch environment or per-call environment; entitlements, Info.plist, scripts/build-open-computer-use-app.sh;
           running the smoke suite or the built binary; K/MCPServer.swift and docs (phase 07)
```

## Acceptance

Command: the Verify lines of Task 6.2 (exact outputs stated there), plus phase 10 step "smoke".
Assertions:
- App target builds; the three router call sites exist; no `server.run()` remains in the app target.
- The relay socket fd is close-on-exec.
- Agent launch environment still carries only the lock opt-in.
- Kit suite green (phase 04's fail-closed and passthrough tests are the behavioural proof).
- Smoke suite (run by main loop in phase 10, direct mode only): flag unset -> 10 tools, no local tools, `find_elements`
  listed; flag set -> 15 tools, AppleScript line swapped, `run_script return 1 + 1` -> `2`, on both direct paths
  (visual cursor on and off).
- Relay: phase 10 step 4 (flag unset, relay and direct responses identical) and the phase 10 harness (flag set).

## Rollback

Revert the phase commit: `proxyMCP` returns to the original loop byte-for-byte and both direct paths call
`server.run()` again. The Kit router stays but is unreferenced, which is inert.

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
