# Phase 07: Agent guidance and docs (decision 6; advisor corrections 2, 3 and 4)

- **Depends on:** 05, because the guidance names `perform_actions`. For accuracy, the docs text also relies on 01, 02 and 06.
- **Parallel-safe with:** 06 Task 6.5.
- **Roles:** Tester ≠ Implementer.
- **Effort:** 1.5h.
- **Commit (exactly one):** `docs(guidance): teach batching and stop per-action get_app_state`
- Paths: `W`, `S` and `T` are as defined in phase 01.

## Context (verified at afb60fa)

- `S/MCPServer.swift`:
  - `:8` says "call `get_app_state` every turn".
  - `:10` is the tool list.
  - `:14` says "After each action, use the action result or fetch the latest state…".
  - `:16` is the AppleScript line. It is **owned by Track B** and must stay byte-identical, and at line 16 (parallel-tracks rule 8).
- The instruction tests compare against the Swift constant, not a literal (`T/OpenComputerUseKitTests.swift:625`, `T/DecisionAdvisorTests.swift:476/:507`), so rewording breaks nothing.
- The cascade-guide gate `listed.count > all.count` (`S/MCPServer.swift:26`) stays correct, because `perform_actions` is in `all`.
- `skills/open-computer-use/SKILL.md`:
  - `:14-16` claims the same tool surface on all three platforms;
  - Core Workflow `:20-32`;
  - `:39` says "Always run `get_app_state` before using `element_index`".
- `skills/open-computer-use/references/usage.md` sections: Text Limits `:71`, Choosing Targets `:101`, Platform Notes / macOS `:153-157`.
- `docs/ARCHITECTURE.md`:
  - `:3` (9 tools)
  - `:67` (get_app_state and action results)
  - `:72` and `:76` (cursor move duration 1.4291667s)
  - `:145` and `:158` (the Go runtimes "stay consistent with the macOS main line")
- AGENTS.md requires a `docs/histories/` entry, and all docs are in English (memory `docs-histories-in-english`).

## Signature (exact text: the executor copies it and invents nothing)

`S/MCPServer.swift`. Replace **lines 8, 10 and 14 in place, each staying a single line**, so that line 16 does not move. Then append one paragraph after line 17 and before the closing `"""`, with one blank line before it.

- Line 8:
  `Begin by calling \`get_app_state\` at the start of each assistant turn in which you want to use Computer Use, because the user may have changed the app since your last turn. Codex will automatically stop the session after each assistant turn, so this step is required before interacting with apps in a new assistant turn. Within a turn, action results already include the refreshed text state, so do not call \`get_app_state\` after every action.`
- Line 10:
  `The available tools are list_apps, get_app_state, click, perform_secondary_action, scroll, drag, type_text, press_key, set_value, and perform_actions. If any of these are not available in your environment, use tool_search to surface one before calling any Computer Use action tools.`
- Line 14:
  `After each action, use the action result to verify the UI changed as expected; call \`get_app_state\` only when the result lacks what you need. Action results are text-only unless you pass \`include_screenshot: true\`; take x/y coordinates only from the most recent screenshot you received.`
- Appended paragraph:
  `Use \`perform_actions\` for a short sequence you can fully specify from the current state, for example focusing a field, typing text and pressing Return. It runs the steps in order, stops at the first failure, and returns one final state with a line per step. Every \`element_index\` in the batch refers to the state you last received, so a step cannot target an element that an earlier step in the same batch reveals. Keep externally visible steps such as Send in their own call, after you confirm them.`

(The backslashes in the quoted lines above only escape the backticks for Markdown. In Swift they are plain backticks.)

`SKILL.md`:
- `:14-16`: keep the 9-tool sentence and add: `On macOS, \`perform_actions\` also runs a short, fully specified action sequence in one call; the Linux and Windows runtimes do not have it.`
- Core Workflow step 8 becomes: `Prefer element-targeted actions using \`element_index\` from the latest \`get_app_state\` or action result. Action results are text-only; pass \`include_screenshot: true\` when you need to see the window.`
- Add a new step after step 8, and renumber the ones after it: `On macOS, batch short sequences you can fully specify (focus a field, type, press Return) into one \`perform_actions\` call; keep externally visible steps such as Send in their own call.`
- `:39` becomes: `Always run \`get_app_state\` at the start of a turn before using \`element_index\`; within a turn, use indices from the latest \`get_app_state\` or action result. Do not guess indexes across sessions or after large UI changes.`

`usage.md`:
- Text Limits: add one line: `Action results are text-only by default; add \`include_screenshot: true\` to any action (or to \`perform_actions\`) to attach the window screenshot. A screenshot is attached automatically when the accessibility tree is empty.`
- Choosing Targets: add the same element_index rule as SKILL `:39`, plus the proven Mail pattern: `Mail search: focus the toolbar search field (for example with \`press_key\` \`cmd+option+f\`), then \`type_text\` and \`press_key Return\`; \`set_value\` fills the field but does not run the search.`
- A new `## Batching Actions (macOS)` section before `## Platform Notes`. It documents:
  - the `{tool, args}` step shape, which is the same shape as CLI `--calls`;
  - the allowed tools and the 10-step cap;
  - stop on first failure, the per-step lines, and one final state;
  - that element indices refer to the last received state;
  - that live focus and geometry are read per step and nearby hit-testing is off inside a batch;
  - one JSON example;
  - that a batch holds the per-call environment lock for its duration.
- Platform Notes / macOS: `perform_actions` is macOS-only.

`docs/ARCHITECTURE.md`:
- `:3`: the macOS server has 10 Computer Use tools (9 shared plus `perform_actions`), and the Go runtimes keep 9.
- `:67`: add that action results are text-only unless `include_screenshot` or an empty tree, that text-only builds skip the ScreenCaptureKit capture, that `decide_next_action` never captures, and that x/y coordinates reuse the last returned screenshot's pixel size or fail closed when the window changed.
- `:72` and `:76`: the recovered 1.4291667s timing is kept in `CursorMotionModel`, and the overlay caps blocking travel at 0.3s by time-compressing the same spring.
- `:145` and `:158`: add "except the macOS-only `perform_actions`".
- Add one sentence where the snapshot walk is described: per-node attributes are read in one `AXUIElementCopyMultipleAttributeValues` round trip.
- Add one sentence on the jev letter table at `…/decision-model/jev-letters/` (0600, per base_url and model, `resolved_at` TTL of 7 days).

History entry: `cd $W && ./scripts/new-history.sh continuous-computer-use-speed`. Fill in the template with:
- the request (condensed);
- the changes per phase;
- the motivation (per-lever measured deltas, taken from the main loop's M1–M6 table if it exists at commit time, otherwise "measured in the PR description");
- the key files.

It must contain no local paths and no secrets (HISTORY_GUIDE).

## Boundaries

```
TARGET:    S/MCPServer.swift (lines 8, 10, 14 in place + one appended paragraph)
           skills/open-computer-use/SKILL.md, skills/open-computer-use/references/usage.md
           docs/ARCHITECTURE.md (the listed lines), docs/histories/2026-09/<new file>
           T/ServerInstructionsGuidanceTests.swift (new; Tester only)
READ-ONLY: S/DecisionAdvisor.swift (cascadeGuide), README.md
FORBIDDEN: S/MCPServer.swift line 16 (Track B) and moving it; the Go runtimes' instructions (apps/OpenComputerUseLinux,
           apps/OpenComputerUseWindows) — non-goal; README.zh-CN.md; any Swift source other than MCPServer.swift
```

## Tasks

### Task 7.1: Failing test first (Tester)
- Create `T/ServerInstructionsGuidanceTests.swift` (class `ServerInstructionsGuidanceTests`) with the assertions listed below.
- Verify (RED): `swift test --filter OpenComputerUseKitTests.ServerInstructionsGuidanceTests 2>&1 | tail -30` exits non-zero with at least one `XCTAssertTrue failed` line (the current text lacks `perform_actions`).

### Task 7.2: Instructions (Implementer)
- Apply the MCPServer.swift text exactly as given.
- Verify:
  - The filtered test exits 0.
  - `sed -n 16p $S/MCPServer.swift` prints exactly `Avoid falling back to AppleScript during a computer use session. Prefer Computer Use tools as much as possible to complete tasks.`

### Task 7.3: Skill and docs (Implementer)
- Apply the texts above.
- Verify:
  - `./scripts/check-docs.sh` exits 0.
  - `grep -c 'perform_actions' skills/open-computer-use/SKILL.md skills/open-computer-use/references/usage.md docs/ARCHITECTURE.md` gives ≥ 1 for each file.
  - `swift test 2>&1 | tail -15` exits 0 and contains `with 0 failures`.
- Commit and report the SHA.

## Acceptance

Command: `cd $W && swift test --filter OpenComputerUseKitTests.ServerInstructionsGuidanceTests`

Assertions on `baseComputerUseServerInstructions` (write first):
- It contains `at the start of each assistant turn`. The start-of-turn get_app_state is kept (correction 2).
- It contains `do not call \`get_app_state\` after every action`.
- It does **not** contain `After each action, use the action result or fetch the latest state`.
- It contains `set_value, and perform_actions.`. The tool list names the tool (correction 3).
- It contains `Use \`perform_actions\` for a short sequence you can fully specify`.
- It contains `include_screenshot: true`.
- Element 12 (0-based) of `baseComputerUseServerInstructions.components(separatedBy: "\n")` equals the AppleScript line verbatim. The string body starts at source line 4, so element 12 is source line 16. The assertion covers content equality **and** position.
- `computerUseServerInstructions(environment: [:]) == baseComputerUseServerInstructions`. The cascade guide is still not appended without the advisory tool.

## Risks

| Risk | L×I | Mitigation |
|---|---|---|
| Line 16 moves and Track B's rebase goes wrong | M×M | Single-line replacements plus the position assertion |
| Agents drop start-of-turn freshness | L×H | Correction 2 is asserted by the test |
| Docs go stale on measured numbers | L×L | The history entry cites the M-table; ARCHITECTURE states mechanisms, not timings |

## Rollback

`git revert <C7>`. It is independent. Revert it before reverting phase 05.

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
