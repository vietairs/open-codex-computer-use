# Red-team (integration lens): Track B plan vs Track A, rebase, coupling, docs, scope

Date 2026-09-29. Plan-only review. Every source cite is in the `fast-macos-channels` worktree at afb60fa
(K=`packages/OpenComputerUseKit/Sources/OpenComputerUseKit`, A=`apps/OpenComputerUse/Sources/OpenComputerUse`). Track A cites
are in `plan-track-a/`. No Critical findings. There are 2 High, 6 Medium and 4 Low.

## High
**H1. Phase 09 tells the executor to put `find_elements` last. Track A's test requires `perform_actions` to be last.**
- phase-09 table row ToolDefinitions says "order `..., perform_actions, find_elements` is irrelevant to tests but keep A first".
- Track A phase-05:285 asserts `ToolDefinitions.all.last?.name == "perform_actions"`, and its :156 appends it "as the last element".
- If the executor follows phase 09, the suite goes red. Contract Rule 4 forbids weakening A's test, so the phase STOPs.
- Fix: at rebase, place `find_elements` BEFORE `perform_actions`. Correct the table row. Add a phase 09 verify:
  `all.last?.name == "perform_actions"` and `all.contains find_elements`. The MCPServer :10 wording already lists perform_actions last.

**H2. The `find_elements` extension becomes a second writer of `snapshotsByApp`. Track A forbids that. The phase 09 table misstates it.**
- phase-05 step 10 stores the merged snapshot "under the same three keys", from the EOF extension.
- Track A phase-01:118 FORBIDS "a second writer of snapshotsByApp (single write point :990-991 stays)".
- Track A phase-05:243 verifies that `grep 'snapshotsByApp\['` shows exactly one assignment line.
- phase-09's ComputerUseService row says "B only reads `snapshotsByApp`". That is false.
- The duplicated three-key rule (K/ComputerUseService.swift:984-992) will drift silently from A's rewrite.
- Fix: correct the phase 09 row. At rebase, extract A's write loop into `private func storeSnapshot(_:query:app:)` and route
  both callers through it. Add a test that find_elements and refreshSnapshot produce the same key set.
- Alternatively, the main loop asks Track A to land that helper before merge. The main loop owns that call; this plan cannot make it.

## Medium
**M1. A hits-only snapshot makes the next `type_text` bring the target app to the front.**
- The hits-only merge sets "focus fields nil" (phase-05 step 8). `typeText` reads `snapshot.focusedElement`
  (ComputerUseService.swift:1536, :1557).
- With focus nil, it falls into the Stage Manager branch, which activates the target app and then restores the previous one (:890-896).
- This happens for find_elements (new window) followed directly by type_text. It breaks the "don't disrupt the user's session" rule.
- Batches are safe: Track A reads focus live. The single-action path is not.
- Fix: in the hits-only path, read `AXFocusedUIElement` once (plus focusedSummary). Add a test that a hits-only snapshot carries focus.

**M2. The smoke suite never exercises the relay. Phase 06 overstates its coverage.**
- `smokeServerEnvironment()` sets `OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY=1` (Smoke main.swift:350). Only direct mode is tested.
- The rewrite of `proxyMCP` (the default install path) is covered only by the phase 10 harness, and only for tools/list and run_script.
- The smoke suite also inherits the caller's environment. A shell with `OPEN_COMPUTER_USE_ENABLE_SCRIPTING=1` exported breaks the
  flag-unset "10 tools" assertion.
- Fix:
  - Remove the scripting key in `smokeServerEnvironment()`, as :351 already does for DECISION_MODEL_URL.
  - Correct the phase 06 wording.
  - Add a phase 10 step that runs the harness flag-unset through the relay and compares initialize and tools/list against direct mode.

**M3. Decision 9 is partly narrowed, and the new guidance contradicts line :8.**
- Decision 9 says "find_elements plus the batch tool". `scriptFirstInstructionGuide` (phase-04 step 1) names only
  "find_elements plus element-targeted actions".
- Phase 09 appends `perform_actions` to the MCPServer line but never to the guide.
- The guide's "full get_app_state only when neither fits" also sits next to the retained :8 "Begin by calling get_app_state every
  turn ... required" (MCPServer.swift:8; kept by decision 12).
- Fix: phase 09 updates the guide to name `perform_actions`, and a test asserts it. The main loop picks wording that scopes :8 to UI
  tools, with no reopening of decision 12.

**M4. The phase 10 harness can kill the main loop's live MCP agent.**
- The Dev.app relay terminates and unlinks any agent whose bundleURL differs (A/MacOSAppAgentProxy.swift:86-93, :618).
- This is memory `app-agent-socket-eviction-between-bundles`.
- Fix: set `OPEN_COMPUTER_USE_AGENT_SOCKET_NAMESPACE=<unique>` (AppAgentSocketNamespace.swift:4) in the harness and smoke environments.

**M5. Docs that the plan misses.**
- docs/ARCHITECTURE.md:42 says the process that "actually calls ... is always Open Computer Use.app, never the iTerm / Terminal /
  Node launcher". That becomes false for run_script: osascript is a child of the relay and runs under the host's Automation TCC.
- docs/ARCHITECTURE.md:12 says the smoke suite covers "the 9 tools".
- docs/ARCHITECTURE.md:69 describes the `call` path without the run_script refusal.
- README.md:50 "Trust boundary (read before enabling)" says nothing about the scripting opt-in, although it effectively grants a
  shell on MCP-only hosts.
- There is no `docs/exec-plans/active/` entry, although docs/PLANS_GUIDE.md:5-9 asks for one on high-risk work. Precedent:
  `docs/exec-plans/active/20260922-local-decision-model-mcp-tool.md`.
- Fix: add these to phase 07 TARGET and Verify (grep `run_script` in README.md and in ARCHITECTURE.md near :42).

**M6. Identical hunks from both tracks auto-merge to stale counts, and the shared-file list is incomplete.**
- Both tracks change DecisionAdvisorTests:448 (10→11), make the same `StaysTen` renames, and change smoke :199-200 (9→10). Git
  merges identical edits without a conflict, so the values end up stale.
- phase-09 Verify 2 greps only `ToolDefinitions.all.count`.
- parallel-tracks.md does not list smoke main.swift as shared (Track A phase-05:199 notes the same gap).
- Fix: add greps for `listed.count` (12 loopback, 11 non-loopback) and the `StaysEleven`/`StaysAtEleven` names. Ask the main loop to
  add the smoke file to the shared list.

## Low
- **L1. The wrong owner type is named for the sanitizer.** Phase 04 names `MacSessionGuard.sanitizePeerEnvironment`. The real symbol
  is `MacSessionLockPolicy.sanitizePeerEnvironment` (MacSessionGuard.swift:47,64). Qualify it in the Signature block and in
  `testSanitizerDropsScriptingFlag`.
- **L2. The measurement target drifted.** Outcome-lock says "find_elements for one button on Mail". Phase 10 pins an AXTextField
  "Search". Measure a button (for example `AXButton` "Get Mail"), or have the main loop record the substitution.
- **L3. The fixture case is not handled.** Fixture snapshots have `targetWindowID: nil` (AccessibilitySnapshot.swift:571), so
  find_elements always produces a hits-only snapshot there. That drops the fixture indices and flips `mode` to `.accessibility`, so a
  later click bypasses FixtureBridge. Fix: refuse or merge when `mode == .fixture`.
- **L4. Counsel amendment 5 ("reuse Track A's owner-only file helper") is silently not applied.** A's helper is a reader
  (`readOwnerOnlyRegularFile`, Track A phase-06:70), while B needs an O_APPEND writer. Record "N/A, reason" in phase 02 and phase 09
  so the security review does not flag the divergence.

## Verified OK (no action)
- `AppSnapshot` gains no field (A phase-01:117), so B's memberwise init survives.
- A leaves the helpers B consumes untouched: `childTraversalAttributes`, `meaningfulActions`, `windowRelativeFrame`,
  `preferredWindowCaptureCandidate`.
- `find_elements` in `all` does not trip `computerUseServerInstructions` (MCPServer.swift:26).
- The unknown-tool refusal sits at dispatcher :128-129 after the guard at :61.
- Tool-count table: 10/11/10 before the rebase and 11/12/11 after, plus 15→16 for the flag-on smoke.
- Scope: no server-side planner. `list_shortcuts` is the only tool beyond decision 7's four channels, and it is read-only and
  flag-gated (Low; state it in plan.md).

## Unresolved questions
1. Will Track A add a `storeSnapshot` helper before merge (H2), or does B extract it during the rebase?
2. What wording reconciles :8 "get_app_state every turn" with the script-first guide without reopening decision 12 (M3)?
