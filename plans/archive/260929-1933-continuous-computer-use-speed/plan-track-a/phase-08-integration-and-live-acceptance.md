# Phase 08: Integration gate and live acceptance (workflow part G, then MAIN LOOP part L)

- **Depends on:** phases 01–07 committed on `feat/continuous-computer-use-speed`.
- **Blocks:** PR A creation and the ship gate, which the main loop owns.
- **Effort:** 0.5h for G and about 2h for L.
- Worktree `W` is as defined in phase 01. `BENCH`, `SERVER`, `DATA` and `NS` are as defined in phase 00 B-4.

## Part G: Workflow gate (non-live; may run in a workflow)

### Task G.1: Full suite, twice
- Verify: `cd $W && swift test 2>&1 | tail -15` exits 0 and contains `with 0 failures`, on two consecutive runs. A second-run failure means state leaked, for example through the jev disk cache.

### Task G.2: Invariants (mechanical)
Every one of these must hold:
- `git -C $W diff --stat afb60fa -- packages/OpenComputerUseKit/Sources/OpenComputerUseKit/CursorMotionModel.swift` prints nothing (correction 5).
- `sed -n 16p $W/packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MCPServer.swift` prints exactly the AppleScript line, which Track B owns.
- `git -C $W diff --name-only afb60fa` lists **only** files that appear in a TARGET of phases 01–07. Nothing from Track B's owns list may appear: `MacOSAppAgentProxy.swift`, `OpenComputerUseMain.swift`, `MCPAppRuntime.swift`, `MacSessionGuard.swift`, and no entitlements or Info.plist.
- `git -C $W log --format=%s afb60fa..HEAD` shows exactly these subjects, in this order. The 0.1s settle trim was dropped by user decision, so there is no trim commit.
  1. `perf(snapshot): skip window capture for text-only action results`
  2. `perf(cursor): cap visual cursor travel at 0.3s`
  3. `refactor(actions): name the post-action settle interval`
  4. `perf(snapshot): read per-node AX attributes in one round trip`
  5. `feat(actions): add perform_actions to run a short action sequence in one call`
  6. optional, zero to two times, only after a failed live batch check: `fix(actions): lengthen the post-action settle interval` (phase 03 pre-authorized raise; the constant must be ≤ 0.3)
  7. `feat(decision-model): persist the jev letter table per backend`
  8. `docs(guidance): teach batching and stop per-action get_app_state`
  (If a settle raise lands after 06 or 07, it may appear later in the list; its position does not matter, its value cap does.)
- The service invariants from phases 01, 03 and 05 still hold at HEAD (`S` as in phase 01): `style: .actionResult` appears once, inside `finishAction`; `grep -c 'screenshotToGlobalPoint' $S/ComputerUseService.swift` prints `3` (definition plus drag's 2 calls); `typingTargetElement(` appears twice (declaration plus the call in `typeText`); `grep -c 'focusedElement: snapshot.focusedElement' $S/ComputerUseService.swift` prints `0`; and `grep -n 'let postActionSettleInterval' $S/ComputerUseService.swift` shows a value ≤ 0.3.
- `git -C $W diff afb60fa -- packages apps skills docs | grep -nE '^\+.*(plan-track-a|phase-0[0-9]|Phase 0[0-9])'` prints nothing. Rule: no plan IDs in code or docs (review-audit rules).
- `cd $W && ./scripts/ci.sh` exits 0. It runs check-docs, repo hygiene, action pinning, and the Go and Python tests. Use `PATH=/usr/bin:$PATH` if python3 is SIGKILLed (memory `python3-sigkill-is-the-framework-build-only`).

## Part L: Live acceptance (MAIN LOOP ONLY; one track at a time on this Mac)

Use phase 00's bench setup throughout. The per-lever runs M1–M6 are defined in phases 01–06. If they were not run as each phase landed, run them now in order: C1, C2, C3, C4, C5, C6. Check out each SHA in the bench worktree.

### L1: Fixture smoke
- In the bench worktree at HEAD, run `./scripts/run-tool-smoke-tests.sh`.
- Pass: exit 0. It asserts 10 tools, runs the full smoke including step `11. perform_actions` (click, type_text, press_key in one batch, then a batch with a bad `element_index` that must fail naming step 2 and leave the fixture unchanged), and runs the cursor-idle smoke. This is the first end-to-end run of `perform_actions` through the dispatcher and the service; run it before L2.

### L2: Final speed matrix at HEAD against B0
- Run `MEASURE(F, <HEAD>, extras: cycle --cursor off, gas, batch)`, then `summarize "$DATA"/*.jsonl --baseline B0 --candidate F`.
- Pass, all of:
  - the line `cursor=on: F / B0 = r` shows **r ≤ 0.700** and verdict `PASS`. Acceptance-grade runs require **zero error calls** (non-warm-up) in the `cycle` records of both labels; `summarize` prints `INVALID` instead of `PASS` when either label has any, and an INVALID run is re-run after fixing the scene, never accepted;
  - `batch` completed its no-Return probe round and 10 rounds, each guard-checked (`Step N … : ok` plus `require_search_value` on the batch result). If it aborts because steps outran Mail, apply the phase 03 pre-authorized settle raise (≤ 0.3s) and re-run L2 at the new HEAD.
- Report beside the gate: the combio-weighted **mean** ratio that `summarize` prints next to the median (it shows the keyboard-path gains the click-dominated median hides; not a gate), and the cursor-off line (not a gate).

### L3: Turns (decision-1 and decision-6 outcome)
Run 3 headless sessions per build, on B0 (the control) and on HEAD. Fixed conditions, identical for both builds:
- **Model.** Pin one model id with `--model <MODEL_ID>` on every run of both builds. Record the id; a run without it is not acceptance-grade.
- **Guidance the agent sees.** The agent sees exactly the build's own MCP server instructions (from its `MCPServer.swift`) plus that build's `skills/open-computer-use/SKILL.md` and `skills/open-computer-use/references/usage.md`, read from the bench worktree checked out at the same SHA and injected with `--append-system-prompt`. `--strict-mcp-config` alone passes only the MCP instructions. Run from `$SCRATCH` (not a repo checkout), so no project `CLAUDE.md` or project skill loads. Before the first run, check for a user-level or plugin copy of the open-computer-use skill (`ls ~/.claude/skills`, `claude plugin list`); if one exists, add `--disable-slash-commands` (confirm the flag with `claude --help`) so it cannot load, or, if the flag is unavailable, record the copy and its version as a confound shared by both builds.
- Write an MCP config file in the scratchpad, for example `$SCRATCH/ocu-bench-mcp.json`:
  ```json
  {"mcpServers":{"open-computer-use":{"command":"<SERVER>","args":["mcp"],"env":{"OPEN_COMPUTER_USE_AGENT_SOCKET_NAMESPACE":"ocu-speed-bench"}}}}
  ```
- Run:
  ```bash
  cd "$SCRATCH" && git -C "$BENCH_WT" checkout --detach <SHA of the build under test>
  claude -p "Using Computer Use on the Mail app, search all mailboxes for 'combio' and list the subjects of the first five results. Do not open, send, delete, move, or modify any message." \
    --model <MODEL_ID> \
    --append-system-prompt "$(cat "$BENCH_WT/skills/open-computer-use/SKILL.md" "$BENCH_WT/skills/open-computer-use/references/usage.md")" \
    --strict-mcp-config --mcp-config "$SCRATCH/ocu-bench-mcp.json" --allowedTools "mcp__open-computer-use" \
    --output-format json > "$SCRATCH/turns-<label>-<n>.json"
  ```
  (`BENCH_WT=/Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/ocu-speed-bench`, the same worktree whose build `SERVER` points to. Build and restart the agent for that SHA first, per phase 00 B-2 and B-3, so the injected guidance and the running server come from the same commit.)
- Take `session_id` from each output. Then apply the gate in one command:
  ```bash
  /usr/bin/python3 "$BENCH" turns --transcript <3 HEAD transcripts> --control <3 B0 transcripts>
  ```
  Transcripts are at `~/.claude/projects/<slug of $SCRATCH>/<session_id>.jsonl`.
- Pass: the `TURNS GATE` line shows `PASS`, which means the median `agent_turns(T=calls-1)` over the 3 HEAD runs is **≤ 9 AND ≤ 50% of the median over the 3 B0 headless control runs**. The relative bound keeps the gate from passing vacuously when the headless control is already low. Report both medians, the model id, and the locked baseline T0 = 18.
- After each run, reset Mail: empty the search field and select Inbox.

### L4: jev
- Run M6 from phase 06 at HEAD.
- Pass: `J_warm` median ≤ 3.0s, and `J_cold` after the first success is not an error.
- If vm100 is overloaded, record it, re-run when idle, and escalate to the user if it still fails.

### L5: Visual and UX
- One single click on Mail with cursor on: the arc and pulse are visible, and travel is about 0.3s.
- One x/y click after a text-only action result, using coordinates from the last `get_app_state` screenshot, hits the intended element (the carried-frame check).
- One x/y click after resizing the Mail window returns the `screenshotFrameMismatchMessage` error rather than clicking.
- Restore the window size afterwards.

### L6: Cleanup
- Kill the bench agents (phase 00 B-3).
- Remove the bench worktrees.
- Delete any `--save-dir` text dumps.
- Keep `$DATA/*.jsonl`. They hold timings only, with no content.

## Acceptance (Track A done = all observable)

| Criterion (outcome lock) | Evidence |
|---|---|
| Turns 18 → ≤ 9 | L3: median T(HEAD) ≤ 9 and ≤ 0.5 × median T(B0 headless), same pinned `--model`, same guidance source rule |
| `M_server` down ≥ 30% | L2: `F / B0 ≤ 0.700` with cursor on, verdict `PASS` (zero error calls); weighted mean ratio reported beside it |
| jev warm ≤ 3s; cold no timeout after first success | L4, plus the phase 06 unit test "disk hit makes 0 /tokenize" |
| `swift test` green, with new tests for batch semantics, the text-only default and the letter-table disk cache | G.1, plus phases 01, 05 and 06 test classes |
| Every lever measured on its own | M1–M4 table (capture, cursor, settle as a no-regression refactor, AX batch) with per-tool deltas; any settle raise recorded with its value and delta |
| Advisor corrections 1–5 and the final-snapshot rule | phase 05 focus test, focus-wiring grep and result-shape tests; phase 07 test; G.2 invariants; phase 02 cap test |
| `perform_actions` works end to end | L1 smoke step 11 (stop at a bad index), L2 guarded batch |
| Element-index clicks do not fail on a frame mismatch | phase 01 invariant: only drag calls `screenshotToGlobalPoint` |

## Rollback

- Before merge: `git reset` is not needed. Drop the branch, or revert individual phase commits in the reverse dependency order: 07 → 06 → settle raise (if any) → 05 → 04 → 03 → 02 → 01.
- After merge: revert the squash or merge commit on main through a PR (memory `merge-requires-review-and-branch-pr-even-for-chores`). No data migration is involved. The jev-letters directory is inert to older builds.

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
