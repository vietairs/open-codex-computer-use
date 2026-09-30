---
title: "Track A (PR A): continuous computer use: speed"
description: "Faster server calls and fewer agent turns on Mail: text-only action results, cursor cap, one named settle constant, batched AX reads, a perform_actions batch tool, a jev letter disk cache, and new guidance."
status: pending
priority: P1
effort: 22h
branch: feat/continuous-computer-use-speed
tags: [performance, mcp, macos, batch, jev, tdd]
created: 2026-09-29
---

# Track A (PR A: speed): plan index

**Outcome.** The Mail combio flow needs at most 9 agent turns (18 today). Median server time per single action call drops by at least 30% against afb60fa. A warm remote-jev `decide_next_action` takes 3s or less, and a cold one stops timing out after the first success. `swift test` is green.

**Scope.** Outcome-lock decisions 1–6, 11, 12 and 13 are fixed; nothing here re-opens them. There is no server-side planner or goal loop (memory `mcp-server-never-owns-a-goal`).

**Status.** The user approved this plan on 2026-09-29 with all edits from the plan counsel ([counsel-plan-speed.md](../reports/track-a/counsel-plan-speed.md)) applied.

## User decisions (2026-09-29)

1. **hitTestElement geometry is fixed in phase 01.** It calls `windowPointToGlobalPoint` directly, which removes the latent double scaling and keeps the new frame-mismatch throw off element_index clicks. Invariant: only drag calls `screenshotToGlobalPoint`.
2. **Turns gate is relative as well as absolute.** Median T(HEAD headless) ≤ 9 **and** ≤ 50% of the median T(B0 headless) control, with the same pinned `--model` for both builds and each build's own SKILL.md and usage.md injected (phase 08 L3).
3. **Settle: no trim.** The 0.1s trim (formerly C3b) is dropped. The main loop is pre-authorized to raise the shared `postActionSettleInterval` to at most 0.3s if the live batch check fails (phase 03).
4. **Smoke suite.** Track A owns `apps/OpenComputerUseSmokeSuite/…/main.swift`: the count at :199-200 and one new fixture `perform_actions` step (click, type_text, press_key; a bad index stops the batch) (phase 05, run in phase 08 L1).
5. **Unchanged in PR A:** single `type_text` keeps reading focus from the snapshot, and compact `get_app_state` keeps its capture. Neither affects a gate, and both would change behaviour.
6. **jev TTL is 7 days** (`resolved_at`, phase 06).
7. **Acceptance-grade bench runs need zero error calls** (non-warm-up, in the `cycle` records that feed `M_server`), and the combio-weighted mean is reported beside the weighted median (phase 00, phase 08 L2).

**Mode.** `--tdd --advice`. Every phase lists its failing tests first. The Tester and the Implementer are different agents. Every leaf task carries `## Signature`, `## Boundaries` and `## Acceptance`, plus `## Contract Rules` and a `## Failure Protocol` that escalates to `kongming`. The plan is handover-ready for a downstream executor: stopping on a failed check is intended behaviour, not a stall.

Source read-only at afb60fa in `/Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/continuous-computer-use-speed`. Every `file:line` citation was re-verified there.

## Phases

| # | Phase | Runs in | Lever | Depends on | Status |
|---|---|---|---|---|---|
| 00 | [Baseline measurement on afb60fa](phase-00-baseline-measurement.md) | **main loop** | — | — | pending |
| 01 | [Capture policy, text-only results, coordinate frame carried forward](phase-01-capture-policy-text-only-results.md) | workflow | L1 capture skip | 00 | pending |
| 02 | [Cursor travel cap 0.3s](phase-02-cursor-travel-cap.md) | workflow | L2 cursor | 00 | pending |
| 03 | [One post-action settle constant](phase-03-post-action-settle-constant.md) | workflow | L3 settle (named, not trimmed) | 01 | pending |
| 04 | [Batched AX attribute reads](phase-04-batched-ax-attribute-reads.md) | workflow | L4 AX batch | 01 | pending |
| 05 | [`perform_actions` batch tool](phase-05-perform-actions-batch-tool.md) | workflow | turns | 01, 03 | pending |
| 06 | [jev letter disk cache](phase-06-jev-letter-disk-cache.md) | workflow | jev | 00 (Task 6.5 also needs 01, 03, 05) | pending |
| 07 | [Agent guidance and docs](phase-07-agent-guidance-and-docs.md) | workflow | turns | 05 | pending |
| 08 | [Integration gate (G) and live acceptance (L)](phase-08-integration-and-live-acceptance.md) | G: workflow; **L: main loop** | all | 01–07 | pending |

Measurement assets: [bench/ocu-speed-bench.py](bench/ocu-speed-bench.py) is a stdlib-only stdio MCP client with modes `preflight`, `cycle`, `gas`, `render`, `decide`, `batch`, `summarize` and `turns`. Its offline modes were self-tested: `turns` reproduces T0 = 18 from the baseline transcript.

## Dependency graph and parallelism

```
00 ──► 01 ──► 03 ──► 05 ──► 07 ──► 08
 │      └──► 04 ─────────────────►┘
 ├──► 02 ────────────────────────►┘
 └──► 06 (6.1–6.4) ── waits for 05 ──► 6.5 ──► 08
```

Parallel-safe sets (disjoint TARGET files):
- after 00: {01, 02, 06 Tasks 6.1–6.4};
- after 01: {03, 04} plus anything still running;
- after 03: {05, 04};
- after 05: {07, 06 Task 6.5}.

**Parallel rule.** Tester RED states are compile errors, and all new tests live in one test target (`OpenComputerUseKitTests`). One phase's RED therefore breaks `swift test` for a concurrent phase in the same checkout. Two ways to run safely:
- **(a) Default:** run phases one at a time in the Track A worktree, in the order 01, 02, 03, 04, 05, 06, 07.
- **(b)** If running in parallel, give each concurrent phase its own sub-worktree and `.build` directory branched from the same commit. The main loop then cherry-picks commits in the order above, so that lever attribution (C1 → C2 → C3 → C4) holds.

## File ownership (no two parallel phases share a file)

Paths are relative to `packages/OpenComputerUseKit/`.

| File | Owner phase(s): each runs sequentially after the previous one |
|---|---|
| `Sources/…/ComputerUseService.swift` | 01 → 03 → 05 → 06 (Task 6.5, `buildDecisionProvider` only); a pre-authorized settle raise (main loop, constant value only) lands after 05 |
| `Sources/…/AccessibilitySnapshot.swift` | 01 (capture region) → 04 (render reads) |
| `Sources/…/ToolDefinitions.swift`, `Sources/…/ComputerUseToolDispatcher.swift` | 01 (`include_screenshot`) → 05 (append `perform_actions`) |
| `Sources/…/SoftwareCursorOverlay.swift` | 02 |
| `Sources/…/AccessibilityAttributePrefetch.swift` (new) | 04 |
| `Sources/…/BatchActionRunner.swift` (new) | 05 |
| `Sources/…/DecisionJevPrompt.swift`, `DecisionJevClient.swift`, `DecisionRemoteBackend.swift`, `DecisionJevLetterDiskCache.swift` (new) | 06 |
| `Sources/…/MCPServer.swift` (lines 8, 10 and 14, plus an appended paragraph; **never line 16**), `skills/open-computer-use/SKILL.md`, `references/usage.md`, `docs/ARCHITECTURE.md`, `docs/histories/2026-09/*` | 07 |
| `Tests/…/OpenComputerUseKitTests.swift` (:256, :2963-2966), `Tests/…/DecisionAdvisorTests.swift` (:436-457), `apps/OpenComputerUseSmokeSuite/…/main.swift` (:199-200 plus one appended `perform_actions` step; Track A owns it, user decision) | 05 |
| New test classes: `ActionResultScreenshotPolicyTests`, `CursorTravelCapTests`, `PostActionSettleTests`, `AXAttributePrefetchTests`, `BatchActionRunnerTests`, `DecisionJevLetterDiskCacheTests`, `ServerInstructionsGuidanceTests` | 01, 02, 03, 04, 05, 06, 07 respectively |
| **Never touched by Track A:** `CursorMotionModel.swift` (0-line diff), `InputSimulation.swift`, `MacOSAppAgentProxy.swift`, `OpenComputerUseMain.swift`, `MCPAppRuntime.swift`, `MacSessionGuard.swift`, entitlements and Info.plist, the Go runtimes | — |

## Build and test commands (Track A worktree only)

```bash
cd /Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/continuous-computer-use-speed
swift build 2>&1 | tail -20
swift test --filter OpenComputerUseKitTests.<TestClass> 2>&1 | tail -30   # phase-level
swift test 2>&1 | tail -15                                                 # pass: exit 0 and "with 0 failures"
./scripts/ci.sh                                                            # phase 08 G.2 (PATH=/usr/bin:$PATH if python3 is SIGKILLed)
```

Never run `swift build` or `swift test` in the main checkout. Live runs (the bench, the smoke suite and headless turns) are main-loop only, from the separate `ocu-speed-bench` worktree (phase 00 §2).

## Test matrix

| Layer | What | Where |
|---|---|---|
| Unit (pure, no AX) and mechanical grep | Capture timing, attach rule, carried frame and fail-closed rule, `include_screenshot` schema and parsing; `style: .actionResult` only inside `finishAction`; only drag calls `screenshotToGlobalPoint` | phase 01 |
| Unit | Cursor cap; the model's tests stay unchanged | phase 02 |
| Unit and mechanical grep | Settle constant (0.15, raise ≤ 0.3 only on a failed live batch check); 7 gate literals untouched | phase 03 |
| Unit | Prefetch normalization (error sentinel → nil), routing, attribute list | phase 04 |
| Unit | Batch stop-on-first-failure, per-step lines, result shape, final-snapshot failure, lock mid-run, index resolution, recovery policy, **live focus** (unit test plus a wiring grep: `typeText` calls `typingTargetElement`, no helper gets `snapshot.focusedElement`), live geometry, upfront parse, registration, tool counts | phase 05 |
| Unit (temp dir, fake transport) | Disk cache 0600/0700, hit = 0 `/tokenize`, key change, invalidation, corrupt, unsafe or expired = miss, progress resume (17 requests), stale partial, default off | phase 06 |
| Unit | Instructions keep start-of-turn, drop per-action get_app_state, name `perform_actions`, line 16 byte-identical and in place | phase 07 |
| Integration (fixture, GUI) | Smoke suite: 10 tools, full smoke including a `perform_actions` step (3-step batch, then a bad index that stops the batch), cursor idle | phase 05 writes, phase 08 L1 runs |
| Live E2E (Mail) | Per-lever M1–M4, batch M5 (no-Return probe, value-checked rounds), jev M6, final matrix, render bracket, turns (relative gate), carried-frame x/y | phases 00, 01–06, 08 L |

## Acceptance criteria (measurable)

1. T(HEAD, median of 3 headless runs) ≤ 9 **and** ≤ 0.5 × T(B0, median of 3 headless control runs), both with the same pinned `--model` and each build's own SKILL.md and usage.md (baseline T0 = 18).
2. `M_server(HEAD) ≤ 0.70 × M_server(B0)` with cursor on (phase 00 §1 definition), from runs with zero non-warm-up `cycle` error calls; the weighted mean ratio is reported beside it.
3. `J_warm` ≤ 3.0s, and `J_cold` after the first success is not an error.
4. `swift test` passes twice in a row, including the 7 new test classes.
5. Per-lever deltas are recorded for capture skip, cursor cap, settle (a no-regression check, since it is a refactor) and AX batch (M1–M4). `get_app_state` full output is unchanged: it keeps the image, and its time is within ±5% through M1–M3.
6. Advisor corrections hold:
   - batch focus is live (a unit test);
   - start-of-turn guidance is kept;
   - `MCPServer.swift:10` names `perform_actions`, and all 5 count sites plus the smoke suite are updated;
   - the `CursorMotionModel.swift` diff is empty;
   - a final-snapshot failure keeps the step lines;
   - jev entries carry `resolved_at`, and progress persists per letter.
7. `perform_actions` passes the fixture smoke step (phase 08 L1) and the guarded live batch (phase 08 L2).
8. `hitTestElement` no longer goes through `screenshotToGlobalPoint` (phase 01 invariant).

## Backwards compatibility

- Public Swift signatures only gain defaulted parameters.
- `get_app_state` output is unchanged.
- Single-action results lose the attached screenshot by default. This is the intended contract change (decision 3), and `include_screenshot: true` restores it.
- x/y clicks after a text-only result keep today's scaling through the carried frame, or fail closed with a clear message.
- The jev disk cache is opt-in by construction: only the production `buildDecisionProvider` passes it. Older builds ignore the directory.
- The Go runtimes are unchanged. The docs say `perform_actions` is macOS-only.

## Top risks

| Risk | L×I | Mitigation (phase) |
|---|---|---|
| Batch steps outrun the app now that the implicit 1.3s refresh settle is gone | M×H | Inter-step settle, live focus, and the M5 live batch whose guard checks where the text landed (no-Return probe, `require_search_value`) (05); pre-authorized settle raise ≤ 0.3s (03) |
| AX multi-read changes the rendered text or trips `as!` | M×H | Sentinel normalization and the 3-app render bracket (04) |
| Text-only results break x/y scaling | H×H if unmitigated | Carried frame plus fail-closed, unit-tested and checked live in L5 (01) |
| The fail-closed throw leaks into element_index clicks through `hitTestElement` | H×H if unmitigated | `hitTestElement` uses `windowPointToGlobalPoint` directly; grep invariant (01) |
| The turns gate passes vacuously or varies with the model | M×M | Relative gate against the headless B0 control, pinned `--model`, fixed guidance source (08 L3) |
| jev tests pollute the real config directory | M×H | Disk cache nil by default, two-run verification (06) |
| Median misses −30% on a keyboard-heavy mix | M×M | 4 attributable levers, weighted-median definition fixed before code, escalation at L2 |
| The bench build lacks TCC, skewing the baseline | M×H | Release config, Developer ID signing, preflight gate (00) |

## Cross-track seams (for the main loop to relay to Track B)

- `MCPServer.swift`: A edits lines 8, 10 and 14 in place and appends one paragraph. Line 16 stays byte-identical and in place. B edits line 16, appends its own text, and resolves line 10 by hand on rebase.
- `ToolDefinitions.all`: A appends `perform_actions` last, so the count goes 9 → 10. `listed.count > all.count` stays valid. B's count is 10 → 11 after rebase, and B's plan must restate all 5 test sites plus smoke `main.swift:199`.
- Dispatcher: A adds one `case` and appends `extension ComputerUseToolDispatcher { parseBatchSteps }` at the end of the file.
- Service:
  - A keeps the single `snapshotsByApp` write point in `refreshSnapshot`, which gains a `capture:` parameter.
  - A's batch final refresh renumbers from 0 and replaces the cache. That conflicts with B's never-resetting index counter, so B merges its hook after that write point.
  - B's private multi-attribute reader is deduplicated against `AXAttributePrefetch` on B's rebase (parallel-tracks rule 6).

## Rollback

Every phase is one commit, plus at most two settle-raise commits if the live batch check needs them, so rollback is `git revert` in reverse dependency order: 07 → 06 → settle raise (if any) → 05 → 04 → 03 → 02 → 01. Phases 02, 04 and 06 revert independently. There is no data migration. The details are in each phase file.

## Unresolved questions

Resolved on 2026-09-29 (see User decisions): smoke suite ownership, single `type_text` live focus, compact `get_app_state` capture, the jev TTL, and the `hitTestElement` double scaling. Plan counsel ran as a kongming review ([counsel-plan-speed.md](../reports/track-a/counsel-plan-speed.md)).

1. **Turn metric.** T = OCU tool calls − 1 reproduces the locked 18. Counting assistant messages instead gives 14 at baseline. Confirm that "calls − 1" is the intended reading of "18 → ≤9".
2. **If warm jev stays above 3s** after the disk cache and the capture and AX speedups, the only remaining lever is running stage-1 pages concurrently, which decision 13 rules out. That needs a user decision, not an executor retry.
3. **Batch on a snapshot-cache miss.** When no state exists for the app, `performActions` builds a fresh pinned snapshot, so `element_index` values refer to a state the agent never saw. Should a batch with `element_index` steps fail closed on a cache miss instead? (Counsel question; the plan keeps the fresh-snapshot behaviour.)
