# Phase 06 gate report: decision-model eval run

Worktree: `.claude/worktrees/decision-model` (branch `feat/decision-model`). PHASE_BASE = `a51ab60e249b010f3d88e35004b4d87db42e6880`.
Commits: `c472a58` (metrics and runner), `8c2b121` (tuning round 1), `721a649` (tau and summary).
Committed aggregate: `scripts/decision-model/eval-data/summary.json`. Raw harness lines stay local under `artifacts/decision-eval/` (gitignored, 0 tracked files).

## Setup

- Dataset: 254 items (27 fixture, 227 real). Split: 175 dev, 79 test. 198 targeted items (click, set_value, scroll): 134 dev, 64 test.
- Model: `qwen3.5-4b-q4km` (sha256 `00fe7986…11a4`). llama.cpp pin `b10964-b29c606e2`.
- Hardware: Apple M4 Max, 48 GB. The p50 gate is specified for a 16 GB M-series machine, so the latency figures below are an **optimistic bound (M4 Max 48 GB)**.
- One harness process per run, with 3 fixture warm-up lines discarded. The run made 257 llama-server requests for 257 decisions (254 items plus 3 warm-ups).
- llama-server timings from the sidecar log, over 254 prefill requests: prompt_n p50 624 and p95 1162 tokens; prompt_ms p50 512.5 and p95 1033.07. `cache_prompt` reuses shared prefixes between consecutive items, which is another reason the latency is optimistic.

## Gates (judged on the test split)

| Gate | Threshold | Test value | Result | Dev value (for reference) |
|---|---|---|---|---|
| top-1 accuracy | >= 0.80 | 0.443 | **FAIL** | 0.503 |
| margin AUROC | >= 0.70 | 0.8286 | **PASS** | 0.7585 |
| correct target pruned | <= 0.05 | 0.0938 (6 of 64) | **FAIL** | 0.1343 (18 of 134) |
| p50 decision latency | < 1500 ms | 509 ms (optimistic bound, M4 Max 48 GB) | **PASS** | 608 ms |

p95 latency: 913 ms on test, 1140 ms on dev. There were no harness errors (0 of 254).
P3 ("agents that follow the advice finish in fewer steps") was **not measured**, because it needs agent-in-the-loop A/B runs.

Pruned targets by cause:

| Cause | Dev | Test | All |
|---|---|---|---|
| not_actionable (absent from the compact view) | 12 | 5 | 17 |
| overflow (ranked beyond the single 52-row page) | 6 | 0 | 6 |
| duplicate_close | 0 | 1 | 1 |
| window_chrome | 0 (2 before tuning) | 0 | 0 |

## Tuning log (dev split only)

| Round | Change | Dev top-1 | Dev pruned-target rate |
|---|---|---|---|
| 0 | baseline | 0.4971 | 0.1493 |
| 1 | `window_chrome` keeps the chrome buttons when the goal names the window or the display (a new unit test was added first and failed before the change) | 0.5029 | 0.1343 |

The tuning trigger held (dev pruned rate above 0.05, and overflow accounted for 6 dev pruned targets). I stopped after one round for two reasons:

- The 12 `not_actionable` targets are list, outline, and sheet rows that the compact view never emits. Fixing them means changing `AccessibilitySnapshot.swift`, which is FORBIDDEN in this phase.
- All 6 `overflow` targets come from one column-view snapshot with 168 actionable rows. Five of them are unnamed icon buttons whose rows carry only geometry, and one is a search field that has no lexical overlap with its goal. No deterministic ranking rule could promote them without encoding that one snapshot, and the model would still see no name on the icon buttons.

## Tau

`selectTau` on the final dev results picked a margin of 0.7117. Rounded up, that gives **0.72**, which is now `DecisionAdvisor.recommendedMinMargin` and `summary.tau.value`.

| Split | Precision at 0.72 | Coverage at 0.72 |
|---|---|---|
| Dev | 0.90 | 0.1714 |
| Test | 0.9286 | 0.1772 |

## Failed gates

**top-1 accuracy (test 0.443, threshold 0.80).** The dev evidence points to three causes of roughly similar weight:

- **Wrong operation.** Dev operation accuracy is 0.686. The largest confusions are click predicted as press_key (10), done predicted as click (10; the model chose "done" for only 6 of 17 done items), click predicted as set_value (8), and set_value predicted as click (6). Only 5 of 19 set_value items got the right operation.
- **Wrong target.** When the correct target was offered, the model picked another element in 45 of 116 dev targeted items. The median page held 36 candidates.
- **Target never offered.** Pruning or the compact view removed the target in 18 of 134 dev targeted items.

The fixture items, which have simple and well-named controls, reach 13 of 18 on dev. The real-app items reach 75 of 157.

For a host, this means that unconditional advice is wrong more often than it is right. The advice is useful only above the recommended margin: at 0.72, about 17% of decisions qualify, and they are right about 90% (dev) to 93% (test) of the time. Everything else must fall back to `get_app_state` and the host's own judgement, which is what the cascade guide already says.

**Correct target pruned (test 0.0938, threshold 0.05).** On test, 5 of the 6 misses are elements that are absent from the compact view (`not_actionable`), and 1 is a `duplicate_close` drop. Dev shows the same dominant cause (12 of 18 are `not_actionable`), plus overflow on a single very large column-view snapshot. The compact view keeps only actionable roles, so sidebar entries, file-list rows, font-panel rows, and save-sheet suggestion rows are never candidates.

For a host, this means that for roughly 1 in 10 targeted decisions the advice cannot be correct, whatever the margin. A high-margin answer on such a screen points at a plausible but wrong element, and only the `chosen_row_text` check in the cascade guide protects against it. Closing this gap needs a compact-view change (P0) or stage-2 paging (K11, cut for v1). Both are outside this phase.

## Privacy checks (Amendment 8)

- These values were grepped over every file committed in this phase and over this report: the `id -un` value, the `scutil --get ComputerName` value, the `scutil --get LocalHostName` value, a hostname fragment seen in a local real capture, the eval-metrics test canary, and the macOS home-directory path prefix. Every count was 0, except that the canary appears only in `eval-metrics.test.mjs`, which is intentional.
- Across all tracked files in the branch, the `id -un` value appears in 3 pre-existing files under `plans/260720-1024-mac-session-guard-lock-detection/reports/`. They predate this phase and are not part of this work.
- The `id -un` value does not appear in the free-text notes or tuning notes in `summary.json`.
- Spot check: 5 distinctive compact-row strings taken from local real snapshots (5 different snapshots) each give `grep -c` = 0 against `summary.json`.

## Verification

- `node --test scripts/decision-model/eval-metrics.test.mjs`: 18 tests pass. Before the implementation existed, the run failed on the missing module.
- `node --check scripts/decision-model/eval-run.mjs` passes. `eval-run.mjs --prune-only --split all` exits 0.
- The summary acceptance script prints "summary ok".
- `recommendedMinMargin` is 0.72, matching the summary tau.
- `swift test`: 312 tests, 0 failures (2 skipped, both pre-existing).
- `git ls-files artifacts/decision-eval` returns 0 files.
- The `DecisionCandidatesTests.swift` numstat against PHASE_BASE shows 0 deleted lines.
- `make ci` is green (run with `PATH=/usr/bin:$PATH`).
- The sidecar was stopped with `stop-sidecar.sh`, and port 39501 is no longer listening.

## Unresolved questions

- Should the 3 pre-existing plan reports that contain the local username be scrubbed? They are outside this phase's ownership.
- Should v1 still ship with a pruned-target miss of about 9% that comes from the compact view? D2 says yes, reported and labelled experimental, but a P0 compact-view follow-up would be the fix.
