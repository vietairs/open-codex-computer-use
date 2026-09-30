---
title: "decide_next_action — local constrained-choice decision model (SemIf / jev-ultrafast shape)"
description: "Opt-in, read-only MCP advisory tool backed by a user-started llama-server readout, with a 200-item eval that measures and reports the P1/P2 gates."
status: pending
priority: P2
effort: 30h
branch: decision-model worktree (.claude/worktrees/decision-model, off main @ 4ac1d5e)
tags: [decision-model, mcp, llama.cpp, eval, macos, security]
created: 2026-09-23
---

# decide_next_action — implementation plan (workstream D)

Continues `docs/exec-plans/active/20260922-local-decision-model-mcp-tool.md` (P0 shipped in PR #10; P1-P3 open).
Binding decisions: D2 (build P1-P3 even though the P0 gate is open; failed gates are reported, not blocking),
D3 (sidecar is user-started, never spawned by the TCC process), D4 (only fixture-derived eval items are committed),
all in `../reports/auto-decisions-260923-0939-notarize-translate-decision-model.md`.

All code paths below are relative to the D worktree root
`/Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/decision-model`.

## Outcome (what "done" means)

1. `decide_next_action(app, goal)` is listed by `tools/list` **only** when `OPEN_COMPUTER_USE_DECISION_MODEL_URL` is set
   to a loopback URL. It returns the chosen operation, the chosen `element_index`, the margins, and the full operation and
   target distributions. It never actuates.
2. `scripts/decision-model/` fetches pinned Qwen3.5-4B Q4_K_M weights (SHA-256 checked), starts `llama-server` on a
   deterministic per-user loopback port, and asserts single-token labels and the probability semantics of the installed
   llama.cpp build.
3. A 200-item eval (fixture app + Finder, System Settings, TextEdit) is scored by a Node runner. It reports top-1 accuracy,
   pruned-target rate, margin AUROC, and p50/p95 latency against the exec-plan gates. The numbers go in the exec plan, the
   tool docs, and a committed aggregate summary. Real-app captures stay under the gitignored `artifacts/decision-eval/`.
4. A host-side cascade guide ships with the tool: follow the advice only when `margin >= recommended_min_margin` and the
   operation is non-destructive; otherwise reason it out.
5. The exec plan is in English, a history note exists, and `docs/ARCHITECTURE.md` and `docs/SECURITY.md` describe the tool.
   These two files are edited last, after rebasing on main.

Non-goals: Linux/Windows Go runtimes do not get the tool. There is no `run_goal`, `decide_and_act`, or P4 lease. No
server-spawned sidecar, no automatic weight download, no weights in npm. `AccessibilitySnapshot.swift` and the compact view
contract do not change. README.md is not edited: the tool is experimental and documented in the skill reference.

## Architecture and data flow

```
host agent ──tools/call decide_next_action{app, goal}──▶ MCP proxy ──per-call env (OPEN_COMPUTER_USE_*)──▶ app-agent (TCC)
  app-agent: ComputerUseToolDispatcher → macSessionGuard.requireUnlocked → ComputerUseService.decideNextAction
    1. DecisionModelEndpoint.fromEnvironment(env)      nil → error "disabled"; non-loopback → error (no network I/O)
    2. refreshSnapshot(app)                            SAME cache update as get_app_state, so returned element_index
                                                       is valid for the next click/set_value/scroll
    3. renderedFull    = snapshot.renderedText(.fullState)          ┐ identical strings to what get_app_state returns,
       renderedCompact = snapshot.renderedText(.compactActionable)  ┘ so the offline eval replays the live path exactly
    4. DecisionCandidateBuilder.build(goal, renderedFull, renderedCompact)
         parse compact rows → prune (disabled, menu bar, scroll-bar parts, repeated controls, window chrome)
         → rank (focused, lexical overlap with goal) → pages of ≤52 → labels A–Z, a–z (ascending index within a page)
    5. per page: DecisionPromptBuilder.prompt + grammar → POST {base}/completion (native llama.cpp endpoint)
         one prefill; grammar forces  " <opLabel>" "\nTarget:" " <targetLabel>"; n_probs pre-sampling logprobs;
         operation head = first generated position, target head = last generated position;
         each head renormalised over its own label set (softmax restricted to labels)
       if pages > 1: one more call over the page winners (stage 2); combined target P(c on page p) = P2(winner_p) × P1_p(c),
       chosen target = argmax of that combined distribution, operation distribution = stage-2 head (K11)
    6. DecisionAdvice → JSON text result (advisory:true, experimental:true, recommended_min_margin, full distributions)
llama-server (user-started, 127.0.0.1:39000+uid%1000, --parallel 1) ◀── loopback only, no redirects, 5 s timeout, 1 MiB cap
```

Offline eval uses the same Kit entry point (`DecisionAdvisor.advise(goal:appName:renderedFull:renderedCompact:client:maxPages:now:)`), called
from a dev-only executable `experiments/DecisionModelEval`. The executable is driven by `scripts/decision-model/eval-run.mjs`,
so eval numbers measure the shipped pruning, prompt, and parsing code, not a JavaScript copy of it.

## Key design decisions (with evidence)

| # | Decision | Why / evidence |
|---|----------|----------------|
| K1 | Pruning consumes the **rendered text** (full + compact), not `ElementRecord` | Eval captures come from the live MCP `get_app_state` (text only). Structured pruning in Swift could not be replayed offline, so the pruned-target metric would measure a different pruner. `ElementRecord` (`AccessibilitySnapshot.swift:7-36`) has no enabled or menu-bar fields anyway. Traits such as `disabled` are rendered as English literals (`AccessibilitySnapshot.swift:1240-1263`). |
| K2 | Menu-bar region = tail of the full tree starting at the **second depth-0 indexed row**, accepted only if every row in that tail has depth ≤ 1; otherwise the rule is skipped (fail-open) | Menu bar is rendered by a second top-level `renderer.render(menuBar)` call at depth 0 (`AccessibilitySnapshot.swift:403-409`). Menu-bar items render with an empty role word (`displayRoleText`, `AccessibilitySnapshot.swift:1959-1961`) and hide their children (`:1808-1809`), so role text cannot identify them. |
| K3 | Role-based rules match English role-description **prefixes**; an unknown or localized role means keep | Role text is `AXRoleDescription` lower-cased (`AccessibilitySnapshot.swift:2008-2010`), which is localized. Failing open costs a label slot. It never costs the target. |
| K4 | **One `/completion` call per page with two sequential heads** (grammar `op "\nTarget:" tgt`), `cache_prompt:true` kept | Qwen3.5-4B is a hybrid Gated-DeltaNet model (48 linear + 16 attention layers). A second request whose suffix diverges from the cached prompt needs a recurrent-state rollback that llama.cpp serves only from context checkpoints. One prefill with sequential heads needs no rollback, halves HTTP calls, and still shares one prefix between the heads. The target head is conditional on the argmax operation; this is documented. **Deviation from the literal "separate requests via cache_prompt" wording; flagged for plan validation.** |
| K5 | Probabilities = **pre-sampling logprobs** (`post_sampling_probs:false`), renormalised over the head's label tokens; greedy (`temperature:0`) under the grammar | In `populate_token_probs`, the non-post-sampling branch reads the raw logits distribution, so the result is softmax restricted to labels, which is the constrained-choice readout. Greedy under the grammar picks the argmax label, which is consistent with that distribution. Phase 01 pins this empirically for build 10964 (`b29c606e2`). |
| K6 | Labels are rendered `A)` in the prompt and generated as the space-prefixed piece `" A"`; `/tokenize` asserts each `" X"` is exactly one token | Prompt prefill ends with `Operation:` / `Target:` without a trailing space, which is the natural BPE boundary. Digits are not used, because Qwen splits `" 1"` into two tokens. |
| K7 | Tool listing is gated per call: `ToolDefinitions.listed(environment:)`; `ToolDefinitions.all` stays the 9 base tools | The MCP proxy forwards `OPEN_COMPUTER_USE_*` env per call (`MacSessionGuard.swift:64-67`, `MacOSAppAgentProxy.swift:406-410`). `testToolDefinitionCount` asserts `all.count == 9` (`OpenComputerUseKitTests.swift:255-257`) and stays green. |
| K8 | Per-call env for the URL is acceptable, unlike the lock opt-in | A same-uid socket peer that points the URL at its own loopback listener learns only goal + candidate rows. It can already read the full tree with `get_app_state`, so no new capability. The loopback restriction removes the off-host exfiltration path. This goes in SECURITY.md. |
| K9 | Model: `unsloth/Qwen3.5-4B-GGUF` @ `720bb031aae5488eae5d6a78768e6d826662b2ae`, `Qwen3.5-4B-Q4_K_M.gguf`, 2,740,937,888 B, LFS sha256 `00fe7986ff5f6b463e62455821146049db6f9313603938a70800d1fb69ef11a4`. Fallback: `unsloth/Qwen3-4B-Instruct-2507-GGUF` `Qwen3-4B-Instruct-2507-Q4_K_M.gguf`, 2,497,281,120 B, sha256 `3605803b982cb64aead44f6c1b2ae36e3acdb41d8e46c8a94c6533bc4c67e597` | Qwen3.5 small series (Mar 2026) is still the newest ≤9B Qwen line; 3.6/3.8 ship only ≥27B. The fallback is a dense transformer, non-thinking instruct, used only if Phase 01's readout pin fails on the hybrid model. The implementer re-derives both hashes from the HF tree API and from `shasum -a 256` after download. |
| K10 | Eval harness is a dev-only executable under `experiments/`, not a CLI subcommand | The CLI proxies through the app-agent, and the debug CLI dies in agent sessions (exit 141, memory note). `experiments/` already holds dev-only targets (`Package.swift:57-67`). |
| K11 | Paged readout: one call per page, then a stage-2 call over the page winners. The reported target distribution is the product `P2(winner_p) × P1_p(c)`, and the chosen target is its argmax | This gives an invariant hosts can rely on: `chosen == argmax(reported distribution)` and `margin == top1 − top2` of what is reported. The full distribution covers every offered candidate and sums to 1. The stage-2 grammar has ≤ 4 labels. |
| K12 | Env reads are injected (`environment: () -> [String: String]` on `StdioMCPServer` and the dispatcher, both defaulted) instead of tests calling `setenv` | In the app-agent, every MCP line, including `initialize` and `tools/list`, runs inside `AppAgentEnvironment.withOverrides` (`MacOSAppAgentProxy.swift:405-414`, `:491-520`), so reading the process env at call time already sees the host's per-call value. Injection keeps tests free of global state, and the existing callers (`MacOSAppAgentProxy.swift:365`, `OpenComputerUseMain.swift:43`, `ComputerUseToolDispatcher.swift:310`) compile unchanged. |
| K13 | The smoke suite strips `OPEN_COMPUTER_USE_DECISION_MODEL_URL` from the server env | It asserts exactly 9 tools (`apps/OpenComputerUseSmokeSuite/.../main.swift:199-201`) and inherits the whole shell env (`:348-352`). A user who exported the URL would otherwise see a false smoke failure. |

## Phases

| Phase | File | Depends on | Parallel group | Executor tier |
|------|------|-----------|----------------|---------------|
| 01 | [phase-01-sidecar-and-model-scripts.md](phase-01-sidecar-and-model-scripts.md) | — | **G1** (parallel with 02, 03) | sonnet (implementer), opus reviews the pin |
| 02 | [phase-02-swift-candidate-pruning-and-labels.md](phase-02-swift-candidate-pruning-and-labels.md) | — | **G1** | tester sonnet → implementer opus |
| 03 | [phase-03-eval-capture-and-ground-truth.md](phase-03-eval-capture-and-ground-truth.md) | — (needs only the live MCP) | **G1** | main loop (opus/fable) + labeller subagents opus |
| 04 | [phase-04-swift-prompt-readout-client.md](phase-04-swift-prompt-readout-client.md) | 01, 02 | sequential | tester sonnet → implementer opus |
| 05 | [phase-05-swift-tool-wiring-and-eval-harness.md](phase-05-swift-tool-wiring-and-eval-harness.md) | 04 | sequential | tester sonnet → implementer opus |
| 06 | [phase-06-eval-run-and-gate-report.md](phase-06-eval-run-and-gate-report.md) | 01, 03, 05 | sequential | implementer sonnet; tuning edits opus |
| 07 | [phase-07-docs-cascade-prompt-and-rebase.md](phase-07-docs-cascade-prompt-and-rebase.md) | 06; ARCHITECTURE/SECURITY step also needs workstream B merged | sequential, last | docs-manager sonnet; security wording reviewed by opus |

Critical path: 02 → 04 → 05 → 06 → 07 (01 and 03 must finish before 06).

## File ownership (no two concurrent phases share a file)

| File / glob | Owner |
|-------------|-------|
| `scripts/decision-model/{model-manifest.json,fetch-model.sh,start-sidecar.sh,stop-sidecar.sh,check-readout.mjs}`, `scripts/decision-model/fixtures/**` | 01 |
| `Sources/OpenComputerUseKit/DecisionCandidates.swift`, `Tests/OpenComputerUseKitTests/DecisionCandidatesTests.swift` | 02 (06 may edit later, sequentially, for tuning) |
| `.gitignore`, `scripts/decision-model/eval-dataset.mjs`, `scripts/decision-model/eval-dataset.test.mjs`, `scripts/decision-model/eval-data/fixture-*` | 03 |
| `Sources/OpenComputerUseKit/{DecisionPrompt.swift,DecisionModelClient.swift}`, `Tests/.../{DecisionPromptTests.swift,DecisionModelClientTests.swift}` | 04 |
| `Sources/OpenComputerUseKit/{DecisionAdvice.swift,DecisionAdvisor.swift,ToolDefinitions.swift,ComputerUseToolDispatcher.swift,ComputerUseService.swift,MCPServer.swift}`, `Tests/.../DecisionAdvisorTests.swift`, `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift` (one line), `Package.swift`, `experiments/DecisionModelEval/**` | 05 (06 may change only `DecisionAdvisor.recommendedMinMargin`) |
| `scripts/decision-model/{eval-run.mjs,eval-metrics.mjs,eval-metrics.test.mjs}`, `scripts/decision-model/eval-data/summary.json`; add-only tests in `DecisionCandidatesTests.swift` plus rule tuning in `DecisionCandidates.swift` (≤ 3 rounds, dev split only) | 06 |
| `docs/exec-plans/active/20260922-local-decision-model-mcp-tool.md`, `docs/histories/2026-09/*-local-decision-model-advisory-tool.md`, `skills/open-computer-use/SKILL.md`, `skills/open-computer-use/references/decision-model.md`, `docs/ARCHITECTURE.md`, `docs/SECURITY.md` | 07 |
| `AccessibilitySnapshot.swift`, `apps/OpenComputerUse/**`, `apps/OpenComputerUseLinux/**`, `apps/OpenComputerUseWindows/**`, `scripts/npm/**`, `README*.md` | nobody (FORBIDDEN everywhere) |

Shared-worktree hazards for G1: phase 03 builds the fixture app with `--scratch-path .build-eval` so it never contends
for `.build/` with phase 02's `swift test`. Each phase commits only its own files with explicit `git add <paths>`, never
`git add -A`.

## Test matrix

| Layer | What | Where | Runner |
|-------|------|-------|--------|
| Unit (Swift) | compact-row parsing, trait parsing, menu-bar region, each prune rule, focused/never-drop invariants, ranking determinism, paging, label alphabet | `DecisionCandidatesTests.swift` | `swift test --filter DecisionCandidatesTests` |
| Unit (Swift) | prompt framing matches the pinned template, special-token scrubbing, grammar text, request body, readout parsing (golden sample), label-split / missing-label errors, loopback enforcement matrix, redirect refusal, size cap, timeout | `DecisionPromptTests.swift`, `DecisionModelClientTests.swift` | `swift test --filter 'DecisionPromptTests|DecisionModelClientTests'` |
| Unit (Swift) | disabled-by-default listing and error, argument validation, advisor paging/stage-2, margin semantics, JSON shape, stub transport end-to-end | `DecisionAdvisorTests.swift` | `swift test --filter DecisionAdvisorTests` |
| Regression | whole Kit suite, no network | all | `swift test` (baseline 233+ passing) |
| Unit (Node) | dataset schema/parity validation; AUROC, percentile, tau selection, summary has no row text | `eval-dataset.test.mjs`, `eval-metrics.test.mjs` | `node --test scripts/decision-model/` |
| Integration | real sidecar: `/tokenize`, template, readout semantics pin | `check-readout.mjs` | `scripts/decision-model/start-sidecar.sh` |
| E2E (offline replay) | 200 items through the shipped Swift pipeline against the real sidecar | `eval-run.mjs` + `DecisionModelEval` | Phase 06 |
| E2E (live) | tool listed only with env; one real call on the fixture app returns a valid index | MCP from an agent session | Phase 05 live check |
| Repo gates | `make ci` (bash -n, node --check, docs, hygiene) | — | `make ci` |

There is no PR CI in this fork (memory note). The local `swift test` and `make ci` runs are the whole evidence and must be
pasted into the PR description.

## Risks (likelihood × impact → mitigation)

| Risk | L×I | Mitigation |
|------|-----|-----------|
| Pruning drops the correct target | H×H | Every rule fails open. Focused and text-entry rows are never dropped. Rules that depend on goal wording keep rows when the goal mentions them. Per-rule drop attribution in the eval. Dev/test split by snapshot. At most 3 tuning rounds in 06. The gate is reported under D2. |
| Qwen3.5 hybrid model misbehaves under the readout (label split, `/tokenize` ≠ 1, template drift) | M×H | Phase 01 pin fails loudly, then switches to the K9 fallback model (dense Qwen3-4B-Instruct-2507) and re-pins. Each switch is recorded. |
| Margin does not separate right from wrong (AUROC < 0.7) | M×H | Reported, not hidden (D2). `recommended_min_margin` is picked from the eval; if no threshold reaches 90% precision, τ = 1.0 ("never auto-follow") and the docs say so. |
| Prompt injection from screen text (`<|im_start|>` or instructions inside rows) | M×M | Scrub `<|` / `|>` from goal and rows. Collapse control characters and newlines. Truncate rows to 160 chars. The readout is grammar-constrained to labels, so the worst case is a steered choice, which the cascade guide and the host's destructive-action rule catch. |
| URLSession blocking deadlock in the app-agent | L×H | Dedicated `OperationQueue` delegate queue. A semaphore wait with a hard deadline. The call is never made on the main queue: the handler asserts `!Thread.isMainThread`, or else dispatches off-main. Covered by a unit test with a slow stub. |
| Decide holds the agent's env-override lock for the HTTP duration (`MacOSAppAgentProxy.swift:494-500`) | M×L | 5 s per request, 12 s overall deadline, `--parallel 1` sidecar. Documented in RELIABILITY wording within ARCHITECTURE. |
| Loopback port squatting by another local user (they receive goal + rows) | L×M | Residual risk; documented in SECURITY.md. The start script checks that the port owner is its own pid. Future hardening is out of scope: a unix socket via `--host *.sock`. |
| Real-app personal data leaks into git | M×H | `.gitignore` entry lands first in 03. The summary writer uses a key whitelist and a test asserts no row text. Pre-commit check: `git status --porcelain | grep decision-eval` must be empty. |
| Live MCP in the session is a stale build without `compact` | M×M | 03 preflight asserts the `Compact actionable view:` header. On failure, STOP (redeploy is outside this plan; memory note "stale Dev.app deploy loop"). |
| Labeller bias (goals reuse element wording, which inflates lexical ranking) | M×M | Quota of ≥40% paraphrased goals, blind second labeller, lexical-overlap stat reported per split. |
| Translation PR (B) conflicts on ARCHITECTURE/SECURITY | H×L | Those edits are scheduled last in 07, after `git rebase origin/main` once B merges. |

## Backwards compatibility

- The feature is additive. With the env var unset, `tools/list` is byte-identical to today's 9 tools and no code path
  touches the network. A regression test asserts this.
- `get_app_state` and the compact view output are unchanged (`AccessibilitySnapshot.swift` is FORBIDDEN).
- No migration. No state is persisted by the server. Sidecar state lives under
  `~/Library/Application Support/OpenComputerUse/decision-model/`.

## Rollback

- Runtime: unset `OPEN_COMPUTER_USE_DECISION_MODEL_URL`, which removes the tool from the list and disables the call path;
  then `scripts/decision-model/stop-sidecar.sh`.
- Code: each phase is its own commit on the D branch. Revert them in reverse order (07 → 01). Phases 02/04/05 add new files
  plus additive edits to 4 existing Kit files, the smoke-suite env line and Package.swift; reverting 05 alone restores the 9-tool server. The weights directory can
  be deleted by hand; nothing else references it.

## Success criteria (observable)

- `swift test` is green with ≥ 60 new decision tests; the baseline is unchanged. `make ci` is green.
- With the env var unset, `tools/list` has 9 tools. Set to `http://127.0.0.1:<port>`, it has 10. Set to
  `http://10.0.0.1:1`, the call returns an error naming the env key before app resolution or any socket (dispatcher test with an unknown app asserts the error is not `appNotFound`).
- `start-sidecar.sh` exits 0 and prints the export line. `check-readout.mjs` writes `fixtures/readout-pin.json` with
  `labelsSingleToken: true` and `probabilitySemantics: "pre_sampling_logprobs_renormalized_over_labels"`.
- `scripts/decision-model/eval-data/summary.json` exists with n ≥ 200 items (≥ 20 fixture), and top-1, pruned-target, AUROC,
  p50, p95 per split, plus PASS/FAIL per gate. The exec plan quotes the same numbers.
- `git ls-files artifacts/decision-eval` is empty.

## Open questions

1. K4 deviates from the exec plan's literal "separate heads via `cache_prompt`" (two requests). The plan uses one request
   with two sequential heads, because Qwen3.5 is hybrid and a divergent suffix needs a recurrent-state rollback. Accept, or
   require the two-request form (then the fallback dense model becomes primary)?
2. The exec plan's P3 gate ("agents following advice finish in fewer steps") needs agent-in-the-loop A/B runs. This plan
   records it as **not measured** in the exec plan rather than inventing a harness. Is that acceptable, or should a phase be
   added?
3. The p50 < 1.5 s gate is specified for a 16 GB M-series machine. The only hardware available is an M4 Max 48 GB, so the
   measured p50 is an optimistic bound and will be labelled that way.
4. Phase 07b (ARCHITECTURE.md and SECURITY.md) waits for workstream B's translation PR to merge. If D is ready first, is
   it acceptable to merge D with 07b deferred to a small follow-up PR? The plan assumes yes, because 07a touches no
   B-owned file.
5. The live end-to-end check (a real `decide_next_action` call through a deployed Dev.app) cannot run from an agent
   session. It is a user handover step in phase 07, not a gate. Is that acceptable for the before-merge review?

## Revision log

- 2026-09-23 10:20 (planner, second pass): wrote phases 05–07. Fixed phase 04's transport tests, which used
  `DispatchQueue.global().sync`: GCD runs `sync` on the calling thread, so the main-thread guard would still trip. They now
  use `async` plus a semaphore. Filled the fallback model revision `a06e946b…` in phase 01 and re-verified both HF
  hashes live; the primary pin `720bb031…` and current `main` carry byte-identical files. Added K11–K13 after tracing
  `MacOSAppAgentProxy.swift` (per-call env covers `initialize` and `tools/list`) and the smoke suite's hard-coded
  9-tool assertion.

## Amendments from plan validation (2026-09-23 10:30, binding; override phase text where they conflict)
Source: ../reports/kongming-plan-validation-decision-model.md + auto-decision D7.
1. K4 accepted: one /completion per page, two sequential heads. The primary model stays Qwen3.5-4B (hybrid); the dense fallback is used only if the phase 01 readout pin fails. Document `target_distribution` as P(target | chosen operation). Rationale to record: one round trip, one prefill, one timeout (request 2 is a strict extension of request 1's cache, so there is no recurrent rollback).
2. Phase 04 sanitize: in addition to the `<|`/`|>` scrub, strip `<[^<>\s]{1,40}>`. /completion tokenizes with parse_special=true, so `</think>`, `<tool_call>` etc. would otherwise survive. Add a test.
3. Loopback: accept only literal `127.0.0.1` and `[::1]` hosts. Reject `localhost` (llama-server binds IPv4 only). Update the tests.
4. The lock-hold bound is ~17 s. State it as such in docs and tests.
5. Cut K11 stage-2 paging for v1: defaultMaxPages = 1. Report overflow as prune cause `overflow`.
6. Drop the `wait` quota in eval goal generation. Use a small file for the phase 01 corrupt-hash negative test.
7. Phase 03 capture (revised 10:35): runs in a subagent that loads the open-computer-use MCP tools via ToolSearch, NOT the main loop. Allowed UI actions are ONLY: (a) Finder: open windows on the synthetic ~/ocu-eval-scratch folder, switch views, Get Info on a dummy file, New Folder inside the scratch folder; (b) System Settings: sidebar navigation to General, Appearance, Desktop & Dock, Keyboard, Displays, Sound — never toggle a setting; (c) TextEdit: new untitled document, type dummy text, open the Font panel, Find bar, Format menu, Settings window, and the Save sheet, which is then dismissed with Escape. Never save, send, delete, sign in, or touch other apps or windows. Close what you opened when done (Escape / close without saving). Excluded panes: About, Sharing, Wi-Fi, Bluetooth, Network, Apple Account, Privacy & Security, Passwords, Wallet, Internet Accounts, Users & Groups. Real-app captures go only to gitignored artifacts/decision-eval/.
8. Phases 06/07 privacy checks also grep committed files for `id -un`, `scutil --get ComputerName`, and `scutil --get LocalHostName` values, plus the prior canary, covering summary.json free-text notes and reports.
9. Phase 03: p50 is reported as "optimistic bound (M4 Max 48 GB)" with timings.prompt_n / prompt_ms recorded.
10. The live Dev.app end-to-end check is a user handover step. The checklist includes the negative case: env var unset → 9 tools listed, no decide_next_action.
