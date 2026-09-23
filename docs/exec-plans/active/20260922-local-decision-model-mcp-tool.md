# Introducing a local decision model on the MCP side (Jev-shaped constrained-choice readout)

## Goal

Without changing open-computer-use's identity as an MCP tool server, add a local, open-weight decision tool for the
host agent: prune the accessibility tree into an actionable candidate table, then use one forward pass to perform a
constrained-choice logit readout over that candidate set, returning the chosen operation, the chosen target element,
and the full probability distributions over both. The final shape is `decide_next_action`, a read-only MCP tool; the
host agent still initiates every action itself.

## Scope

- In scope: the compact actionable-candidate mode for `get_app_state` (P0); the local eval set and margin
  separability measurement (P1); the readout prototype on the `llama-server` sidecar (P2); the read-only
  `decide_next_action` MCP tool with its host-side cascade prompt (P3).
- Out of scope: server-side autonomous goal loops such as `run_goal` (rejected); bounded delegated execution via
  `decide_and_act` (P4, deferred, needs a separate decision and security review); packaging model weights into the
  npm package; changing the existing lock policy or peer-auth mechanism.

## Background

- Related docs: `docs/ARCHITECTURE.md`, `docs/SECURITY.md`, `docs/SUPPLY_CHAIN_SECURITY.md`, `docs/RELIABILITY.md`.
- Related code paths: `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/` (`AccessibilitySnapshot.swift`,
  `ToolDefinitions.swift`, `ComputerUseToolDispatcher.swift`, `ComputerUseService.swift`, `MacSessionGuard.swift`),
  `apps/OpenComputerUseLinux/`, `apps/OpenComputerUseWindows/`.
- Design source: a design-proposal artifact (rev 3, private) <https://claude.ai/artifact/KPS1j3Y2qvXXpnWbQZ941J>,
  drawing on `browser-use/jev-ultrafast`, SemIf (formerly openjev.com), and `awlevin/typesafe-computer-use`.
- Known constraints (all verified in this repo):
  - **No open-weight Jev model exists.** SemIf is a research demo; what transfers is the constrained-choice readout
    technique, not any weights.
  - **Candidate labels must be single tokens.** The Qwen-family tokenizer splits digits by character, so `[12]` is
    not one token; single-letter labels are used instead, capping candidates at about 52, while
    `AccessibilitySnapshot.swift`'s `defaultMaxNodeCount` is 1200. **Deterministic pruning is the hard part of this
    project, not inference.**
  - **Only an HTTP sidecar is cross-platform.** `Package.swift` declares only `.macOS(.v14)`; Linux/Windows are
    separate Go binaries (`main.go` embedding `runtime.py` over AT-SPI and `runtime.ps1` over the UIA bridge,
    respectively) with no Swift. Embedding llama.cpp or MLX-Swift would still cover macOS only.
  - 4B Q4 weights are about 2.5–3 GB and, with KV cache, need roughly 16 GB of unified memory; Intel Macs and CPU-only
    Linux/Windows machines take seconds per step.

## Risks

- Risk: per-step error compounds. 84.5% single-step accuracy is only about 19% correct over a ten-step task.
  - Mitigation: the tool is advisory only, never executes; the host agent owns verification and recovery; the P1
    gate requires the margin to separate right from wrong (AUROC ≥ 0.7), or the whole cascade premise fails.
- Risk: pruning drops the correct target, making the model's accuracy irrelevant.
  - Mitigation: P1 separately measures the "correct target pruned" rate; above 5% the project stops outright.
- Risk: on-screen content is an attacker-controlled input to the decision model; a web page or email could steer the
  choice toward "send" without using free text.
  - Mitigation: the goal string comes only from the host; the candidate table carries only element metadata; no
    delegated-execution capability is in this plan's scope.
- Risk: the sidecar introduces loopback TCP as a new same-uid attack surface and a new process-lifecycle burden.
  - Mitigation: bind loopback only, user-started, a deterministic per-user port, a pinned model path and SHA-256, and
    no automatic download by default.
- Risk: the fork has to carry a new subsystem across every future upstream sync.
  - Mitigation: keep the tool stateless and additive; P0 alone is already independently useful and model-independent.

## Milestones

1. **P0 — compact actionable-candidate table (no ML).** Add a mode to `get_app_state` that drops screenshots, keeps
   only actionable roles, de-duplicates, and prioritizes the focused element. Gate: if this alone captures most of
   the token and latency win, stop here — a classifier would be unnecessary scope.
2. **P1 — local eval set.** Collect 200 decisions from the existing fixture app plus three real apps, with host-agent
   ground truth and the per-step margin recorded. Gate: 4B top-1 ≥ 80% and margin AUROC ≥ 0.7.
3. **P2 — readout prototype.** Validate constrained readout on `llama-server`: assert single-token labels at
   startup, pin the probability semantics (pre/post-sampling) of the installed version, and share one prefill across
   multiple heads via `cache_prompt`. Gate: p50 decision latency under 1.5 s on a 16 GB M-series machine.
4. **P3 — `decide_next_action` read-only tool.** Return the full distribution, not just the argmax; ship a
   host-side cascade prompt alongside the tool. Gate: an agent that follows the advice finishes in fewer steps than
   one that ignores it.

## Validation

- Commands: `swift test` (Kit unit tests, covering pruning and candidate-table serialization), `go test` for the
  Linux/Windows runtimes, the existing smoke suite.
- Manual checks: on three real apps, compare the candidate table before and after pruning to confirm the correct
  target survives; confirm `get_app_state`'s default behavior is unchanged.
- Observed checks: record the candidate table, probability distribution, and decision latency per step; P0's token
  and latency win needs numbers against a baseline.

## Progress

- [x] P0: implemented the compact actionable-candidate mode (`get_app_state`'s `compact` parameter, macOS runtime
  only). After code-review fixes, `swift test` passes 233 tests.
- [x] P0: measured the win on real apps. Chrome 42% / Finder 30% / Mail 12% (text only, no screenshot); no latency
  difference. Detail: `plans/reports/e2e-measurement-260922-0835-compact-actionable-snapshot.md`.
- [x] P0 gate: decided to continue to the classifier. Pruning tree text alone captured only 12–42%, short of the
  proposal's expected magnitude; the larger win is dropping the screenshot, which the e2e run had not yet isolated
  (every full response carried no screenshot block). Decision (2026-09-22, D2 below): build P1–P3 anyway; the gates
  are measured and reported, not treated as blocking.
- [x] P1: built a 254-item local eval set (27 fixture, 227 real; 175 dev / 79 test split) and measured top-1 and
  margin AUROC. Gate result: **top-1 FAILS** (0.443 on test, threshold 0.80); **margin AUROC PASSES** (0.8286 on
  test, threshold 0.70). See the Measured gates table below.
- [x] P2: completed the `llama-server` readout prototype and latency measurement. Readout pin: llama.cpp
  `b10964-b29c606e2`, model `qwen3.5-4b-q4km`, probability semantics
  `pre_sampling_logprobs_renormalized_over_labels`. Gate result: **p50 latency PASSES** — 509 ms on test (labelled
  "M4 Max 48 GB; optimistic bound for the 16 GB gate"; threshold < 1500 ms), p95 913 ms.
- [x] P3: shipped `decide_next_action` as an opt-in, experimental, read-only MCP tool, listed only when
  `OPEN_COMPUTER_USE_DECISION_MODEL_URL` is set. The step-count gate ("agents following advice finish in fewer
  steps") is **not measured**: it needs agent-in-the-loop A/B runs, which are out of scope for this plan.

Status stays `active/`: the P3 step-count gate is still open, so this plan is not moved to `completed/`.

### Measured gates (from `scripts/decision-model/eval-data/summary.json`, test split)

| Gate | Threshold | Test value | Result |
|---|---|---|---|
| top-1 accuracy | ≥ 0.80 | 0.443 | FAIL |
| margin AUROC | ≥ 0.70 | 0.8286 | PASS |
| correct target pruned | ≤ 0.05 | 0.0938 (6 of 64) | FAIL |
| p50 latency | < 1500 ms | 509 ms | PASS |

p95 latency on test: 913 ms. Both latency figures are an optimistic bound: the gate is specified for a 16 GB
M-series machine, and this was measured on an Apple M4 Max with 48 GB. They are also the advisor's `latency_ms` only
(candidate pruning plus the model round trip): the accessibility refresh and rendering that the live call performs
first, and the MCP and app-agent hops, are not included, so a live call takes longer.

The 79 test items come from only 7 screens (16 screens for dev), because the split is by snapshot. Items from one
screen are correlated, so the passing test AUROC and the test precision at τ are weaker evidence than 79 independent
items would be. τ was selected on dev only. The pruning tuning rounds (0 and 1) were compared on their dev metrics,
but they ran over every split, so their reports also printed test aggregates; `eval-run.mjs` now runs tuning rounds
over `--split dev` only.

`recommended_min_margin` (τ) is **0.72**: the smallest dev margin with precision ≥ 0.90 and coverage ≥ 0.10 (selected
0.7117, rounded up to 2 decimals). At τ = 0.72, dev precision is 0.90 with 0.1714 coverage, and test precision is
0.9286 with 0.1772 coverage. 1.0 would mean "never auto-follow"; that is not the case here.

#### Failed gates (verbatim from the phase 06 gate report)

**top-1 accuracy (test 0.443, threshold 0.80).** The dev evidence points to three causes of roughly similar weight:

- **Wrong operation.** Dev operation accuracy is 0.686. The largest confusions are click predicted as press_key
  (10), done predicted as click (10; the model chose "done" for only 6 of 17 done items), click predicted as
  set_value (8), and set_value predicted as click (6). Only 5 of 19 set_value items got the right operation.
- **Wrong target.** When the correct target was offered, the model picked another element in 45 of 116 dev targeted
  items. The median page held 36 candidates.
- **Target never offered.** Pruning or the compact view removed the target in 18 of 134 dev targeted items.

The fixture items, which have simple and well-named controls, reach 13 of 18 on dev. The real-app items reach 75 of
157.

For a host, this means that unconditional advice is wrong more often than it is right. The advice is useful only
above the recommended margin: at 0.72, about 17% of decisions qualify, and they are right about 90% (dev) to 93%
(test) of the time. Everything else must fall back to `get_app_state` and the host's own judgement, which is what
the cascade guide already says.

**Correct target pruned (test 0.0938, threshold 0.05).** On test, 5 of the 6 misses are elements that are absent
from the compact view (`not_actionable`), and 1 is a `duplicate_close` drop. Dev shows the same dominant cause (12 of
18 are `not_actionable`), plus overflow on a single very large column-view snapshot. The compact view keeps only
actionable roles, so sidebar entries, file-list rows, font-panel rows, and save-sheet suggestion rows are never
candidates.

For a host, this means that for roughly 1 in 10 targeted decisions the advice cannot be correct, whatever the
margin. A high-margin answer on such a screen points at a plausible but wrong element, and only the
`chosen_row_text` check in the cascade guide protects against it. Closing this gap needs a compact-view change (P0)
or stage-2 paging (K11, cut for v1). Both are outside this phase.

## Decisions

- 2026-09-22: **open-computer-use stays an MCP tool server.** The server may advise and may execute an assigned
  action, but it never owns a goal and never runs its own planning loop. `run_goal` is rejected; bounded delegated
  execution via `decide_and_act` is deferred to P4 and needs a separate decision. Rationale: the host agent (Claude
  Code, Codex) already owns the goal, escalation, and user approval; adding a second policy loop inside a process
  that holds Accessibility permission is worse duplication. This repo also tracks upstream as a fork, and a stateful
  subsystem is a standing carry cost.
- 2026-09-22: scope extended to P3 — actually shipping the tool — but the P0/P1/P2 gates may still stop the project
  early.
- 2026-09-22: model weights are downloaded on first use and pinned by SHA-256, never bundled into the npm package,
  and gated behind hardware detection. This preserves local-inference-only as a core property, at the cost of a
  slower first run. **2026-09-23: superseded in part.** Weights are fetched only by an explicit
  `scripts/decision-model/fetch-model.sh` run, never on first use, and there is no hardware gate; the docs only
  recommend about 16 GB of unified memory. The SHA-256 pin and the no-weights-in-npm rule stand.
- 2026-09-22: land this only in the vietairs fork; do not propose it upstream to iFurySt.
- 2026-09-22: the current pain point is judged to be split evenly between cost/latency and reliability. That makes
  P1's margin-separability gate load-bearing: if the margin cannot separate right from wrong, the classifier only
  makes reliability worse, and the project should stop at P0.
- 2026-09-23 (D2): build P1–P3 even though the P0 gate above was open; failed P1/P2/P3 gates are measured and
  reported, not treated as blocking. See `plans/reports/auto-decisions-260923-0939-notarize-translate-decision-model.md`.
- 2026-09-23 (D3): the sidecar is **user-started**, launched by hand via `scripts/decision-model/start-sidecar.sh`.
  This supersedes the P0 risk note above, which said the sidecar would be "launched by the agent with a sanitized
  environment" — that design changed before implementation; the server never spawns the sidecar.
- 2026-09-23: the readout uses **one `/completion` call per page with two sequential heads** (operation, then
  target, in the same request under one grammar), instead of two separate requests sharing a prefix via
  `cache_prompt`. Reason: the primary model (Qwen3.5-4B) is a hybrid Gated-DeltaNet architecture, and a second
  request whose suffix diverges from the cached prompt would need a recurrent-state rollback that llama.cpp serves
  only from context checkpoints; one prefill with sequential heads needs no rollback. `target_distribution` is
  documented as P(target | chosen operation) — the target head is read after the operation label is generated, in
  the same completion.
- 2026-09-23: model choice is `unsloth/Qwen3.5-4B-GGUF` (`Qwen3.5-4B-Q4_K_M.gguf`, pinned by SHA-256), with
  `unsloth/Qwen3-4B-Instruct-2507-GGUF` as the fallback if the readout pin fails on the hybrid model; the fallback
  was not activated in this run (phase 01 pinned the primary model).
- 2026-09-23 (D4): real-app eval captures are never committed; only fixture-derived eval items live in the repo. Raw
  real-app captures stay under the gitignored `artifacts/decision-eval/`.
- 2026-09-23: Linux and Windows runtimes remain a non-goal for this tool; `Package.swift` declares macOS only, and
  the Go runtimes are unaffected.
- 2026-09-23 (review fixes): the client accepts only `http://127.0.0.1:<port>`. `[::1]` is refused because the
  sidecar binds IPv4 only, so the IPv6 loopback port is free for any same-uid process to take.
- 2026-09-23 (review fixes): before each request, the agent verifies that the listener on `127.0.0.1:<port>` is the
  sidecar recorded by `start-sidecar.sh`: the recorded pid runs the recorded `llama-server` binary and holds that
  listening socket (`DecisionSidecarVerifier.swift`). The sidecar has no authentication, so without this check a
  process that holds the port while the sidecar is down, including a sandboxed app without Accessibility access, would
  receive the goal and candidate rows. A shared bearer key was considered and rejected: the client would still send
  the key and the body to such a squatter.
- 2026-09-23 (review fixes): the pid file records pid, port, start time, resolved binary, and model key.
  `stop-sidecar.sh` signals only that pid, and only while its start time and kernel-reported executable still match;
  `start-sidecar.sh` keeps one sidecar per user and re-runs `check-readout.mjs` before reusing a running one.
- 2026-09-23 (review fixes): in the shared app agent, `decide_next_action`, `tools/list`, and `initialize` read the
  decision-model URL from the calling host's per-call environment only, and `decide_next_action` runs outside the
  agent's process-wide environment-override lock, so its network wait no longer blocks other hosts' calls.
