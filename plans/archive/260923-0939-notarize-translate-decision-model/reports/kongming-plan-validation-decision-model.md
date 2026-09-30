# Kongming counsel — plan validation, workstream D (`decide_next_action`)

Date: 2026-09-23. Mode: unattended `--auto` gate; advisory only. Model: Fable 5.1.
Inputs read: `decision-model/plan.md`, `phase-01`…`phase-07`, the auto-decisions report, the Chinese exec plan,
`MacOSAppAgentProxy.swift:405-520`, `MacSessionGuard.swift:55-75`, and llama.cpp `tools/server/server-context.cpp` +
`server-common.cpp` (master, fetched 2026-09-23).

## TL;DR

Accept the plan with five bounded amendments. K4 (one call, two sequential heads) is the right primary, but its stated
reason is wrong and should be corrected in the record. Ship opt-in/experimental with P3 unmeasured, the p50 labelled as
an M4 Max optimistic bound, ARCHITECTURE/SECURITY deferred behind B, and the live Dev.app check as handover. Cut the
stage-2 paging readout (K11) for v1, widen the special-token scrub, restrict the endpoint to literal loopback
addresses, and add identity-string greps to the privacy checks. The single riskiest step is phase 03's unattended
real-app capture.

## Answers to the five questions

### Q1 — K4: one `/completion` call with two sequential heads vs two cached-prefix requests

**Recommendation: one call, two sequential heads, hybrid Qwen3.5-4B stays primary; the dense Qwen3-4B-Instruct-2507
fallback is triggered only by the phase 01 pin, never by the head design.**

- The plan's rationale ("a second request needs a recurrent-state rollback") is not accurate for the two-request form
  as the exec plan intended it. Request 2 (`prompt + " A" + "\nTarget:"`) is a strict extension of request 1's cached
  sequence, so llama-server appends without any rollback; checkpoints only matter when the new prompt diverges from the
  cache (different candidate list, or conditioning on a non-generated op). Correct the decision-record wording in phase
  07: the real reasons are one HTTP round trip instead of two, one prefill, one timeout budget, and a simpler failure
  surface. Same conclusion, honest reason.
- Conditioning the target head on the argmax operation is acceptable for an advisory tool. The exec plan's "full
  distribution" means "not only the argmax", and both heads still return every label's renormalised probability. Name
  the semantics in the result and docs: `operation_distribution` is P(op), `target_distribution` is P(target | op =
  chosen). Do not attempt a joint over (op, target); that is 7 requests for no host benefit.
- Verified: the native `/completion` path computes `top_logprobs` from raw logits when `post_sampling_probs` is false
  (`get_token_probabilities` reads `llama_get_logits_ith`; `populate_token_probs` takes that branch). The phase 01
  "at least one non-label token in `top_logprobs`" assertion is the right empirical pin for build 10964.
- Two cautions the plan already half-covers: `n_probs` is clamped server-side to `min(max_probs, request)` (fine at 128),
  and every label outside the top-128 is a `missingLabel` with probability 0 (fine, because the grammar-greedy token is
  always the top label, so no missing label can outrank it).

### Q2 — P3 gate ("agents following advice finish in fewer steps") not measured

**Acceptable.** Shipping opt-in and labelled experimental with the exec plan kept in `active/` and the gate recorded as
"not measured" is honest and proportionate. Do not invent an A/B harness in this run. Record in the exec plan what
would measure it later (N fixed tasks, same host model, advice on/off, step count and success), so the follow-up is
scoped, not forgotten. Note the residual: the eval measures agreement with an opus labeller on LLM-authored goals; a
PASS there does not prove hosts benefit. The τ = 1.0 default when precision < 90% is the right safety valve.

### Q3 — p50 < 1.5 s specified for 16 GB M-series, measured on M4 Max 48 GB

**Acceptable with the label, plus one cheap addition.** Record `hardware` in `summary.json` (already planned) and mark
the gate row "optimistic bound; not the target hardware". Cheap addition: the readout is prefill-dominated (≈1k prompt
tokens, ≤16 generated), so also record llama-server's `timings.prompt_n` and `prompt_ms` per item in the local results
and aggregate `promptTokensP50` / `prefillTokensPerSec` in the summary. That lets a 16 GB reader rescale. Speculative,
not measured: a base M1/M2 16 GB is roughly 4–6x slower on prefill than an M4 Max, so a 0.3 s M4 Max p50 would land
near the 1.5 s line on the target hardware; treat any M4 Max p50 above ≈0.35 s as a likely FAIL on 16 GB.

### Q4 — ARCHITECTURE.md / SECURITY.md deferred until the translation PR (B) merges

**Acceptable.** B is PR #16, docs-only, with one blocking finding; it will almost certainly merge long before D reaches
phase 07 (D is a ~30 h critical path), so the deferral is mostly theoretical. Conditions if it does trigger: (1) the D PR
description lists 07b as a required follow-up with the section text pre-drafted in the phase 07 report, so the follow-up
is a paste; (2) the skill reference's security notes (07a item 3) ship in D itself, so no user can enable the tool
without a security description somewhere. Do not append to those two files before B merges; B rewrites every line, so
any pre-merge edit conflicts.

### Q5 — Live end-to-end through the deployed Dev.app as handover, not a merge gate

**Acceptable.** The per-call env path the tool relies on is proven live, not just read from code: the sanitizer comment
in `MacSessionGuard.swift:55-63` records that a forged per-call lock opt-in became reachable through exactly this
`withOverrides` + call-time `ProcessInfo.processInfo.environment` route. The phase 05 `StdioMCPServer` tests with an
injected environment cover the Kit side. Strengthen the handover checklist with the negative case (unset the env var,
restart the host, confirm 9 tools) and the memory-note hazards (stale Dev.app binary, socket eviction between Dev and
release bundles, TCC re-grant). Keep it a handover; an agent session cannot run it (exit 141 memory note).

## Flags

### Locked constraint (server never owns a goal)

No violation found. No `run_goal`, no `decide_and_act`, no actuation from the decide path, no server-spawned process.
`done` and `wait` are advisory labels, and the cascade guide is host guidance appended to `initialize` instructions only
when the tool is enabled. Keep phase 05's FORBIDDEN line on actuation as written.

### Attack surface in the privileged process beyond a loopback POST client

1. **Special-token scrub is incomplete (medium, cheap fix).** Verified on llama.cpp master: the native `/completion`
   handler tokenizes string prompts with `add_special=true, parse_special=true` (`server-context.cpp:4299`). Qwen3
   tokenizers mark `<think>`, `</think>`, `<tool_call>`, `</tool_call>`, `<tool_response>`, `<|endoftext|>`,
   `<|fim_*|>`, `<|vision_start|>` and similar as special tokens. Scrubbing only `<|` and `|>` leaves `</think>` in a
   candidate row to be parsed as a real control token. Amend phase 04 `sanitize`: remove every `<[^<>\s]{1,40}>` span
   (all Qwen special tokens are angle-bracketed, whitespace-free) in addition to the `<|`/`|>` rule, and add the
   `</think>` case to the `DecisionPromptTests` sanitize assertion. Worst case remains a steered label under the grammar,
   but the fix costs one regex.
2. **Restrict the endpoint to literal loopback addresses (small simplification).** Accept only `http://127.0.0.1:<port>`
   and `http://[::1]:<port>`; drop `localhost`. That removes name resolution from the privileged path and a practical
   footgun: `start-sidecar.sh` binds `--host 127.0.0.1` (IPv4 only) while `localhost` resolves to `::1` first on
   macOS, so Happy Eyeballs adds delay or confusing timeouts. Update the phase 04 accepted/throws lists accordingly.
3. **State the true lock-hold bound.** The deadline is checked before each model call and each call has a 5 s
   timeout, so the `AppAgentEnvironment.lock` can be held ≈17 s, not 12 s. Say 17 s in ARCHITECTURE/SECURITY, or check
   the deadline inside the transport. With K11 cut (below) the single-call bound is 5 s and the point becomes moot.
4. Nothing else: no redirects, no proxies, 1 MiB cap, ephemeral session, no Process spawning. The K8 argument (a
   same-uid peer redirecting the URL learns only goal + rows it could already read via `get_app_state`) holds.

### Personal data from real-app snapshots

1. **Add identity-string greps to every privacy check.** The canary test covers goal/row fields, but `summary.json`
   carries free text in `tuningRounds[].note` and `notes`, and phase reports are prose. In phase 06's acceptance and
   phase 07's `grep -R '/Users/|CANARY'` line, also grep for `$(id -un)`, `$(scutil --get ComputerName)`, and
   `$(scutil --get LocalHostName)` across `summary.json`, the exec plan, the history note, the skill reference, and the
   phase reports. Finder's sidebar renders the home folder short name and System Settings renders the Mac's name, so
   these strings will exist in the local captures.
2. **Widen the System Settings exclusion list** to General > About, Sharing, Wi-Fi, Bluetooth, and Network (computer
   name, SSIDs, paired device names). Six general panes remain available.
3. **`plans/` is untracked today (18 entries in `git status`).** A later plan-gc may commit the phase reports. The
   "counts only, no content" rule in phases 03 and 06 must hold, and the greps above should run over `plans/**` before
   any such commit.
4. Fixture-only commits, `.gitignore` first, key-whitelisted summary: correct as written.

### YAGNI for a first experimental opt-in release

1. **Cut K11 (stage-2 paged readout) — the largest cut.** Set `defaultMaxPages = 1`, keep the pure `overflow` rule in
   the candidate builder, and have the advisor read exactly one page. The eval then reports overflow as a pruned-target
   cause, which is precisely the evidence needed to decide whether paging is worth building. Removes the stage-2 prompt
   form, the product-rule distribution, the 4-call deadline logic, `pagesQueried` semantics, and ~15 assertions; it also
   makes the hybrid-model prefix-reuse question irrelevant (divergent prompts only arise across pages).
2. `localhost` and dotted-IPv6 acceptance (see attack-surface item 2).
3. `wait` as ground truth from a static snapshot is unlearnable noise; keep `done`, drop the per-snapshot `wait` quota
   in phase 03 (or drop `wait` from the label set if the tester agrees it never has a defensible label).
4. Phase 01's negative test copies a 2.7 GB model to corrupt one byte; use a small stand-in file with a scratch manifest.
5. Keep the generator/blind-labeller/adjudicate/spot-check pipeline; it is heavy but the gate numbers depend on it.

### Single riskiest thing in the plan

**Phase 03's unattended real-app capture from the main loop.** It is the only step that drives the user's real desktop
(Finder, System Settings, TextEdit) with no human present, it feeds full real-app trees into ~36 subagent contexts, and
its preflight can STOP the whole critical path (06 depends on 03) if the session's MCP binary is stale (memory notes:
stale Dev.app deploy loop, socket eviction between bundles). Everything downstream (gate numbers, τ, docs) inherits its
quality and its privacy exposure. Mitigations: run fixture capture first and commit it before any real capture; keep the
`Compact actionable view:` preflight as a hard STOP; navigation-only actions; the widened pane exclusions and identity
greps above. Runner-up, already rated H×H by the plan: the pruning rules dropping the correct target.

## Work checklist (amendments only)

1. Phase 04: widen `sanitize` to strip `<[^<>\s]{1,40}>`; add the `</think>` test case; accept only literal
   `127.0.0.1` / `[::1]`.
2. Phase 05: `defaultMaxPages = 1`, single-page advisor, drop stage-2 and the product rule; document
   `target_distribution` as conditional on the chosen operation.
3. Phase 03: widen the System Settings exclusions; drop the `wait` quota.
4. Phase 06/07: identity-string greps; record `timings.prompt_n`/`prompt_ms`; label p50 as an M4 Max optimistic
   bound; state the 5 s (single call) lock-hold bound.
5. Phase 07: correct the K4 rationale in the exec-plan decision record; pre-draft the 07b sections in the report.

## Success metrics

`swift test` and `make ci` green with the env var unset producing a byte-identical 9-tool `tools/list`; `summary.json`
committed with n ≥ 200 and all four gates evaluated on the test split, PASS or FAIL stated verbatim in the exec plan;
zero hits for the identity greps across every committed file; overflow-pruned GT rate reported so the paging decision
has data; the handover checklist executed by the user reports 10 tools with the env var and 9 without.

## Assumptions

- Build 10964 tokenizes `/completion` string prompts with `parse_special=true` like master does (high; verified on
  master, and this behaviour predates the build). If it does not, item 1 under attack surface is harmless but unneeded.
- B (PR #16) merges before D reaches phase 07 (high). If not, the 07b follow-up PR conditions in Q4 apply.
- Qwen3.5-4B loads and pins cleanly in build 10964 (medium). Phase 01's pin and the dense fallback are the arbiter;
  nothing here depends on which model wins.
- The eval's multi-page cases are rare enough that cutting K11 costs little top-1 (medium). The overflow-pruned rate in
  `summary.json` is the evidence that would flip this; above ≈2 % on the test split, build paging as a follow-up.
- The per-call env override reaches call-time `ProcessInfo.processInfo.environment` reads in the deployed agent (high;
  evidenced by the recorded forged-opt-in incident in `MacSessionGuard.swift:55-63`).
- The controller adjudicates conservatively; every amendment above is bounded to files already owned by the named phase
  and none widens a FORBIDDEN boundary.
