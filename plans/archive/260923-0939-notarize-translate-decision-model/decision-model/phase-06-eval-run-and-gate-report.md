# Phase 06 — Eval run, bounded pruning tuning, gate report, tau

Sequential. Depends on **01** (sidecar and pin), **03** (dataset and validator), and **05** (`DecisionModelEval`,
`DecisionAdvisor`). Executor: a sonnet implementer writes the Node scripts. **Tests-first** for `eval-metrics.mjs`: a
tester writes `eval-metrics.test.mjs` first and confirms it fails. Any pruning-rule tuning in `DecisionCandidates.swift`
is done by an opus implementer, and each tuning change adds a unit test before the code change.
Worktree: `/Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/decision-model`.

## Goal

Measure the shipped pipeline on the ≥ 200-item dataset. Report top-1 accuracy, pruned-target rate (with per-rule
attribution), margin AUROC, and p50/p95 latency against the exec-plan gates. Pick `recommended_min_margin` (tau) from the
dev split and confirm it on the test split. Commit only an aggregate `summary.json` that contains no personal data. Under
decision D2 a failed gate is **reported, not blocking**: phase 07 still ships the tool opt-in and labelled experimental,
and the numbers go into the docs verbatim.

## Context (verified)

- The gates come from the exec plan (`docs/exec-plans/active/20260922-local-decision-model-mcp-tool.md`, milestones P1 and
  P2): top-1 ≥ 80%, margin AUROC ≥ 0.7, correct target pruned ≤ 5%, p50 decision latency < 1.5 s. The p50 gate is
  specified for a 16 GB M-series machine. The only hardware available is an Apple M4 Max with 48 GB, so the measured p50
  is an **optimistic bound** and is labelled as such.
- The P3 gate ("agents following the advice finish in fewer steps") needs agent-in-the-loop A/B runs. It is **not
  measured** in this plan and is recorded as such (plan.md open question 2).
- Harness contract: `DecisionModelEval (--prune-only | --url <loopback>)`, JSONL in and JSONL out (phase 05 Signature).
  Its output lines contain `chosen_row_text` / `row_text`, which is real screen text for real-app items, so raw results
  go **only** under the gitignored `artifacts/decision-eval/`.
- `loadDataset`, `validateItem`, `splitFor`, `OPERATIONS`, and `TARGETED` come from `scripts/decision-model/eval-dataset.mjs` (phase 03).
- The GT target may be absent from the compact view entirely: the compact view keeps only actionable roles
  (`AccessibilitySnapshot.swift:158-202`). That counts as pruned, with cause `not_actionable`. It is a P0 compact-view
  limitation, and `AccessibilitySnapshot.swift` stays FORBIDDEN.
- All tooling here is Node (built-ins only). No Python: the Homebrew-framework `python3` is SIGKILLed on this machine
  (memory note).
- At phase start, record `PHASE_BASE=$(git rev-parse HEAD)` in the report. The no-weakening check below diffs against it.

## Signature

`scripts/decision-model/eval-metrics.mjs` (ES module, node built-ins only):
```js
export const GATES = Object.freeze([
  { name: 'top1',             threshold: 0.80, cmp: '>=' },
  { name: 'auroc',            threshold: 0.70, cmp: '>=' },
  { name: 'prunedTargetRate', threshold: 0.05, cmp: '<=' },
  { name: 'p50Ms',            threshold: 1500, cmp: '<'  },
]);
/** Mann-Whitney AUROC; ties count 0.5; returns null when either class is empty. */
export function auroc(scores /* number[] */, positives /* boolean[] */) /* -> number | null */;
/** Nearest-rank percentile, p in (0, 100]; returns null for an empty array. */
export function percentile(values /* number[] */, p /* number */) /* -> number | null */;
/**
 * item: a dataset item (phase 03 schema); line: one harness output line for it.
 * -> { id, split, source, targeted, correct, opCorrect, targetCorrect /* null if !targeted */,
 *      prunedTarget /* null if !targeted */, pruneCause /* rule | 'not_actionable' | null */,
 *      margin /* null on error */, latencyMs /* advice.latency_ms, null on error */, error /* string | null */ }
 * correct = !error && advice.operation === gt.operation && (!TARGETED.has(gt.operation) || advice.element_index === gt.elementIndex)
 * prunedTarget = targeted && !line.offered_indices.includes(gt.elementIndex)
 * pruneCause = prunedTarget ? (line.dropped[String(gt.elementIndex)] ?? 'not_actionable') : null
 */
export function scoreItem(item, line);
/** Aggregates over scored items: {n, top1, opAccuracy, targetAccuracy, prunedTargetRate, prunedByCause, auroc, p50Ms, p95Ms, errors}.
 *  Errors count as incorrect in top1 and are excluded from auroc and latency. prunedTargetRate is over targeted items only. */
export function aggregate(scored);
/** Smallest margin t in the sorted distinct margins of `scored` (plus 1.0) such that items with margin >= t have
 *  precision >= minPrecision and coverage (share of items with margin >= t) >= minCoverage. Returns
 *  {tau, precision, coverage}; when none qualifies returns {tau: 1.0, precision: null, coverage: 0}. */
export function selectTau(scored, { minPrecision = 0.90, minCoverage = 0.10 } = {});
/** Builds the committed summary object from whitelisted fields only; never copies goal, row, or rendered text. */
export function buildSummary({ meta, dataset, metricsBySplit, tau, tauOnTest, tuningRounds, notes });
```
`scripts/decision-model/eval-run.mjs` CLI:
```
node scripts/decision-model/eval-run.mjs
    [--url http://127.0.0.1:<port>]       default: http://127.0.0.1:$((39000 + uid % 1000)); ignored with --prune-only
    [--prune-only]                        pruning metrics only; no sidecar needed
    [--split dev|test|all]                default all
    [--write-summary]                     writes scripts/decision-model/eval-data/summary.json (only without --prune-only)
    [--tuning-round <n> --tuning-note <text>]   appended to artifacts/decision-eval/tuning-log.json
  Loads scripts/decision-model/eval-data/fixture-items.jsonl (+ fixture-snapshots) and, if present,
  artifacts/decision-eval/items-real.jsonl (+ snapshots); validates every item with validateItem and aborts (exit 2) on
  any error. Builds DecisionModelEval once (`swift build --product DecisionModelEval`), spawns .build/debug/DecisionModelEval
  once, sends 3 warm-up lines (fixture items, ids prefixed "warmup-", discarded), then every item in dataset order.
  Writes raw lines to artifacts/decision-eval/results-<YYYYMMDD-HHmm>.jsonl. Prints the aggregate per split as JSON.
  Exit 0 on a completed run regardless of gate outcome (gates are reported, not enforced); non-zero only for
  harness/validation failures.
```
`scripts/decision-model/eval-data/summary.json` top-level keys (exact): `schemaVersion` (1), `generatedAt`, `model`
(`{key, sha256}` from the manifest), `llamaCpp` (`{version}` from the pin), `hardware` (`{chip, memoryGB}` from
`sysctl -n machdep.cpu.brand_string` / `hw.memsize`), `dataset` (`{n, fixture, real, bySplit, byOperation}`),
`metrics` (`{all, dev, test}`, each an `aggregate` result), `tau` (`{value, devPrecision, devCoverage, testPrecision, testCoverage}`),
`gates` (`[{name, threshold, cmp, value, split: "test", pass}]`), `tuningRounds` (`[{round, note, devTop1, devPrunedTargetRate}]`),
`notes` (string array, including the hardware-bound note and "P3 step-count gate not measured").

## Boundaries

```
TARGET:    scripts/decision-model/eval-metrics.mjs                                  (new)
           scripts/decision-model/eval-metrics.test.mjs                             (new)
           scripts/decision-model/eval-run.mjs                                      (new)
           scripts/decision-model/eval-data/summary.json                            (new, generated)
           packages/OpenComputerUseKit/Sources/OpenComputerUseKit/DecisionCandidates.swift        (tuning only, see Steps 5)
           packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/DecisionCandidatesTests.swift (add tests only)
           packages/OpenComputerUseKit/Sources/OpenComputerUseKit/DecisionAdvisor.swift           (the recommendedMinMargin literal only)
           artifacts/decision-eval/**                                               (local only, gitignored)
READ-ONLY: scripts/decision-model/eval-dataset.mjs, eval-data/fixture-*, model-manifest.json, fixtures/readout-pin.json,
           start-sidecar.sh / stop-sidecar.sh (run them, do not edit), experiments/DecisionModelEval/**
FORBIDDEN: editing or deleting any existing DecisionCandidatesTests assertion (tuning may only ADD tests);
           DecisionPrompt.swift, DecisionModelClient.swift, ToolDefinitions.swift, MCPServer.swift, ComputerUseService.swift,
           ComputerUseToolDispatcher.swift, AccessibilitySnapshot.swift, Package.swift, experiments/**;
           any dataset item or ground-truth label edit to improve a metric (labels are frozen after phase 03's spot-check);
           any tuning decision informed by test-split results; more than 3 tuning rounds;
           committing artifacts/decision-eval/** or any file containing goal, row, or rendered text;
           docs/**, skills/** (phase 07); npm dependencies
```

## Steps

1. **Metrics tests first.** The tester writes `eval-metrics.test.mjs` (`node:test`):
   - `auroc([0.9,0.8,0.2,0.1],[true,true,false,false]) === 1`; the reversed labels give `0`;
     `auroc([0.5,0.5],[true,false]) === 0.5`; `auroc([1],[true]) === null`.
   - `percentile([1,2,3,4,5,6,7,8,9,10],50) === 5`; `…,95) === 10`; `percentile([],50) === null`.
   - `scoreItem`: correct click; right op + wrong index → `correct false, targetCorrect false`; `press_key` GT with
     advice `press_key` and any index → `correct true`; GT index not offered and present in `dropped` as `menu_bar` →
     `prunedTarget true, pruneCause 'menu_bar'`; GT index not offered and absent from `dropped` → `'not_actionable'`;
     harness `error` set → `correct false, margin null`.
   - `aggregate`: errors count against `top1` but are excluded from `auroc` / `p50Ms`; `prunedTargetRate` uses targeted
     items only.
   - `selectTau`: a constructed set where margin ≥ 0.6 gives precision 0.95 over 30% of items → `tau === 0.6`; a set that
     never reaches 0.9 → `{tau: 1.0, coverage: 0}`.
   - Privacy: build a summary from scored items whose goals and row texts contain `CANARY-PII-7f3a`. Then
     `JSON.stringify(summary)` does not contain the canary, and its top-level keys equal exactly the 11 listed in the
     Signature.
   Run the tests (they must fail), then implement `eval-metrics.mjs` until they are green.
2. **Runner.** Implement `eval-run.mjs`. Dry run: `node scripts/decision-model/eval-run.mjs --prune-only --split all`
   → exit 0, and it prints the pruned-target rate and per-cause counts.
3. **Baseline run (round 0).** Run `scripts/decision-model/start-sidecar.sh` (it must print the export line). Then run
   `node scripts/decision-model/eval-run.mjs --tuning-round 0 --tuning-note baseline` and record the dev and test
   aggregates.
4. **Decide whether to tune.** Tune only if dev `prunedTargetRate > 0.05`, **or** a single prune rule accounts for ≥ 3
   dev-split pruned targets. Look only at dev-split pruned items, and read them from the local results file (never paste
   their text into reports; describe patterns abstractly, for example "a menu-bar rule drops a toolbar item in app X").
5. **Tuning round r (r ≤ 3), dev split only.** For each change: (a) add a failing synthetic unit test to
   `DecisionCandidatesTests.swift` that encodes the missed pattern; (b) change the rule in `DecisionCandidates.swift` so it
   stays deterministic and fail-open; (c) `swift test --filter DecisionCandidatesTests`, then `swift test`, both green;
   (d) `eval-run.mjs --prune-only --split dev`, then a full run with `--tuning-round r`. Stop early once dev
   `prunedTargetRate ≤ 0.05`. Commit each round separately (`git add` the explicit paths).
6. **Tau.** `selectTau` on the final dev results. Set `DecisionAdvisor.recommendedMinMargin` to `tau` rounded **up** to 2
   decimals (1.0 if nothing qualifies). Run `swift test` (the phase 05 JSON test reads the constant, so it stays green).
   Compute precision and coverage on test at the same tau.
7. **Final run + summary.** `node scripts/decision-model/eval-run.mjs --write-summary`. Gates are evaluated on the **test**
   split. Then run `scripts/decision-model/stop-sidecar.sh`.
8. **Gate report.** Write the phase report (in the plan's `reports/` directory, not in `docs/`). Include a gate table with
   PASS/FAIL, the per-cause pruned counts, the tuning log, tau, and the hardware note. If any gate fails, write one
   paragraph per failed gate: the observed value, the most likely cause (from dev-split evidence only), and what it means
   for a host following the advice. Phase 07 copies this into the exec plan. A failed gate does **not** stop phase 07 (D2).

## Acceptance

```
node --test scripts/decision-model/eval-metrics.test.mjs                  # all pass (failed before step 1's implementation)
node --check scripts/decision-model/eval-run.mjs
node scripts/decision-model/eval-run.mjs --prune-only --split all          # exit 0
node -e 'const s=require("./scripts/decision-model/eval-data/summary.json");
  const need=["schemaVersion","generatedAt","model","llamaCpp","hardware","dataset","metrics","tau","gates","tuningRounds","notes"];
  if(JSON.stringify(Object.keys(s).sort())!==JSON.stringify(need.sort())) throw "keys";
  if(s.dataset.n<200||s.dataset.fixture<20) throw "n";
  if(s.gates.length!==4||s.gates.some(g=>typeof g.pass!=="boolean"||g.split!=="test")) throw "gates";
  if(!(s.tau.value>0&&s.tau.value<=1)) throw "tau";
  if(s.tuningRounds.length<1||s.tuningRounds.length>4) throw "rounds";
  console.log("summary ok")'                                                # prints "summary ok"
grep -c 'recommendedMinMargin' packages/OpenComputerUseKit/Sources/OpenComputerUseKit/DecisionAdvisor.swift   # ≥ 1, literal == summary tau
swift test                                                                 # green
git ls-files artifacts/decision-eval | wc -l                               # 0
git diff --numstat "$PHASE_BASE"..HEAD -- packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/DecisionCandidatesTests.swift | awk '{print $2}'   # "0" or empty: tuning deleted no test lines
make ci                                                                    # green
! lsof -nP -iTCP:39501 -sTCP:LISTEN                                        # sidecar stopped
```
Privacy spot-check (manual, recorded in the report): `grep -c` of 5 distinctive row strings taken from **local** real
snapshots against `scripts/decision-model/eval-data/summary.json` gives 0 for each.

## Success criteria

`summary.json` is committed with n ≥ 200 and all four gates evaluated on the test split. The tau literal in
`DecisionAdvisor.swift` equals `summary.tau.value`. There are ≤ 3 tuning rounds, each with an added unit test. No existing
test is weakened. The phase report states PASS/FAIL per gate in plain words.

## Risks and rollback

- Overfitting pruning to the eval: dev/test split by snapshot (`splitFor`), ≤ 3 rounds, gates judged on test only.
- Sidecar left running: step 7 stops it. The process-management rule applies, so the executor stops only the pid recorded
  in the pid file.
- Latency skew from the first request: 3 warm-up lines are discarded. The p50 is additionally labelled with the hardware.
- Rollback: revert the tuning commits individually (each is self-contained with its test), reset the tau literal to 1.0,
  and delete `summary.json`.

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
silently retries the same approach and never weakens an assertion to get green. A gate that measures below its threshold
is **not** a failed Verify. It is a result, and it is reported (D2). A failed Verify is a command that errors or an
assertion in the Acceptance block that does not hold.
