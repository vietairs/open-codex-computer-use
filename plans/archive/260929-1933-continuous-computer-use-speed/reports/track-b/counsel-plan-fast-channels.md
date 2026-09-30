# Counsel: Track B plan, direction-confirm gate (PR B, fast channels)

Date 2026-09-29. One-shot `--counsel` pass with no interview. Decisions 7-10 and 14-16 and the approved P2 design are treated as fixed. I checked the plan against source at base afb60fa in the fast-macos-channels worktree.

## Verdict
The direction is right, so approve it with six plan amendments. The plan executes P2 faithfully and closes all eight counsel amendments. Every PR B acceptance line maps to a unit test or a live step. The three red-team passes were folded in honestly. The 37h estimate, against the brainstorm's 20-24h, buys proportionate rigour for a code-execution surface, so I found no material over-scope. `list_shortcuts` is the only tool beyond decision 7. It is read-only and flag-gated, so keep it. The gaps sit at the edges: `find_elements` can return rows that are off-screen, `open_url` is never exercised live, and the live-host steps in phase 10 are missing their setup. The main acceptance risk is also the one found last: the ≤50% ratio is first measured after about 35h of work.

## Verified in source
- Actions resolve indices from the cached snapshot (`currentSnapshot` ComputerUseService.swift:961-967; click :615/:648). Track A's batch pins `currentSnapshot` too (track-a phase-05:177, and it forbids a TTL). Merged hits therefore survive both single actions and batches, which closes counsel check 4.
- The relay loop runs on the main thread (`proxyMCP` MacOSAppAgentProxy.swift:121-137), while direct mode runs on a detached thread (MCPAppRuntime.swift:58). `StdioMCPServer.run` (MCPServer.swift:45-55) skips blank lines and nil responses, and the router copies that behaviour.
- The phase 04 tests call symbols that exist with the planned signatures: `runOpenComputerUseCall`, `ToolCallResult.text(_:isError:)`, `ToolDefinition.asDictionary`, `handle(line:)`, and `sanitizePeerEnvironment` (:64-68).
- `visibleRows` is private (AccessibilitySnapshot.swift:2297-2315). Click has no window-bounds guard: `windowPointToGlobalPoint` (:1809-1815) only adds the window origin.
- The smoke env strips `DECISION_MODEL_URL` only (smoke main.swift:351), not `OPEN_COMPUTER_USE_DECISION_MODEL_BACKEND` (DecisionRemoteBackend.swift:22).

## Acceptance coverage
- **Mail run_script ≤1s:** phase 00 runs a pre-check and phase 10 step 1 measures the median of 5 warm runs through the relay.
- **find_elements ≤50%:** phase 10 step 2 measures it with `max_results:1`.
- **Flag unset lists nothing:** phase 04 unit tests, the phase 06 smoke and the phase 10 equivalence check cover it.
- **Filter rejects:** phase 01 has a table test, and phase 10 step 6 runs a compiler probe.
- **Never crosses the socket:** the router never forwards, the agent dispatcher and `call run_script` refuse the tool with an unlocked guard, the sanitizer drops the flag, and the child sees only fds 0-2. A grep checks the relay wiring, and the live harness proves it by construction, because the agent has no run_script case.
- **Tool counts:** 10 before the rebase and 11 after, stated per assertion. The grep gates catch stale identical hunks.

## Amend the plan before cook
1. **Off-screen hits (phase 05).** Rows are taken as the first 20 with no visibility filter, so a hit can carry a frame outside the window. Auto-click then hit-tests and posts a pid-targeted click at that off-window point (ComputerUseService.swift:660-677), which can be a wrong click or a silent no-op. Fix: fetch `AXVisibleRows` in the batched read for table, outline and list roles, or set `localFrame` to nil for hits outside the window so click fails with "no clickable frame". Add one test.
2. **Live `open_url` and `list_shortcuts` (phase 10).** Neither runs live today. The default opener waits on a semaphore, and in the relay that wait happens on the main thread. I believe, without having verified it, that AppKit delivers the completion handler on a concurrent queue. If it uses the main queue instead, every `open_url` becomes a 10s false failure that the unit tests cannot see. Add a harness step that opens `https://example.com` and calls `list_shortcuts`.
3. **Host setup for phase 10 steps 7 and 9.** The session's MCP server is the npm release, which has no run_script. Add a step that registers the Dev.app build under the same server name `open-computer-use`, with the flag and `OPEN_COMPUTER_USE_AGENT_SOCKET_NAMESPACE` set, restarts the session, and restores the old registration afterwards. Under any other server name the narrowed `mcp__open-computer-use__*` rules do not match, so the review observation would be meaningless.
4. **`OPEN_COMPUTER_USE_DECISION_MODEL_BACKEND`.** Strip it in the harness `DROP` list and in `smokeServerEnvironment`. If remote jev is exported, the counts read 12 and 16 instead of 11 and 15.
5. **Measure the ratio early.** Run phase 05 first in G1. When Track A is not being measured, take one live `find_elements` vs `get_app_state` probe on the build before the rebase. Track A's batched reads (decision 13) shrink the denominator later, so aim for about 0.35 early. If the ratio misses, the lever is walk order (breadth-first finds shallow toolbar controls sooner). Raising `max_nodes` does not help.
6. **Timing tests on CI.** Five checks run per PR. The timing windows are tight (`testFirstContactFloorAppliesOnce` expects 2.5-4.5s, and several others expect under 3s), so widen the upper bounds before a shared macOS runner makes them flake.

## Top risks
- The ≤1s target is bounded by Mail's own `whose` speed. Phase 00 gates this correctly, so run it first.
- Desktop hosts may give a silent -1743. If they do, run_script works only from terminal hosts, and no fix fits inside decision 8.
- The only review of prompt-injected scripts is Claude Code's auto-mode classifier. Codex and Claude.app hosts have none. The docs state this, and it is the user's accepted trade-off under decision 16.
- The rebase is a risk: there is a second `snapshotsByApp` writer, `MCPServer.swift:10` must be resolved by hand, and identical count hunks auto-merge stale. The plan's grep gates and the post-rebase re-review are adequate.

## Decisions the user must confirm
1. **Guide wording (plan Q2).** Confirm the plan's wording. I recommend adding one sentence: the turn-start `get_app_state` applies to UI work, so a turn that only uses `run_script` skips it. Also name `find_elements` for "after a script changed the UI". That is where it saves calls, since Track A's action results already carry state.
2. **`storeSnapshot` owner.** Recommended: Track A lands the helper in its own file if PR A is not frozen. Otherwise keep the plan default, where B extracts it at the rebase.
3. **Relay death orphans the osascript child.** Recommended: accept this as a documented residual rather than adding process-wide signal forwarding.
4. **Static-only sdef.** Apps with only `aete` terminology get `noScriptingDefinition`. Recommended: accept.
5. **Script log retention.** The plan keeps 10 MB plus one rotated file, and the log holds email content. This is the user's call.
6. **Phase 10 live setup (amendment 3).** Approve temporarily re-pointing the Claude Code MCP server to Dev.app. The user runs the harness in Terminal.app, because the sandbox blocks Apple Events.

## Checklist and success metrics
- [ ] Fold amendments 1-6 into phases 05, 06 and 10.
- [ ] Run phase 00, then cook G1 with phase 05 first, then the early probe, then G2 through G4, phase 08, the rebase and phase 10.
- Success means all of these hold:
  - `swift test` passes before and after the rebase.
  - The run_script median of warm runs is ≤1.0s.
  - The `find_elements`/`get_app_state` ratio is ≤0.50, measured after the rebase.
  - With the flag unset, the equivalence check prints `IDENTICAL` four times.
  - `open_url` returns `Opened ...` in under 2s.
  - `scripts.log` has mode 600.
  - There are zero open Critical/High findings.

## Unresolved questions
1. Does AppKit deliver the `NSWorkspace.open(_:withApplicationAt:configuration:completionHandler:)` completion off the main queue? This is unverified, and amendment 2 settles it live.
2. Where does Mail's "Get Mail" button fall in DFS order relative to the message-list split group? This sets `nodes_visited`, and the early probe answers it.
3. Is PR A still open to a one-line `storeSnapshot` helper (decision 2)?
