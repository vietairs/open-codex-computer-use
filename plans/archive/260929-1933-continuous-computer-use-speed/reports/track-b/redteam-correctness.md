# Red-team: Track B plan, correctness and testability lens (2026-09-29)

Scope: plan-track-b/plan.md, phases 00-10, threat-model.md. Every claim was checked against the source at base afb60fa in
`.claude/worktrees/fast-macos-channels` (A = apps/OpenComputerUse/Sources/OpenComputerUse, K = Kit sources, S = smoke suite).
Verdict: wiring sound (router order, flag-off passthrough, fail-closed agent paths). 4 High gaps before cook; no Critical.

## Verified correct (no action)
- The router covers the relay and both direct paths. The only `StdioMCPServer` stdin loops are `A/OpenComputerUseMain.swift:49` and `A/MCPAppRuntime.swift:96`. The agent (`A/MacOSAppAgentProxy.swift:365,407-418`) uses `handle` and deliberately gets no router.
- Flag off: `route` calls `forward(line)` without parsing, handlers are built lazily, and the blank-line skip plus nil-drop match `K/MCPServer.swift:45-54` and `A/MacOSAppAgentProxy.swift:121-137`.
- Refusal tests are satisfiable. The `unsupportedTool` text is `unsupportedTool("<name>")` (`K/Errors.swift:17-18`), and the lock guard runs first (`K/ComputerUseToolDispatcher.swift:61`), so an unlocked guard is required, which the plan specifies.
- The CLI path fails closed: `runOpenComputerUseCall` goes through `callToolAsResult` (`K/ComputerUseToolDispatcher.swift:323-342`).
- `click`, `set_value` and `scroll` read `currentSnapshot` (cached, `K/ComputerUseService.swift:961-967`), so merged hit indices do resolve. `elements` is a dictionary, so a missing index cannot trap (`:997-1003`).
- The group kill is covered implicitly. `trap "" TERM` passes SIG_IGN to `sleep` as well, so only `kill(-pid, SIGKILL)` passes `testTermIgnoringChildIsKilled`.

## High
H1. **Scripts rejected by the filter are never logged, and a test enforces that.** Decision 8 says "Every script text is logged" (outcome-lock.md:45). Phase 04 runs the filter before the audit request (phase-04:59) and `testFilterRejectionNeverSpawns` asserts "no request entry in the audit file" (phase-04:191). As a result, prompt-injection attempts leave no forensic trace.
Fix: audit `.request` with the full source before the filter runs. On rejection, audit `.result` with outcome `rejected:<pattern>`. Refuse the call if the audit write fails. Invert the test: the entry exists, the marker file is absent.

H2. **No test proves amendment 5 for open_url and run_shortcut.** The plan specifies audit-then-refuse for both (phase-04 step 4), but only `run_script` has audit tests (`testAuditFailureRefusesScript`, `testRunScriptEndToEnd`). Counsel amendment 5 ("Log open_url and run_shortcut calls as well", counsel:21) is an acceptance criterion, so as written it is unverified.
Fix: add `testOpenUrlAndShortcutAreAuditedAndRefusedWhenLogUnsafe`. It needs an injected launcher (a recording `opener` and a marker `shortcutsExecutablePath`). Assert a request and a result entry on success. With a symlinked audit dir, assert that the opener is never called and the marker is absent.

H3. **No test exercises the relay, and only one direct path is smoked.** Phase 06 names the smoke suite as the end-to-end check (phase-06:13). The smoke suite always sets `OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY=1` (`S/main.swift:348-352`) and launches the raw product binary, so it never reaches `proxyMCP` or `relayMCPLine`. The visual cursor defaults to on (`K/SoftwareCursorOverlay.swift:27-33`), so the smoke runs only the `MCPAppRuntime` path; the `server.run()` path at `OpenComputerUseMain.swift:49` is only grep-checked. Acceptance 2 ("byte-identical ... smoke, phase 10") is therefore unproven for the production relay.
Fix, in phase 10 step 4: send the same request script (initialize, tools/list, tools/call run_script, unknown method) to Dev.app twice, once via the relay and once with `OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY=1`, with the flag unset. Diff the responses; they must be identical.
Phase 06: add a flag-on smoke variant with `OPEN_COMPUTER_USE_VISUAL_CURSOR=0`.

H4. **A contract STOP is guaranteed in phase 04.** `testFirstContactFloorAppliesOnce` needs an injectable first-contact floor (`firstContactMinimumTimeout: 3`, phase-04:198), and step 4 says to call `OsascriptChildRunner.effectiveTimeout(requested:isFirstContactWithTarget:)` with that floor "replaced" (phase-04:62). The frozen signature (phase-01:165,171) hard-codes 30, so the implementer cannot satisfy both Contract Rule 1 and the test.
Fix: change the phase 01 signature to `effectiveTimeout(requested:isFirstContactWithTarget:firstContactFloor: TimeInterval = firstContactMinimumTimeout)` and add a table row for it in `testEffectiveTimeoutTable`.

## Medium
M1. **A second guaranteed STOP in phase 05.** `CGRect.renderedLocalFrame` is `private extension` (`K/AccessibilitySnapshot.swift:2341-2345`), but phase 05 lists it as a reusable internal helper (phase-05:25) and requires it in the row format (:82). The same phase forbids edits to `AccessibilitySnapshot.swift`.
Fix: allow a private copy in `ElementSearchSnapshotMerge.swift`, pinned by `testRowFormat` against a literal `x=..., y=..., w=..., h=...`. Add it to the phase 09 dedupe list.

M2. **A hits-only snapshot breaks `type_text`.** A hits-only snapshot sets its focus fields to nil (phase-05:79-81), and it replaces the cache under all three keys. `typeText` then fails both focus paths (`K/ComputerUseService.swift:1535-1538` plus the keyboard-fallback guard). It falls into `NSRunningApplication.activate` (`:886-896`), which steals the user's foreground on the new guide's `find_elements -> type_text` flow.
Fix: in the hits-only branch, read `AXFocusedUIElement` once and fill `focusedElement`. Add a test that a hits-only snapshot carries a focus from the fake source.

M3. **The merge checks the window ID but not the bounds.** A hit's `localFrame` is computed against the window bounds as they are now (phase-05 step 6), but `click` converts it with the cached snapshot's `windowBounds` (`K/ComputerUseService.swift:647-653`). If the window moved since the last refresh, the cursor target and the non-AX fallback point are wrong.
Fix: merge only when `targetWindowID` AND `windowBounds` are equal; otherwise build a hits-only snapshot. Add a case with the same ID and moved bounds to `testMergeRequiresMatchingWindow`.

M4. **Timeout and reap edges.**
(a) Two threads can both reap the child: the waitpid thread and "then reap" after SIGKILL (phase-01:53). Specify one reaper and a bounded wait on its semaphore after SIGKILL.
(b) The drain-thread join has no bound. A descendant that outlives a normally exiting leader, or a setsid'd one, keeps the pipes open and wedges the serial relay. After the leader is reaped, run `kill(-pid, SIGKILL)` and join the drains with a deadline, then close the read ends. Test: `/bin/sh -c 'sleep 30 & exit 0'` returns in under 3s.
(c) The truncation cap can split a UTF-8 sequence, so `String(data:encoding:)` may return nil. Mandate `String(decoding:as: UTF8.self)` and test a multi-byte character that straddles 65,536 bytes.

M5. **The script child is orphaned when the relay dies.** `POSIX_SPAWN_SETPGROUP` moves osascript out of the host's process group. Ctrl-C, or the host sending SIGTERM or SIGHUP to the relay, leaves the script running with no timeout. The phase 08 red-team item checks only the audit lines (phase-08:39).
Fix: the relay records the active child's pgid and forwards SIGTERM, SIGINT and SIGHUP to it before exiting. Document SIGKILL of the relay as a residual risk.

M6. **A router test runs the real `/usr/bin/shortcuts`.** `testLocalToolsAreNeverForwarded` calls all five tools with default handlers, and `list_shortcuts` takes no arguments, so it runs `/usr/bin/shortcuts list` (phase-04:72,186). The test-hygiene rules forbid real non-osascript children.
Fix: inject `makeHandlers` with a temp audit log and a launcher whose `shortcutsExecutablePath` is a temp marker script.

M7. **The router's error handling is underspecified.** `route` only says "never call forward" for local tools (phase-04:77). Any throw from encoding the result or patching `initialize`/`tools/list` would propagate out of `run` and kill the relay. Error responses (no `result`, or no `instructions`/`tools`) are specified only as "nil or unparsable".
Fix: catch every local-side error into a JSON-RPC error. Pass through untouched any forwarded response that lacks `result.instructions` or `result.tools`. Add a test for each case.

M8. **The phase 10 harness never exercises early stop.** `fe_args` omits `max_results` (phase-10:46), and the default is 5. With fewer than five "Search" matches the walk never stops early and reads up to 1,200 nodes, so criterion 7b does not measure the feature the design relies on.
Fix: pass `max_results: 1`, and record `nodes_visited` from the tool output.

M9. **`get_scripting_dictionary` can launch an app with no review.** For apps without `OSAScriptingDefinition`, the fallback `OSACopyScriptingDefinitionFromURL` (phase-03:53) may use dynamic terminology, which launches the app and sends it an Apple Event. The tool is annotated read-only and is allow-listed in phase 10.
Fix: restrict the fallback to static resources (it must not send events), or return `.noScriptingDefinition`. Add a live check to phase 10.

## Low
- L1. The phase 04 signature puts `sanitizePeerEnvironment` under the heading "MacSessionGuard.swift". The real owner is `MacSessionLockPolicy` (`K/MacSessionGuard.swift:47,64-68`). Name the type so the test compiles.
- L2. `testInitializeSwapsAppleScriptLineForGuide` asserts `Ask the user before`, but the base text already has it at `K/MCPServer.swift:17`, so the assertion is vacuous. Assert the guide's own sentence instead.
- L3. Add a unit test that `tools/call` for `Run_Script` (case variant) is forwarded. Today this is only a paper red-team item in phase 08.
- L4. The harness uses `dict(os.environ, ...)`. A loopback `OPEN_COMPUTER_USE_DECISION_MODEL_URL` in the shell makes step 4 print 12, not 11. Pop that key.
- L5. `target_app` (audit) and `contactedTargets` (first-contact floor) are keyed on the self-declared `app` argument, not the app the script actually tells. Document that `target_app` is advisory.
- L6. Audit rotation race: a writer blocked on `flock` against the old inode rotates a second time (phase-02:32). After `flock`, compare the inodes from `fstat` and `lstat` and reopen on mismatch.
- L7. The allocator's 1,000,000 base is only safe while full trees stay below 1M nodes, and `max_tree_nodes` is unbounded (`K/ComputerUseToolDispatcher.swift:70`). Note this as a residual risk.
- L8. In the default single-worktree mode, phase 06 verify 6 (full `swift test`) fails while phase 07's runtime-red test exists. The rule must say one red phase at a time, runtime-red included.
- L9. `testCompactViewSkipsHitRowsButCountsThem` pins a path no tool reaches: every rendered snapshot comes from `refreshSnapshot`. Keep it or drop it, but do not count it as coverage.

## Plan fixes, in priority order: H1+H2; H4+M1; H3; M2+M3; M4/M5/M7; M6/M8/M9; then Lows.

## Unresolved questions
1. H1: should a script rejected by the lock guard or by argument validation also be logged, or only scripts the filter rejects?
2. M5: is forwarding the relay's signals acceptable, or should the child stay in the host's process group and give up the group kill?
