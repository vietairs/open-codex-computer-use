# Phase 03 — Eval capture (live MCP) and ground-truth labelling

Parallel group G1 (with 01, 02). No code dependencies. It needs the live `open-computer-use` MCP tools in an agent
session. Executor: the **main loop**, because only it holds the live MCP tools, on opus/fable. Goal generation uses sonnet
subagents; blind labelling uses **opus** subagents (frontier labeller); adjudication and spot-checks are done by the main
loop. Tests-first for the validator: a tester subagent writes `eval-dataset.test.mjs` before the implementer writes
`eval-dataset.mjs`.
Worktree: `/Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/decision-model`.

## Goal

Build ≥ 200 `(goal, snapshot, ground-truth operation + element_index)` items: ≥ 20 from the fixture app (committed) and
≥ 180 from Finder, System Settings, and TextEdit (local only, gitignored). Each snapshot stores the exact full and compact
text the live tool returned, so phase 06 can replay them through the shipped Swift pipeline.

## Context (verified)

- The live MCP `get_app_state` works from agent sessions; the repo debug CLI does not (exit 141; memory note).
- Compact mode is `get_app_state {"app":…, "compact": true}` (`ComputerUseToolDispatcher.swift:54-63`). The compact header
  starts `Compact actionable view:` (`AccessibilitySnapshot.swift:176-179`).
- Fixture app: executable target `OpenComputerUseFixture` (`Package.swift:15-17`). App name `OpenComputerUseFixture`
  (`FixtureBridge.swift:111`). Its tree has 10 elements, including increment button, text field, scroll area, and drag pad
  (`apps/OpenComputerUseFixture/Sources/OpenComputerUseFixture/main.swift:366-375`).
- A live Finder capture during scouting contained a third party's name and personal file names (D4). Real captures must
  never be committed.
- `.gitignore` currently ignores `artifacts/codex-dumps/` but not `artifacts/decision-eval/`.

## Signature

`.gitignore`: append the line `artifacts/decision-eval/`.

Snapshot file (JSON, one per captured screen):
```json
{ "schemaVersion": 1, "snapshotId": "finder-03", "source": "real" | "fixture", "app": "Finder",
  "capturedAt": "2026-09-23T11:02:00+10:00", "screenNote": "Applications folder, list view",
  "renderedFull": "<exact text content of get_app_state compact:false>",
  "renderedCompact": "<exact text content of get_app_state compact:true>" }
```
Item (JSONL, one per line):
```json
{ "schemaVersion": 1, "id": "finder-03-g02", "snapshotId": "finder-03", "source": "real", "goal": "…",
  "groundTruth": { "operation": "click", "elementIndex": 42 },
  "split": "dev" | "test",
  "labeling": { "generator": {"operation":"click","elementIndex":42},
                "labeler":   {"operation":"click","elementIndex":42,"confidence":"high"|"medium"|"low"},
                "agreement": true, "adjudicated": false, "spotChecked": false, "paraphrased": true } }
```
Operations: `click, set_value, type_text, scroll, press_key, wait, done`. `elementIndex` is an integer for
`click, set_value, scroll` and `null` for the rest (`type_text` targets the focused element, matching the MCP tool, which
has no `element_index`).

`scripts/decision-model/eval-dataset.mjs` (ES module, node built-ins only):
```js
export const OPERATIONS = ['click','set_value','type_text','scroll','press_key','wait','done'];
export const TARGETED = new Set(['click','set_value','scroll']);
export function splitFor(snapshotId /* string */) /* -> 'dev' | 'test' */;
    // first byte of sha256(snapshotId) even -> 'dev', odd -> 'test'
export function validateItem(item, snapshot /* object | undefined */, { committed = false } = {}) /* -> string[] errors */;
export function loadDataset(itemsPath, snapshotsDir) /* -> { items: object[], snapshots: Map<string, object> } */;
// CLI: node eval-dataset.mjs --check <items.jsonl> --snapshots <dir> [--committed]
//   prints one JSON object {n, bySource, byOperation, bySplit, agreementRate, adjudicated, paraphrasedRate, errors:[...]}
//   exit 0 iff errors is empty
```
`validateItem` rules:
1. required fields and types; `schemaVersion === 1`; operation ∈ OPERATIONS; `elementIndex` is an integer iff the
   operation ∈ TARGETED;
2. snapshot exists and `snapshot.source === item.source`; `item.split === splitFor(item.snapshotId)`;
3. parity: every compact row (lines after the `Compact actionable view:` header up to the first blank line, matching
   `^\d+ `) has its first segment (text before ` — `, with a trailing ` (focused)` removed) equal to some full-tree line
   stripped of leading tabs and spaces;
4. a targeted `elementIndex` appears as the leading integer of some stripped full-tree line;
5. with `committed: true`, any `source !== 'fixture'` is an error.

Committed paths: `scripts/decision-model/eval-data/fixture-items.jsonl` and `scripts/decision-model/eval-data/fixture-snapshots/*.json`.
Local paths: `artifacts/decision-eval/snapshots/*.json` and `artifacts/decision-eval/items-real.jsonl`.

## Boundaries

```
TARGET:    .gitignore
           scripts/decision-model/eval-dataset.mjs            (new)
           scripts/decision-model/eval-dataset.test.mjs       (new)
           scripts/decision-model/eval-data/fixture-items.jsonl        (new)
           scripts/decision-model/eval-data/fixture-snapshots/*.json   (new)
           artifacts/decision-eval/**                          (local only, gitignored, never committed)
READ-ONLY: apps/OpenComputerUseFixture/**, packages/OpenComputerUseKit/Sources/OpenComputerUseKit/FixtureBridge.swift,
           packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift
FORBIDDEN: any Swift source or Package.swift (phases 02/04/05); scripts/decision-model/{model-manifest.json,*.sh,check-readout.mjs,fixtures/**} (phase 01);
           scripts/decision-model/eval-run.mjs, eval-metrics*.mjs, eval-data/summary.json (phase 06);
           committing any file with source "real" or any path under artifacts/decision-eval/;
           destructive or externally visible UI actions (send, delete, purchase, sign-in, file moves outside the scratch folder);
           System Settings panes: Apple Account, Privacy & Security, Passwords, Wallet, Internet Accounts, Users & Groups;
           Mail, Messages, browsers; pasting real snapshot text into any report, commit message, or PR
```

## Steps

1. **Ignore first.** Append `artifacts/decision-eval/` to `.gitignore` and commit it alone
   (`git add .gitignore && git commit`). Verify: `git check-ignore -v artifacts/decision-eval/snapshots/probe.json` prints
   the rule.
2. **Validator, tests first.** The tester writes `eval-dataset.test.mjs` (`node:test`) covering: a valid fixture item
   passes; missing snapshot → error; `elementIndex` absent from the full tree → error; `type_text` with an integer index
   → error; `click` with null → error; a parity mismatch (compact row not in the full tree) → error; wrong `split` → error;
   `committed:true` with `source:"real"` → error; `splitFor` is deterministic and returns both values over 20 ids. Run it:
   it must fail. Then implement `eval-dataset.mjs` until green.
3. **Preflight the live tool.** `get_app_state {"app":"Finder","compact":true}` must contain `Compact actionable view:`.
   If it does not, STOP: the session's MCP binary predates PR #10 and needs a redeploy, which is outside this plan.
4. **Fixture captures (committed).** `swift build --product OpenComputerUseFixture --scratch-path .build-eval` (a separate
   scratch path, so it never contends with phase 02's `.build`). Launch the binary in the background, record its PID, and
   confirm `list_apps` shows it and `get_app_state` shows `ID: fixture-increment`. Capture 3 states: initial; after
   `set_value` on the text field; after clicking Increment twice. For each state, capture full then compact with no action
   in between. Write `fixture-snapshots/fixture-0N.json`. Author ≥ 7 goals per state (≥ 21 items) covering every
   operation. For the fixture, the executor labels directly, and a labeller subagent confirms blind. Kill the fixture PID
   at the end.
5. **Real captures (local).** Make a scratch folder `~/ocu-eval-scratch` with 10 dummy files (`report-draft.txt`,
   `budget-2026.numbers` placeholders, and so on) so Finder screens contain synthetic names. Capture ≥ 6 screens per app,
   using only navigation actions:
   - Finder: scratch folder in list, icon, and column views; the Applications folder; a Get Info window on a dummy file;
     the New Folder name field in edit mode.
   - System Settings: General, Appearance, Desktop & Dock, Keyboard, Displays, Sound.
   - TextEdit: a new document containing dummy text; the Font panel; the Save sheet; the Settings window; the Find bar; the
     Format menu open.
   Write each capture to `artifacts/decision-eval/snapshots/<app>-NN.json`.
6. **Goals.** Per real snapshot, spawn a sonnet generator subagent. Give it the snapshot's `renderedFull` only and ask for
   10–12 goals as JSON `{goal, operation, elementIndex, paraphrased}`. Quotas per snapshot: ≥ 5 `click`; ≥ 1
   `set_value`/`type_text` if a text-entry row exists; ≥ 1 `scroll` if a scroll area exists; ≥ 1 `press_key`; ≥ 1
   `wait`/`done`; ≥ 40% `paraphrased: true`, meaning the goal shares no word with the target row's title. Goals must
   describe user intent ("turn on dark mode"), never an index or a label.
7. **Blind labels.** Per snapshot, spawn an **opus** labeller subagent. Give it `renderedFull` plus the goal texts only,
   with the operation definitions above. It returns `{operation, elementIndex, confidence}` per goal.
8. **Agreement and adjudication.** If generator and labeller agree on the operation and (for targeted operations) the
   index, accept. Otherwise the main loop reads the full snapshot and either picks the correct answer (`adjudicated:true`)
   or drops the item as ambiguous (count it). Ground truth = the accepted answer.
9. **Spot-check.** Using a seeded (`20260923`) random sample of 10% of accepted items (≥ 20 items, stratified by app), the
   main loop verifies each one against the full tree and sets `spotChecked:true`. If more than 1 of every 20 is wrong,
   re-label that app's items with a fresh opus labeller and repeat.
10. **Assemble and validate.** Write `items-real.jsonl` (local) and `fixture-items.jsonl` (committed), with `split` from
    `splitFor`. Run the validator on both.
11. **Commit only the fixture files and the validator**, with explicit `git add` paths.

## Acceptance

```
git check-ignore -q artifacts/decision-eval/snapshots/probe.json                                  # exit 0
node --test scripts/decision-model/eval-dataset.test.mjs                                          # all pass (and failed before step 2's implementation)
node scripts/decision-model/eval-dataset.mjs --check scripts/decision-model/eval-data/fixture-items.jsonl \
     --snapshots scripts/decision-model/eval-data/fixture-snapshots --committed                   # exit 0, n >= 20
node scripts/decision-model/eval-dataset.mjs --check artifacts/decision-eval/items-real.jsonl \
     --snapshots artifacts/decision-eval/snapshots                                                # exit 0, n >= 180
git ls-files artifacts/decision-eval | wc -l                                                      # 0
git status --porcelain | grep -c 'decision-eval/'                                                 # 0 (the .gitignore line itself is committed)
make ci                                                                                           # green (node --check covers the new .mjs)
```
Reported stats (counts only, no content): fixture n + real n ≥ 200; each operation present; `paraphrasedRate ≥ 0.40`;
agreement rate; adjudicated count; dropped count; spot-check sample size and error count (≤ 1 per 20); dev/test split
sizes, both ≥ 60.

## Success criteria

≥ 200 validated items; the fixture subset is committed and passes `--committed`; zero real-app content is tracked by git.

## Risks and rollback

- Fixture app state file not visible to the live agent (different `$TMPDIR`) → preflight in step 4 fails → Failure Protocol.
- Labeller bias → blind second labeller, paraphrase quota, spot-check.
- Rollback: revert the phase commits. `rm -rf artifacts/decision-eval ~/ocu-eval-scratch` removes all local data.

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
silently retries the same approach and never weakens an assertion to get green.