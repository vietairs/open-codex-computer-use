# Outcome lock (2026-09-29 19:50, user answers)

Outcome: a multi-step computer-use task feels continuous. Fewer agent turns per task, and each server call is faster.

Locked decisions:
1. **Batch tool.** Add one MCP tool (working name `perform_actions`). The agent passes a short, fully specified list of
   existing actions (click, type_text, press_key, set_value, scroll, perform_secondary_action). The server runs them
   back-to-back, stops at the first failure, and returns one final state plus a per-step outcome. The server never
   chooses steps. Scope lock `mcp-server-never-owns-a-goal` stays intact; no decide_and_act lease.
2. **Permissions.** DONE 19:52: `permissions.allow: ["mcp__open-computer-use"]` added to `~/.claude/settings.json`
   (user chose all OCU tools, including actions).
3. **Screenshots.** Action results are text-only by default. A screenshot is attached only on request, or when the
   accessibility tree is empty. `get_app_state` behaviour is unchanged unless the plan finds a reason.
4. **jev.** Persist the resolved letter table on disk per (base_url, model) in the 0600 config dir. Keep the
   one-ephemeral-session-per-request transport; no keep-alive.
5. **Server fast path**, implied by the outcome: skip the redundant pre-action snapshot when a fresh cached one exists,
   trim fixed sleeps where they are safe, and shorten the cursor travel animation. Every change needs its own
   measurement.
6. **Agent guidance.** The MCP instructions and skill docs stop telling agents to call `get_app_state` after every
   action, and teach batching.

Non-goals: server-side planning or goal loops; HTTP keep-alive for jev; Linux/Windows runtimes (Go) unless the batch
tool is trivially portable there; changing the TCC/peer-auth trust model.

Acceptance (measured on the Mail "combio" search flow, same Mac):
- The same flow needs at most half the agent turns (18 → ≤9).
- Median server time per single action call on Mail drops by at least 30% (4.5s in session, ~3s server-side).
- A warm `decide_next_action` against remote jev completes in ≤3s, and a cold one no longer times out after the first
  success.
- `swift test` is green; new tests cover batch semantics (stop on first failure, per-step results, index resolution),
  the text-only default, and the letter-table disk cache (0600, invalidation on model/base_url change).

## Addendum 2026-09-29 20:12 — scope expansion (user: "also expand the open-computer-use to use other way faster than screenshot to interact with macos app, like run apple scripts, or something")

Locked decisions (user answers):
7. **Fast channels, all four:**
   - `run_script`: AppleScript/JXA against an app's scripting dictionary.
   - A scripting-dictionary lookup tool: the app's sdef commands and classes.
   - `find_elements`: a targeted AX search with early stop, instead of a full tree walk.
   - Shortcuts / URL-scheme launch.
8. **Script guard:**
   - Opt-in by an env flag, off by default.
   - Runs in the MCP server process and never through the app-agent socket (see memory `app-agent-ipc-confused-deputy`).
   - A best-effort text filter rejects `do shell script`, `run script` and `load script`. It adds friction; it is not a security boundary, and the docs must say so.
   - Every script text is logged.
   - Automation TCC asks once per target app.
9. **Guidance:** script first when the app's dictionary covers the task, then find_elements plus the batch tool for UI work, then full get_app_state only when neither fits or to verify. Replaces the current "Avoid falling back to AppleScript" instruction.
10. **Delivery:** one plan, two PRs.
    - PR A: speed work (decisions 1–6).
    - PR B: fast channels (7–9), with a security review.
11. **Snapshot capture:** a text-only snapshot must also skip the SCScreenshotManager capture, not just the attachment. Capture currently runs inside SnapshotBuilder.build on every snapshot (AccessibilitySnapshot.swift:393).

Additional acceptance (PR B), measured on Mail:
- A Mail search via `run_script` returns results in ≤1s.
- `find_elements` for one button on Mail runs ≤50% of a full get_app_state.
- With the flag unset the script tool is not listed.
- With the flag set, the shell-verb filter rejects a script (unit test).
- Script execution never crosses the app-agent socket (test or code-path assertion).

Risk revision: PR B adds a code-execution surface, so risk for PR B is high. PR A stays medium.

## Addendum 2026-09-29 20:50 — brainstorm gate decisions (user answers)

12. **Track A design = Proposal A** (thin `perform_actions` runner: validate all steps first, pinned snapshot resolves `element_index` only, one final text state; capture policy with text-only default and the coordinate frame carried forward; cursor travel capped ~0.3s; one settle constant; jev letter disk cache). Advisor corrections are acceptance criteria:
    - Batch steps read focus, window bounds and frames LIVE; a unit test fails if `type_text` in a batch uses the pinned snapshot's focus.
    - Guidance keeps "call get_app_state at the start of each turn"; drops only "after every action".
    - `MCPServer.swift` tool-list line names `perform_actions`; both tool-count tests updated (OpenComputerUseKitTests:256, DecisionAdvisorTests:437) plus docs/ARCHITECTURE.md and SKILL.md tool lists.
    - Cursor cap lives in `SoftwareCursorOverlay.animateMove` only; `CursorMotionModel.swift` and its tests stay byte-identical; one new cap test.
    - Final-snapshot failure still returns the per-step lines. jev disk entries carry `resolved_at`; letter progress persists as letters resolve.
    - Metric defined before code: server-side, direct stdio, per tool, combio call mix, baseline on afb60fa.
13. **Widened decision 5 (user-approved):** PR A also batches AX attribute reads (`AXUIElementCopyMultipleAttributeValues`) in the snapshot walk. Concurrent jev stage-1 pages remain OUT.
14. **Track B design = P2 + all 8 advisor amendments** (relay-local router `LocalChannelRouter.run(forward:)` covering the relay and both direct paths; `/usr/bin/osascript` child with fds 0–2 only, scrubbed env, timeout then SIGKILL; metadata-only stderr, full text in a 0600 O_NOFOLLOW|O_APPEND log; keep "Avoid falling back to AppleScript" while the flag is off; no OpenComputerUseCLI change, test that `call run_script` fails closed; sdef XInclude only inside the bundle or /System/Library/ScriptingDefinitions, no network/external entities; find_elements indices from a never-resetting counter, merge only on matching targetWindowID, per-hit position/size/actions; open_url blocks dangerous schemes AND Terminal/iTerm/Script Editor/Shortcuts handlers).
15. **Decision 8 reading (user):** a short-lived osascript child of the relay satisfies "runs in the MCP server process, never through the app-agent socket".
16. **Script review (user):** narrow the `mcp__open-computer-use` blanket allow to named tools so run_script / run_shortcut / open_url go through the auto-mode classifier. Main loop edits ~/.claude/settings.json when PR B is ready for live testing (tool names final then).

## Addendum 2026-09-29 22:53 — Mail script target revised (user, after phase-00 timing)
17. Measured: a full-inbox `whose subject contains "combio"` in Mail takes 20s warm (49–66s on repeats) with osascript itself at ~0.06s CPU, so Mail itself is the bottleneck. The PR B acceptance line "Mail search via run_script ≤1s" is replaced by:
    - `run_script` against Mail on a NARROW target (the selected message, or the newest N inbox messages) returns in ≤1s, median of 5 warm runs, from a non-cmux host.
    - Guidance: full-mailbox search goes through Mail's own search field via find_elements + perform_actions (Mail's index). The docs warn that large `whose` queries stall Mail for 20–60s, and that stall also blocks get_app_state/find_elements on Mail.
    - Docs note that cmux SIGTERMs app-targeting osascript children (memory `cmux-kills-osascript-children`), so run_script fails when the host runs under cmux.

## Addendum 2026-09-29 23:17 — decision 18 (user, after Track A code review)
18. (a) Text-only action results fall back to a screenshot when the window has no content elements: the menu bar and the window root do not count toward "non-empty". (b) perform_actions fails closed when any step uses element_index and there is no cached app state for that app (error asks for get_app_state first); x/y and key-only batches still run.

19. (2026-09-29 23:39, user, verbatim) "open-computer-use should control and screenshot the app in the background and task manager and should not take the focus while i'm working on other tab or app". Background operation is a hard requirement: no activation, raise, or focus theft of the target app, for the product and for every bench/acceptance run. The counsel's "run the bench with Mail frontmost" fix is rejected. The bench focus guard must use a signal that works in the background, and it still fails closed so that no keystroke ever reaches the message list.

## Addendum 2026-09-29 23:48 — decision 20 (user, after background-focus root cause)
20. The background-focus fix goes INTO Track A (PR A). type_text (single call and perform_actions step) never activates the target: when no text focus can be confirmed in the background, it fails with a clear error (no SkyLight synthetic focus). Focus detection adds a background signal: per-element AXFocused (prefetched) as a fallback when the app-level AXFocusedUIElement is nil. Default-path activation elsewhere (launching a non-running app, snapshot window recovery) also stops taking focus. Opt-in paths (global pointer fallbacks env, sky_click, explicit Raise) stay as they are. Bench runs use G1 (focus line on the search field + value checks) plus G2 (frontmost-app tripwire around every call).

## Addendum 2026-09-30 00:14 — decision 21 (user, after live background probe)
21. Spike an AX element-focus write: set the target text field's own AXFocused=true (accessibility attribute write; no app activation, no SkyLight), then deliver keys to the app's pid. If Mail accepts keyboard input into the search field while inactive, fold it into Track A (click on / type into a background text field); if not, fall back to a background-safe bench flow (value write + click + clear, no search submission).

## Addendum 2026-09-30 00:34 — decision 22 (user, after Stage Manager finding)
22. Measured: under Stage Manager an off-stage window (Mail, Finder) returns no screenshot; the grant is fine (the on-stage app returns an image). User chose "Investigate a fix first" and said: "try to find a way to work with app in stage manager". Spike background capture of off-stage windows (no activation, no bringing the window on stage, per decision 19) before the benchmark resumes.

## Addendum 2026-09-30 00:52 — decision 23 (user, after Stage Manager spikes)
23. Off-stage (Stage Manager strip) windows: no non-disruptive way exists to bring them on stage or capture them at full size (AXRaise, WindowManager AXAddToStage, pid-posted shift-click all no-ops; SCK/CG/SLS capture return only the thumbnail). User chose "Text-only when off stage": get_app_state and action results return the full AX tree plus a clear note that the window is off stage in Stage Manager and has no screenshot; element_index actions keep working; x/y clicks on such a window fail with a clear error. Never switch stages, activate, or move the cursor. Bench runs BOTH scenes (user answer 00:45): off stage (text-only, both builds) and on stage (user drags Mail into the current stage set; Mail stays inactive).

24. (2026-09-30 08:25, user, ship gate) Per-call L2 missed (0.955 on / 0.944 off; floor = post-action AX snapshot build). Before PR A, add a tree-read fix: cache repeated subtree walks and prefetch children (render output must stay byte-identical), then re-measure L2. Turns gate amended: median T(HEAD) <= 9 AND <= max(1, 0.5 x median T(B0f headless)) per scene (T=1 is the floor for element-targeted flows).
25. (2026-09-30 08:25, user) decide_next_action cascadeGuide truncation (pre-existing) is a follow-up done with Track B's 2048-char instructions re-budget; PR A lists it as a known limitation. Live L4 (jev) and L5 (visual) run now.
