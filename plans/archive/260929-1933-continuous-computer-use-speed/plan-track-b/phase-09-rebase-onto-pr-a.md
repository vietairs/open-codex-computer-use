# Phase 09: rebase onto main after PR A merges

Depends on: phase 08 gate passed AND PR A merged into `origin/main` (vietairs fork; never `upstream`). Blocks: 10.
Owner: implementer for conflict resolution; the phase 08 reviewer re-reviews the hand-resolved hunks. Risk: High
(certain conflicts in shared files; silent loss of either track's lines). Effort 2.5h.

## Execution constants

- `WT=/Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/fast-macos-channels`, branch
  `feat/fast-macos-channels`. Remote `origin` = `vietairs/open-codex-computer-use` (verified 2026-09-29). Never rebase on
  or push to `upstream`.
- Precondition check: `cd "$WT" && git fetch origin && git log --oneline origin/main -5` shows the PR A merge commit, and
  `git status --short` is empty.
- `K=packages/OpenComputerUseKit/Sources/OpenComputerUseKit`, `T=packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests`,
  `S=apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite`.
- Parallel-tracks rules 7-8 apply: B edits MCPServer.swift :16 and appends; B resolves :10 by hand.

## Files both tracks edit (expected conflicts)

| File | Track A change | Track B change | Resolution |
|---|---|---|---|
| `K/ToolDefinitions.swift` | `perform_actions` appended to `all` as the LAST element (Track A test asserts `all.last?.name == "perform_actions"`, track A phase-05:285); `include_screenshot` on six action schemas | `find_elements` appended to `all` | Keep both elements with `find_elements` placed immediately BEFORE `perform_actions`, so `perform_actions` stays last. Never edit A's test. |
| `K/ComputerUseToolDispatcher.swift` | `perform_actions` case | `find_elements` case | Keep both cases before `default:`. |
| `K/ComputerUseService.swift` | action methods take `ActionContext`; `refreshSnapshot` gains capture policy; single write point of `snapshotsByApp` (track A phase-01:118) | extension appended at EOF that ALSO writes `snapshotsByApp` (a second writer, keys from `snapshotCacheKeys`) | Keep B's extension at EOF. Fold both writers into one `private func storeSnapshot(_ snapshot: AppSnapshot, query: String, app: RunningAppDescriptor)` that loops over `snapshotCacheKeys(query:app:)`; A's `refreshSnapshot` write loop and B's extension both call it (Task 9.1 step 5). If A moved `snapshotsByApp` to another file, STOP (visibility change needed; Failure Protocol). |
| `K/MCPServer.swift` | :8, :14 rewritten | :10 list, :16 interpolation, appended find_elements line | :10 by hand: `list_apps, get_app_state, find_elements, click, perform_secondary_action, scroll, drag, type_text, press_key, set_value, and perform_actions` (match A's final wording). Keep A's :8/:14 verbatim, B's :16 and appended line. Append `and \`perform_actions\`` to B's find_elements sentence. |
| `K/LocalChannelGuidance.swift` (B only) | none | script-first guide | Decision 9 names "find_elements plus the batch tool": the guide's UI sentence becomes `find_elements` plus element-targeted actions or `perform_actions` (Task 9.1 step 6). |
| `T/OpenComputerUseKitTests.swift` | count 9->10 at :256; guiTools maybe +perform_actions | 9->10 and guiTools +find_elements | Final: `all.count == 11`; guiTools contains both new names, count 11. |
| `T/DecisionAdvisorTests.swift` | :437 -> 10, names | :437 -> 10, names | Final: all 11 (`...StaysElevenAnd...`), loopback listed 12, non-loopback 11 (`...StaysAtEleven`). |
| `S/main.swift` (smoke) | 9 -> 10 | 9 -> 10, flag-on case expects 15 | Final: 11 flag unset; 16 flag set. Not on the parallel-tracks shared list; the main loop adds it. |
| `skills/open-computer-use/SKILL.md`, `references/usage.md` | batching guidance, tool list | find_elements + fast channels | Keep both; tool list names both. |
| `docs/ARCHITECTURE.md` | tool count | tool count + router paragraph | macOS main line: 11 tools. |

## Task 9.1: rebase and resolve

- Steps:
  1. `cd "$WT" && git rebase origin/main`. For each conflict apply the table; never take one side wholesale for the
     files above.
  2. Dedupe (parallel-tracks rule 6), only if PR A's API allows it without editing A-owned logic:
     - If A exposes a no-capture window resolution (e.g. a capture flag on window resolution), switch
       `resolveElementSearchWindow` to it and delete B's CGWindowList copy.
     - If A exposes a batched multi-attribute AX read helper, use it inside `AccessibilityElementSearchSource.read`
       only if it still performs exactly ONE `AXUIElementCopyMultipleAttributeValues` call per node.
     - If A makes `CGRect.renderedLocalFrame` non-private, replace B's `elementSearchRenderedFrame` copy with it
       (`testRowFormat` keeps the literal).
     - Otherwise keep B's private copies and note it in the PR body.
  3. Add two tests in `T/ElementSearchTests.swift` [UNVERIFIED: depends on PR A's final `perform_actions` API; adapt
     names, not intent]:
     - a `perform_actions` step naming `run_script` (or any local tool) is rejected at validation;
     - a merged snapshot's hit index resolves through the same lookup `perform_actions` uses for its pinned snapshot.
  4. Confirm with A's merged code that the "fresh cached snapshot" rule treats a merged snapshot as usable for index
     lookup only, never as a reason to skip the post-action refresh; if A's code would skip, STOP (Failure Protocol).
  5. Single cache writer: add `storeSnapshot(_:query:app:)` inside the `ComputerUseService` class body next to
     `refreshSnapshot`; replace A's inline key loop with one call to it and route B's extension through it. No other
     line of `refreshSnapshot` changes. User decision (2026-09-29): Track B extracts this helper here at the rebase;
     Track A does not land it. If PR A nevertheless ships an equivalent helper, call it instead and skip the extraction.
  6. `K/LocalChannelGuidance.swift`: the guide's UI sentence names `perform_actions` next to `find_elements`; add
     `testScriptFirstGuideNamesBatchTool` to `T/LocalChannelGuidanceTests.swift` (contains `perform_actions`).
- Verify:
  1. `cd "$WT" && swift build && swift test 2>&1 | tail -15` exits 0 and prints `with 0 failures`.
  2. `cd "$WT" && grep -n "ToolDefinitions.all.count" packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/*.swift`
     shows only `11`. Identical hunks from both tracks (the 9 -> 10 edits and the `StaysTen` renames) merge without a
     conflict and stay stale, so also check: `grep -n "listed.count" .../DecisionAdvisorTests.swift` shows `12`
     (loopback) and `11` (non-loopback); `grep -nE "Stays(Nine|Ten|AtNine|AtTen)" .../DecisionAdvisorTests.swift`
     prints nothing and `grep -cE "StaysEleven|StaysAtEleven" .../DecisionAdvisorTests.swift` prints >= 2;
     `grep -n "guiTools.count" .../OpenComputerUseKitTests.swift` shows `11`.
  2a. `cd "$WT" && grep -n "snapshotsByApp\[" packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
     shows exactly one assignment line (inside `storeSnapshot`) plus read sites.
  2b. `ToolDefinitions.all.last?.name == "perform_actions"` (Track A's test, green in Verify 1) and
     `grep -n '"find_elements"' .../ToolDefinitions.swift` prints one line.
  3. `cd "$WT" && grep -n "tools.count ==" apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
     shows `11` (and `16` in the flag-on case).
  4. `cd "$WT" && grep -c "appleScriptAvoidanceInstructionLine" packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MCPServer.swift`
     prints `1`; `grep -c "perform_actions" .../MCPServer.swift` >= 1; `grep -c "find_elements" .../MCPServer.swift` >= 2.
  5. `cd "$WT" && git diff origin/main --stat` lists no Track-A-only file (`SoftwareCursorOverlay.swift`,
     `CursorMotionModel.swift`, `DecisionJev*.swift`, `AccessibilitySnapshot.swift` unless step 2 dedupe was applied
     and is called out).
  6. `cd "$WT" && bash scripts/check-docs.sh` exits 0.

## Task 9.2: delta review

- The phase 08 reviewer reads only the hand-resolved hunks and the dedupe changes, re-checks T2, T4, T14, T18 of
  `threat-model.md` and the single `snapshotsByApp` writer, and appends a "post-rebase" section to the phase 08 review report.
- Verify: the review report contains `post-rebase` and no open Critical/High.

## Rollback

Before rebasing: `cd "$WT" && git branch backup/fast-macos-channels-pre-rebase`. If the rebase goes wrong:
`git rebase --abort`, or after completion `git reset --hard backup/fast-macos-channels-pre-rebase` (main loop approval
required; this discards the rebase only). Delete the backup branch after phase 10 passes.

## Contract Rules

1. Implements to the SIGNATURE exactly. A signature that cannot work is a STOP, not a redesign —
   report it through the Failure Protocol.
2. Edits only within TARGET. Discovering that the change genuinely requires a FORBIDDEN file is a
   STOP with that finding, never a quiet widening.
3. Writes the acceptance assertions first where the plan says tests-first, confirms they FAIL, then
   implements until they pass.
4. Never weakens an assertion, never marks a test skipped, and never stubs an implementation to
   make one pass. A passing suite obtained this way is the specific failure this whole contract is
   built to prevent — cheap tiers reward-hack checkable specs more than strong ones do, so the
   escalation path exists precisely for the moment the spec looks unsatisfiable.
5. On any failed Verify, follows the `## Failure Protocol` already in the phase file. That is the
   backchannel; using it is correct behaviour, not an admission of failure. The escalation names
   the failure's class: a missed edge case, a wrong or incomplete fix, a misread requirement
   (including a wrong reading of an ambiguous one), or a wrong domain rule. The first two are
   fixed by more verification. The last two are not fixed by more effort or by a retry: they need
   the outcome re-locked or the rule looked up, so name the class in the escalation instead of
   retrying.

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
