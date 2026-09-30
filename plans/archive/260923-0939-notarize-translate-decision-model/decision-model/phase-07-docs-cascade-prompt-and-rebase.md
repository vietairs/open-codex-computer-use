# Phase 07 — Docs: exec plan (English), history, skill cascade guide, ARCHITECTURE/SECURITY after rebase

Sequential and last. Depends on **06** (numbers, tau, gate verdicts). Step 07b (ARCHITECTURE.md and SECURITY.md) also
depends on **workstream B (docs translation PR) being merged into `origin/main`**. Executor: docs-manager (sonnet). An opus
reviewer checks the SECURITY.md wording and the cascade guide before commit.
Worktree: `/Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/decision-model`.

## Goal

Make every doc that the tool makes stale accurate, all in English. Ship the host-side cascade guide where hosts and skill
users read it. Record the measured gates honestly, whether they passed or failed (D2). Hand over the one live check that
an agent session cannot run.

## Context (verified)

- The exec plan `docs/exec-plans/active/20260922-local-decision-model-mcp-tool.md` is in Chinese. Workstream B **excludes**
  it (the B worktree has no change to it; checked 2026-09-23), so D owns its translation. B **does** modify
  `docs/ARCHITECTURE.md` and `docs/SECURITY.md` (B worktree `git status`: ` M docs/ARCHITECTURE.md`, ` M docs/SECURITY.md`).
  Editing those two files before B merges guarantees a conflict, so they are edited only after rebasing on a `main` that
  contains B.
- ARCHITECTURE.md mentions "9 tools" on six lines of the Chinese version (`docs/ARCHITECTURE.md:3`, `:12`, `:65`, `:68`,
  `:145`, `:158`). Re-locate them by grep after the rebase, because line numbers will change. Update only the macOS-scoped
  ones (`:3`, `:65`, `:68` equivalents). `:12` is the smoke runner, which strips the env var and still exercises 9.
  `:145` and `:158` are the Windows and Linux runtimes, which stay at 9.
- `dist/` is gitignored (`.gitignore:5`), so `scripts/package-skill.sh` output is never committed.
- The skill is `skills/open-computer-use/` (`SKILL.md` plus `references/{installation,usage,troubleshooting}.md`, and
  `agents/openai.yaml`), and it is packaged by `scripts/package-skill.sh`. Validation there checks only the frontmatter
  (`name:` and `description:`), and the zip includes every file under the folder, so a new `references/decision-model.md`
  ships automatically.
- The usage reference already sets the convention that MCP env vars belong in the server entry's `env`, and that the server
  must be restarted afterwards (`skills/open-computer-use/references/usage.md:149`).
- History notes: `scripts/new-history.sh <slug>` creates `docs/histories/YYYY-MM/YYYYMMDD-HHmm-<slug>.md` from the
  template. Content is written in English (memory note: docs in English only). Keep the template's section structure,
  translating its headings. Never include local paths, keys, or raw logs (`docs/HISTORY_GUIDE.md`).
- The exec plan's P0 risk text says the sidecar is "launched by the agent with a sanitized environment". Decision D3
  supersedes this: the sidecar is **user-started**. The translation must state the current design and record the change in
  the decision log, not silently rewrite history.
- `scripts/check-docs.sh` requires the docs skeleton files, and `make ci` runs it.

## Signature

Files and the required content (each bullet is checkable):

**07a — can run as soon as 06 is done**
1. `docs/exec-plans/active/20260922-local-decision-model-mcp-tool.md` — full English translation, same section order
   (Goal, Scope, Background, Risks, Milestones, Validation, Progress, Decisions). Updates:
   - Progress: the P0 gate is closed by user decision (2026-09-23, D2: build P1–P3; gates are measured and reported). P1
     ✔ with dataset size and split sizes. P2 ✔ with the readout pin (llama.cpp version, model key, semantics
     `pre_sampling_logprobs_renormalized_over_labels`) and p50/p95 (labelled "M4 Max 48 GB; optimistic bound for the 16 GB
     gate"). P3 ✔ with the tool shipped opt-in and experimental. The P3 step-count gate is **not measured**.
   - A **Measured gates** table copied from `summary.json`: gate, threshold, test-split value, PASS/FAIL. Plus tau and its
     dev/test precision and coverage. For every FAIL, the phase 06 paragraph is included verbatim.
   - Decisions (append, dated 2026-09-23): D2; D3 (user-started sidecar, which supersedes the agent-launched wording); one
     `/completion` call with two sequential heads instead of two requests (hybrid Qwen3.5 recurrent-state reason; plan.md
     K4); model choice and fallback (whichever phase 01 activated); real-app captures never committed (D4); Linux/Windows
     are a non-goal.
   - Status stays in `active/`, because the P3 step-count gate is open. The file is not moved to `completed/`.
2. `docs/histories/2026-09/<YYYYMMDD-HHmm>-local-decision-model-advisory-tool.md` (created with `scripts/new-history.sh local-decision-model-advisory-tool`)
   — in English: user query (sanitized), key actions, design intent (advisory only; the server never owns a goal), files
   modified (repo-relative paths only), and gate results in one line each.
3. `skills/open-computer-use/references/decision-model.md` (new), with sections:
   - *What it is*: experimental, macOS only, read-only, off by default, never acts.
   - *Setup*: `brew install llama.cpp`; `scripts/decision-model/fetch-model.sh` (explicit download, SHA-256 checked, about
     2.7 GB, never automatic); `scripts/decision-model/start-sidecar.sh` (loopback, per-user port `39000 + uid % 1000`,
     prints the export line); then put `OPEN_COMPUTER_USE_DECISION_MODEL_URL` in the MCP server entry's `env` and restart
     the host. Give one JSON `env` example and one Codex TOML `env` example. `stop-sidecar.sh` to stop. Memory: about
     16 GB unified memory recommended.
   - *Cascade guide*: the `DecisionAdvisor.cascadeGuide` text **verbatim**, in a fenced block.
   - *Result fields*: every key of the result JSON (phase 05 Signature) with one line each.
   - *Measured quality*: the gates table and tau from `summary.json`, with the date and model key.
   - *Security notes*: loopback only; the goal and candidate rows are sent to the local sidecar; screen text is untrusted
     input to the model; follow the destructive-action rule regardless of margin.
   - *Not supported*: Linux and Windows runtimes; no automatic weight download; no weights in npm.
4. `skills/open-computer-use/SKILL.md` — (a) after the core tool list sentence, add one sentence: on macOS an optional
   experimental `decide_next_action` advisory tool exists when a local decision model is configured; see
   `references/decision-model.md`. (b) Add a References bullet for `references/decision-model.md`. The core tool list
   and the frontmatter stay unchanged.

**07b — only after B is merged**
5. `git fetch origin && git rebase origin/main` (the D branch). Resolve nothing by hand in B's files. If the rebase
   conflicts in ARCHITECTURE.md or SECURITY.md, the D branch touched them early, which is a violation → Failure Protocol.
6. `docs/ARCHITECTURE.md` (English after B) — the tool count wording becomes "9 Computer Use tools, plus the opt-in,
   macOS-only `decide_next_action` advisory tool". Add a short subsection "Local decision model (experimental)" with the
   data flow (host → proxy → app-agent → pruning → loopback `/completion` → advisory JSON); the per-call env gating of
   `tools/list`; that the call holds the app-agent env-override lock for ≤ 12 s; and that the sidecar is user-started and
   never spawned by the server.
7. `docs/SECURITY.md` (English after B) — a subsection "Local decision model" covering: loopback-only enforcement (the
   exact accepted hosts, no redirects, no proxies, 1 MiB cap, 5 s/12 s timeouts); why the URL may travel on the per-call env
   channel (a same-uid peer can already read the tree with `get_app_state`, so a redirected URL gains no new capability;
   plan.md K8); residual risk of loopback port squatting by another local user (the start script checks the port owner);
   prompt-injection handling (special-token scrubbing, row truncation, grammar-constrained output, advisory only); weights
   are fetched explicitly with SHA-256 pinning and never shipped in npm; eval captures of real apps are never committed.

## Boundaries

```
TARGET:    docs/exec-plans/active/20260922-local-decision-model-mcp-tool.md
           docs/histories/2026-09/*-local-decision-model-advisory-tool.md                  (new)
           skills/open-computer-use/references/decision-model.md                           (new)
           skills/open-computer-use/SKILL.md
           docs/ARCHITECTURE.md, docs/SECURITY.md                                          (07b only, after rebase)
READ-ONLY: scripts/decision-model/eval-data/summary.json, scripts/decision-model/model-manifest.json,
           scripts/decision-model/fixtures/readout-pin.json, DecisionAdvisor.swift (the cascadeGuide source text),
           the phase 06 report, ../reports/auto-decisions-260923-0939-notarize-translate-decision-model.md
FORBIDDEN: any Swift, Package.swift, or scripts/** change (a doc that disagrees with code is a STOP, never a code edit);
           README.md and README.zh-CN.md (the tool is experimental and documented in the skill reference);
           docs/releases/** (no version bump in this workstream);
           editing ARCHITECTURE.md or SECURITY.md before `origin/main` contains workstream B's merge;
           translating or touching any other Chinese doc (workstream B owns them);
           real snapshot text, personal file names, or local absolute paths in any doc;
           rounding or restating a gate number differently from summary.json
```

## Steps

1. 07a items 1–4. Take every number from `summary.json` by copy, never retyping it from memory.
2. Verify 07a (Acceptance block A) and commit 07a on its own (`git add` the explicit paths).
3. Check whether B has merged: `git fetch origin && git log origin/main --oneline -20 | grep -i -E 'translat|english'`.
   If B has **not** merged, stop here with `Status: DONE_WITH_CONCERNS`: "07b pending B merge", and leave items 5–7 as a
   handover checklist in the report. That is not a failure.
4. If B has merged: items 5–7, then verify (Acceptance block B) and commit.
5. Write the **handover checklist** in the phase report and in the PR description. These are live checks that an agent
   session cannot run (the debug CLI dies in agent sessions, and the MCP env is fixed at host start):
   rebuild and redeploy the Dev.app (memory: rm-first deploy, kill the stale agent, re-grant TCC if needed); start the
   sidecar; add the env var to the host MCP config; restart the host; confirm `decide_next_action` is listed; call it on the
   fixture app with goal "increment the counter"; confirm the advised `element_index` is the Increment button, and that
   `click` on it works. Then remove the env var and confirm the tool disappears.

## Acceptance

**Block A (after 07a):**
```
grep -c -P '[\x{4e00}-\x{9fff}]' docs/exec-plans/active/20260922-local-decision-model-mcp-tool.md     # 0  (use: perl -CSD -ne '$c++ if /\p{Han}/; END{print $c+0,"\n"}' <file> if grep lacks -P)
grep -F 'Follow the advice only when margin >= recommended_min_margin' skills/open-computer-use/references/decision-model.md \
  && grep -F 'Follow the advice only when margin >= recommended_min_margin' packages/OpenComputerUseKit/Sources/OpenComputerUseKit/DecisionAdvisor.swift   # both match
node -e 'const s=require("./scripts/decision-model/eval-data/summary.json");const fs=require("fs");
  const md=fs.readFileSync("docs/exec-plans/active/20260922-local-decision-model-mcp-tool.md","utf8");
  for(const g of s.gates){ if(!md.includes(g.pass?"PASS":"FAIL")) throw g.name; }
  if(!md.includes(String(s.tau.value))) throw "tau"; console.log("gates quoted")'                    # prints "gates quoted"
grep -c 'references/decision-model.md' skills/open-computer-use/SKILL.md                              # ≥ 1
scripts/package-skill.sh && unzip -Z1 dist/skills/open-computer-use-skill.zip | grep -c 'open-computer-use/references/decision-model.md'   # 1
grep -R -n -E '/Users/|CANARY' docs/histories/2026-09/*local-decision-model* skills/open-computer-use/references/decision-model.md | wc -l   # 0
make ci                                                                                                # green
```
**Block B (after 07b):**
```
git merge-base --is-ancestor <B merge commit> HEAD                                                    # exit 0
perl -CSD -ne '$c++ if /\p{Han}/; END{print $c+0,"\n"}' docs/ARCHITECTURE.md docs/SECURITY.md          # 0 (B already translated them)
grep -c 'decide_next_action' docs/ARCHITECTURE.md docs/SECURITY.md                                     # ≥ 1 each
grep -c -i 'loopback' docs/SECURITY.md                                                                 # ≥ 1
make ci && swift test                                                                                  # green
```
(`dist/` is gitignored, so `package-skill.sh` output never enters git.)

## Success criteria

No Chinese remains in the exec plan. The cascade guide text is identical in Swift and in the skill reference. The gate
verdicts in the exec plan match `summary.json`. The history note exists. After B merges, ARCHITECTURE.md and SECURITY.md
describe the tool, and CI is green. The handover checklist is in the PR description.

## Risks and rollback

- B has not merged by the time 07 runs → 07b is deferred with a checklist (step 3). The D PR can still merge first,
  because 07a touches no file that B owns.
- Doc drift from code → every number is copied from generated files, and the cascade guide is grep-matched against the
  Swift source.
- Rollback: `git revert` the 07a and 07b commits. They are docs-only, so there is no runtime effect.

## Contract Rules

1. Implements to the SIGNATURE exactly. A signature that cannot work is a STOP, not a redesign — report it through the Failure Protocol.
2. Edits only within TARGET. Discovering that the change genuinely requires a FORBIDDEN file is a STOP with that finding, never a quiet widening.
3. Writes the acceptance assertions first where the plan says tests-first, confirms they FAIL, then implements until they pass.
4. Never weakens an assertion, never marks a test skipped, and never stubs an implementation to make one pass. A passing suite obtained this way is the specific failure this whole contract is built to prevent — cheap tiers reward-hack checkable specs more than strong ones do, so the escalation path exists precisely for the moment the spec looks unsatisfiable.
5. On any failed Verify, follows the `## Failure Protocol` already in the phase file. That is the backchannel; using it is correct behaviour, not an admission of failure.

## Failure Protocol

On any failed Verify or Acceptance step (non-zero exit, failed assertion, or output that differs from what is specified
here), the executor stops reasoning about the fix on its own. It spawns the `kongming` agent with: this phase file's path,
the exact failing command and its full output, `git diff -- <TARGET files>`, and the approaches already tried. It waits
for the advice, applies it within TARGET only, and re-runs the failed step. If `kongming` is unavailable, or its advice
needs a FORBIDDEN file or a changed Signature, the executor STOPS and reports `Status: BLOCKED` with the evidence. It never
silently retries the same approach and never weakens an assertion to get green. Step 3's "B not merged yet" outcome is
a planned deferral, not a failed Verify.
