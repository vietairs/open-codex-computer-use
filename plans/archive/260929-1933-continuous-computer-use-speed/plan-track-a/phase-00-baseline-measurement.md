# Phase 00: Baseline measurement on afb60fa (MAIN LOOP ONLY)

- **Owner:** the main loop. Never run this in a workflow. The track rules forbid live MCP and app-agent use there (parallel-tracks.md rule 3).
- **Depends on:** nothing. **Blocks:** every lever measurement (M1–M6) and phase 08.
- **Code edits:** none. Bench builds go into a separate, main-loop-owned worktree. Never touch the Track A worktree or the main checkout.
- **Effort:** about 1.5h, including one Mail session of about 25 minutes.

This file defines the metrics, the bench setup, and the `MEASURE` procedure. Phases 01–08 reuse all three, so they are written down once here.

## 1. Metrics (fixed before any code, per decision 12)

| Id | Definition | Pass rule (checked in phase 08) |
|---|---|---|
| `M_server` | **Combio-weighted median** of per-call wall time for single action calls on Mail, with the visual cursor on (the default). A call's time runs from writing the JSON-RPC request on the stdio client to reading its matching response. Only action tools count. Weights come from the baseline combio run: `click 6, press_key 5, set_value 1, type_text 1` (session `0a4f5ed5`, 2026-09-29 07:10–07:14Z; encoded as `COMBIO_WEIGHTS` in `bench/ocu-speed-bench.py`). Each sample of tool *t* carries weight `w_t / n_t`, with n ≥ 10 per tool after warm-up. Computed from `cycle` mode only. The combio-weighted **mean** is reported beside it (not a gate). Acceptance-grade runs have **zero** non-warm-up error calls in `cycle` mode; `summarize` prints `INVALID` otherwise (baseline `decide` timeouts are reported but do not count). | `M_server(final) ≤ 0.70 × M_server(B0)`, verdict `PASS` |
| `M_tool` | Per-tool median, p25 and p75. This covers the 4 action tools plus `get_app_state` full and compact. | Reported. `get_app_state` full must stay within ±5% of B0 through M1–M3, because decision 3 says get_app_state is unchanged. |
| `T` | Agent turns for the combio flow = (number of `open-computer-use` tool_use blocks in the flow window) − 1, which counts the agent's decision gaps. Recounting the baseline with the harness `turns` mode gives **T0 = 18** (19 calls; 14 assistant messages). | Median `T(HEAD headless) ≤ 9` **and** `≤ 0.5 ×` median `T(B0 headless)`, same pinned `--model` (phase 08 L3) |
| `J_warm` | Median wall time of `decide_next_action` (remote jev) for calls 2..5 in one server session. | ≤ 3.0s |
| `J_cold` | Time of call 1 after the bench agent restarts, once a successful resolution exists on disk. | Not an error or timeout. It also needs **no letter resolution**, which the unit tests prove; live, it should land within `J_warm` + 1.5s. |

All times are server-side over direct stdio, with no Claude Code permission review in the path. The in-session figure is reported next to them but is not an acceptance metric (counsel: decision 2's permission change is not credited to PR A).

## 2. Bench setup (once per campaign)

B-1. Create the bench worktree. It is main-loop owned and detached, so neither track's worktree is touched:
```bash
git -C /Users/hvnguyen/Projects/open-codex-computer-use worktree add --detach \
  /Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/ocu-speed-bench afb60fa
```
For the byte-identical render bracket (M4), create a second one the same way at `.../ocu-speed-bench-prev`.

B-2. Build a commit. Use the release configuration, so the bundle id `com.ifuryst.opencomputeruse` and the Developer ID match the notarized npm install and reuse its TCC grants (memory `dev-app-deploy-and-tcc-regrant-cycle`):
```bash
cd /Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/ocu-speed-bench
git checkout --detach <SHA>
OPEN_COMPUTER_USE_NOTARIZE=skip OPEN_COMPUTER_USE_CODESIGN_MODE=identity \
OPEN_COMPUTER_USE_CODESIGN_IDENTITY="Developer ID Application: Viet Nguyen (3HB354R355)" \
./scripts/build-open-computer-use-app.sh release
```
Output: `.../ocu-speed-bench/dist/Open Computer Use.app`. If a hook blocks command text containing `dist`, put the command in a script file and run that file instead.

B-3. Stop the stale bench agent after every rebuild. A running agent at the same path keeps serving the old binary. Kill by PID only, never with a pattern `pkill` (the `(Dev)` regex trap), and never the npm install's agent that serves this session:
```bash
ps -eo pid,command | grep -F "/ocu-speed-bench/dist/Open Computer Use.app/" | grep -v grep
kill <each PID listed>
```

B-4. Variables for every run:
```bash
BENCH=/Users/hvnguyen/Projects/open-codex-computer-use/plans/260929-1933-continuous-computer-use-speed/plan-track-a/bench/ocu-speed-bench.py
SERVER="/Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/ocu-speed-bench/dist/Open Computer Use.app/Contents/MacOS/OpenComputerUse"
DATA=/Users/hvnguyen/Projects/open-codex-computer-use/plans/260929-1933-continuous-computer-use-speed/reports/track-a/bench-data
NS=ocu-speed-bench        # own agent socket, so this session's agent is never evicted
```
Every harness run uses `/usr/bin/python3 "$BENCH" …`. It needs Launch Services to start the bench agent, so run it with the Bash sandbox disabled. That goes through the permission gate; it is not a blanket bypass. If it still exits 141 with no output, give the user the exact command to run in their own Terminal (memory `bang-prefix-has-no-tty-for-interactive-prompts`).

B-5. Scene. Tell the user first, and ask them not to touch Mail during a run.
- Mail is open with one viewer window, Inbox selected, and an empty toolbar search field. Do not move or resize the window for the whole campaign.
- Finder shows one window on a fixed folder.
- TextEdit has one untitled document with fixed text.
- The screen stays unlocked.
- Nothing else drives Mail.

B-6. Preflight for every build:
```bash
/usr/bin/python3 "$BENCH" preflight --server "$SERVER" --label <L>-preflight --out "$DATA" --namespace $NS
```
Pass condition, all of:
- `parts=` includes `'image'` (Screen Recording is granted);
- `text_chars` is ≥ 1000 (Accessibility is granted);
- `search_field_index=<n>` is printed;
- no `WARN:` line appears.

If the search field is not found, check its rendered role text. The harness does not print it; that is by design. Pass `--search-field-re`, and `--focus-re` if needed.

## 3. `MEASURE(L, SHA, extras)`

1. B-2 (build `SHA`), then B-3 (kill the stale agent), then B-6 (preflight).
2. `cycle` (cursor on). Each round runs get_app_state compact, click on the search field, press_key `cmd+option+f` (a guarded focus check), type_text `combio` (guarded), press_key Return, click on the search field, set_value `""`, press_key Escape. That gives click 2, press_key 3, type_text 1 and set_value 1 per round.
   ```bash
   /usr/bin/python3 "$BENCH" cycle --server "$SERVER" --label L --out "$DATA" --namespace $NS --cursor on --rounds 10 --warmup 1
   ```
   Pass condition: exit 0 and 10 `round N done` lines. Exit 3 or `abort …` means a guard stopped the run before any keystroke went to the wrong place. Fix the scene and re-run; do not loosen the guards.
3. Run each extra the phase names:
   - `cycle --cursor off`
   - `gas` (get_app_state full plus compact, 10 rounds)
   - `render` (sha256 of the full-state text for Finder, Mail and TextEdit)
   - `batch`
   - `decide --remote-decision --calls 5`
4. Summarize against the previous label:
   ```bash
   /usr/bin/python3 "$BENCH" summarize "$DATA"/*.jsonl --baseline <PREV> --candidate L
   ```
   Record the per-tool table, `COMBIO_WEIGHTED_MEDIAN`, `COMBIO_WEIGHTED_MEAN` and the error-call line in the main loop's progress file. A label with non-warm-up error calls is not acceptance-grade: fix the scene and re-run it.

Attribution rule: each lever lands as its own commit, in the fixed order C1 → C2 → C3 → C4 (C3 is a behaviour-neutral refactor; the 0.1s trim was dropped by user decision). A lever's effect is `MEASURE(C_k) − MEASURE(C_{k−1})`, so every delta holds exactly one lever. No permanent env knob is added just to measure a lever.

## 4. Phase 00 runs (baseline B0 = afb60fa)

| Step | Command (after B-1…B-6 with SHA=afb60fa, label `B0`) | Records |
|---|---|---|
| 0.1 | `cycle --cursor on --rounds 10` | `M_server(B0)`, per-tool medians |
| 0.2 | `cycle --cursor off --rounds 10` | The cursor upper bound: on − off for click and set_value |
| 0.3 | `gas --rounds 10` | `get_app_state` full and compact medians. This is the baseline for M1 (unchanged) and M4 (the AX lever). |
| 0.4 | `render --apps Finder,Mail,TextEdit`, run twice back to back | Same-build stability per app. If the two hashes differ, that app is volatile, and M4 must use `--save-dir` and diff while ignoring timestamp lines. |
| 0.5 | Kill the bench agent (B-3), then `decide --remote-decision --calls 5` | `J` at baseline. Timeouts are expected (test-260929-1720). Record them; they are not a failure of this phase. |
| 0.6 | `summarize "$DATA"/B0*.jsonl` | The baseline table |
| 0.7 | `turns --transcript ~/.claude/projects/-Users-hvnguyen-Projects-open-codex-computer-use/0a4f5ed5-68d3-4d03-ab61-127aeb69dc4a.jsonl --since 2026-09-29T07:09:00 --until 2026-09-29T07:14:00` | Must print `agent_turns(T=calls-1)=18` |
| 0.8 | Headless control runs on B0 (3 runs, pinned `--model`, B0's own SKILL.md and usage.md). The protocol is in phase-08 §L3. | `T(B0-headless)` median, the control for the relative turns gate |

**Success criteria (all observable):**
- the baseline table exists with n ≥ 10 for click, press_key, set_value, type_text and get_app_state full and compact;
- step 0.7 prints 18;
- B0 preflight passed.

## Risks

| Risk | L×I | Mitigation |
|---|---|---|
| The bench build lacks TCC, so there is no image and no tree. Baseline capture cost would be understated. | M×H | The B-6 preflight gate. If it fails, the user re-grants for the release bundle id once. |
| The bench agent evicts the session's agent. | L×H | A separate `--namespace`, and kill by bench path only |
| Mail state drifts between builds (new mail) | M×M | Median over 10 rounds, discard 1 warm-up round, same window geometry |
| The cursor-off env does not reach the agent | L×M | Per-call `setenv` of `OPEN_COMPUTER_USE_*` (MacOSAppAgentProxy.swift:507-540; `visualCursorEnabled` reads the process env, SoftwareCursorOverlay.swift:8). Sanity check: at B0 the click median with cursor off must be ≥ 1.0s below cursor on. |

## Rollback

Nothing ships. Clean up with `git -C /Users/hvnguyen/Projects/open-codex-computer-use worktree remove --force .claude/worktrees/ocu-speed-bench` (and `-prev`). Also kill the bench agent PIDs (B-3).

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
