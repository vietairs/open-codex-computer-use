# Phase 07: guidance and docs

Depends on: phases 04 (guidance constants) and 05 (find_elements exists). Parallel group G4 (with phase 06; disjoint
files). Blocks: 08. Risk: Medium (MCPServer.swift is a certain rebase conflict with Track A). Effort 3h.
**Touches files Track A also edits:** `K/MCPServer.swift` (:10), `SKILL.md`, `usage.md`, `docs/ARCHITECTURE.md`.
`README.md` is read-only for Track A (Track A phase 07 Boundaries), so the Trust boundary edit does not collide.
Track A owns MCPServer.swift :8 and :14 and leaves :16 byte-identical (Track A brainstorm §1); Track B owns :16.

## Execution constants

- `WT=/Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/fast-macos-channels`; run as `cd "$WT" && ...`.
- All docs in English (repo rule, `AGENTS.md`). A history entry is required for a completed code change
  (`docs/HISTORY_GUIDE.md`; create with `scripts/new-history.sh fast-macos-channels`, which writes
  `docs/histories/2026-09/<timestamp>-fast-macos-channels.md` from `docs/histories/template.md`).
- Roles: tester writes Task 7.1; a different implementer does Task 7.2.

## Task 7.1 (tester): failing guidance tests

- Target: new `T/LocalChannelGuidanceTests.swift`.
- Assertions: see Acceptance.
- Verify (RED is the pass condition): `cd "$WT" && swift test --filter LocalChannelGuidanceTests 2>&1 | tail -30` exits
  non-zero and reports a failure in `testBaseInstructionsNameFindElements` (the other tests may already pass).

## Task 7.2 (implementer): guidance text and docs

- Steps:
  1. `K/MCPServer.swift:10`: the tool list sentence becomes `The available tools are list_apps, get_app_state,
     find_elements, click, perform_secondary_action, scroll, drag, type_text, press_key, and set_value.` (rest of the
     line unchanged).
  2. `K/MCPServer.swift:16`: replace the literal sentence with `\(appleScriptAvoidanceInstructionLine)` (the output
     string is byte-identical; `computerUseServerInstructions` equality tests at `T/OpenComputerUseKitTests.swift:625`
     and `T/DecisionAdvisorTests.swift:476,507` must stay green).
  3. `K/MCPServer.swift`, append one line after :17 (last line of the literal):
     `To act on one specific control without reading the whole tree, call \`find_elements\` with a role, label or identifier; its element_index values work with the action tools until the next state refresh.`
  4. `skills/open-computer-use/SKILL.md`: add `find_elements` to the tool list (line 15-16) and a short "Fast channels"
     section: find_elements usage, and that `OPEN_COMPUTER_USE_ENABLE_SCRIPTING=1` in the MCP server's launch
     environment adds `run_script`, `get_scripting_dictionary`, `open_url`, `run_shortcut`, `list_shortcuts`; the
     turn-start `get_app_state` applies to UI work (a turn that only uses `run_script` skips it), and `find_elements`
     is the call to make after a script changed the UI; link `references/scripting.md`.
  5. `skills/open-computer-use/references/usage.md`: a `find_elements` subsection (arguments, index lifetime, example
     `open-computer-use call find_elements --args '{"app":"Mail","role":"AXTextField","label":"Search"}'`) and a pointer
     to `scripting.md`. State that `open-computer-use call run_script` is not supported (scripts run only in the MCP
     server process).
  6. New `skills/open-computer-use/references/scripting.md`, covering each item of `threat-model.md` (plan dir) "Residual
     risks" plus: how to enable (flag in the host's MCP server env, never per call); the five tools and their args;
     TCC model (grant is per host app x target app, inherited and shared, never OCU.app; the -1743 fix path); filter is
     best-effort friction, not a boundary, and shell-capable hosts bypass it with Bash `osascript`; on an MCP-only
     host enabling it is equivalent to granting a shell; audit log path
     `~/Library/Application Support/OpenComputerUse/logs/scripts.log`, JSON lines, 0600, 10 MB cap + one rotated file,
     contains script text (may include email content); metadata-only stderr; timeouts (20s default, 60s max, 30s first
     contact) and that a killed script keeps running inside the target app; open_url blocked schemes and handlers;
     Shortcuts "Run Shell Script" warning; recommended permission setup (named-tool allow list so these three tools go
     through review, decision 16), and that only Claude Code's auto mode has such a classifier: Codex and Claude.app
     hosts run these tools with no review step. Also state: every script text is logged, including scripts the filter
     rejects and scripts refused while the Mac is locked; the logged `target_app` is the agent-declared `app` argument
     and is advisory (a script can `tell` a different app), and so is the first-contact timeout floor; the `open_url`
     policy is friction only (a script can `open location` or drive Finder); a script can show
     `display dialog ... default answer "" with hidden answer` and return what the user types to the agent, so treat
     unexpected password prompts as hostile; if the MCP host kills the relay mid-script, the osascript child is
     orphaned and runs to completion (the log then shows a request with no result); `get_scripting_dictionary` reads
     static `.sdef` files only and never launches the app.
  7. `docs/ARCHITECTURE.md` :3, :65, :68: macOS main line now has 10 Computer Use tools (the Go runtimes keep 9; say so
     explicitly where the sentence covers both). :12: the smoke runner covers the 10 tools plus the flag-on scripting
     smoke. :42: add the exception to "the process that actually calls ... is always `Open Computer Use.app`": with the
     scripting opt-in, `run_script` / `run_shortcut` run as an `osascript` / `shortcuts` child of the MCP server process
     and use the HOST app's Automation grant, never OCU.app's. :69: `open-computer-use call run_script` (and the other
     four local tools) is refused, because scripts run only in the MCP server process. Add one paragraph in the macOS
     runtime section: the relay-local channel router (`LocalChannelRouter`) intercepts local tools in the relay and
     direct mode, never in the agent; flag-gated; `find_elements` runs in the agent like other AX tools.
  8. `docs/SECURITY.md`: append a "Scripting channel (opt-in)" section summarising the threat model in five bullets and
     linking `skills/open-computer-use/references/scripting.md`.
  9. `README.md`, "Trust boundary (read before enabling)" paragraph (:50): append two sentences: the scripting opt-in
     (`OPEN_COMPUTER_USE_ENABLE_SCRIPTING=1`) is off by default; on an MCP-only host, enabling it is equivalent to
     granting that host a shell under its own Automation grants, and the shell-verb filter is not a security boundary.
     Link `skills/open-computer-use/references/scripting.md`. Do not edit `README.zh-CN.md`.
  10. New `docs/exec-plans/active/20260929-fast-macos-channels.md` from `docs/exec-plans/templates/execution-plan.md`
      (required for high-risk work, `docs/PLANS_GUIDE.md:5-9`; precedent
      `docs/exec-plans/active/20260922-local-decision-model-mcp-tool.md`): goal, scope, constraints, risks, verification,
      in English, with no local paths and no plan or finding ids.
  11. History entry via `scripts/new-history.sh fast-macos-channels`, filled in English, no secrets, no local paths.
- Verify:
  1. `cd "$WT" && swift test --filter 'LocalChannelGuidanceTests|OpenComputerUseKitTests|DecisionAdvisorTests' 2>&1 | tail -30`
     exits 0 and prints `with 0 failures`.
  2. `cd "$WT" && bash scripts/check-docs.sh` exits 0.
  3. `cd "$WT" && grep -c "find_elements" skills/open-computer-use/SKILL.md skills/open-computer-use/references/usage.md docs/ARCHITECTURE.md`
     prints a count >= 1 for each file.
  4. `cd "$WT" && grep -n "not a security boundary" skills/open-computer-use/references/scripting.md docs/SECURITY.md`
     prints at least one line per file.
  5. `cd "$WT" && ls docs/histories/2026-09/ | grep -c fast-macos-channels` prints `1`.
  6. `cd "$WT" && grep -c "run_script" README.md docs/ARCHITECTURE.md` prints >= 1 for each file, and
     `sed -n 40,46p docs/ARCHITECTURE.md | grep -c "osascript"` prints >= 1.
  7. `cd "$WT" && ls docs/exec-plans/active/ | grep -c fast-macos-channels` prints `1`.
  8. `cd "$WT" && grep -n "hidden answer\|advisory\|orphaned" skills/open-computer-use/references/scripting.md` prints at
     least three lines.
  9. `cd "$WT" && swift build && swift test 2>&1 | tail -15` exits 0 and prints `with 0 failures`.

## Signature

```swift
// K/MCPServer.swift (existing symbols; text-only change)
let baseComputerUseServerInstructions: String   // :3-18, now interpolates appleScriptAvoidanceInstructionLine at :16
func computerUseServerInstructions(environment: [String: String]) -> String   // unchanged (:25-30)
```

## Boundaries

```
TARGET:    K/MCPServer.swift (:10, :16, one line appended after :17), T/LocalChannelGuidanceTests.swift,
           skills/open-computer-use/SKILL.md, skills/open-computer-use/references/usage.md,
           skills/open-computer-use/references/scripting.md (new), docs/ARCHITECTURE.md, docs/SECURITY.md,
           README.md (Trust boundary paragraph only), docs/exec-plans/active/20260929-fast-macos-channels.md (new),
           docs/histories/2026-09/<timestamp>-fast-macos-channels.md (new)
READ-ONLY: K/LocalChannelGuidance.swift, K/LocalChannelToolHandlers.swift, K/ToolDefinitions.swift, plan-track-b/threat-model.md
FORBIDDEN: MCPServer.swift :8 and :14 (Track A); removing the AppleScript line unconditionally (amendment 2);
           dropping "Begin by calling get_app_state every turn" (Track A keeps it); any Go runtime docs change;
           app-target files (phase 06); README.zh-CN.md
```

## Acceptance

Command: `cd "$WT" && swift test --filter LocalChannelGuidanceTests`
Assertions (write first):
- `testBaseInstructionsNameFindElements`: `baseComputerUseServerInstructions` contains `find_elements` in the
  `The available tools are` sentence and contains `call \`find_elements\``.
- `testBaseInstructionsKeepAppleScriptLine`: contains `appleScriptAvoidanceInstructionLine` exactly once.
- `testScriptFirstGuideKeepsAskBeforeDestructive`: `scriptFirstInstructionGuide` contains `Ask the user before` and
  `not a security boundary` and `run_script`.
- `testScriptFirstGuideKeepsTurnStartStateForUIWork`: `scriptFirstInstructionGuide` contains `find_elements` and
  `turn-start`, so it does not contradict the retained "Begin by calling get_app_state every turn" line; it also
  contains the text "only uses `run_script`" (a script-only turn skips the turn-start read) and `after a script changed the UI`
  (names `find_elements` for that case).
- `testInstructionsWithoutAdvisorStayBase`: `computerUseServerInstructions(environment: [:]) == baseComputerUseServerInstructions`.
- Existing equality tests at `T/OpenComputerUseKitTests.swift:625`, `T/DecisionAdvisorTests.swift:476,507` stay green.

## Rollback

Revert the phase commit. Instructions return to the base text (with the AppleScript line, since it was never removed);
docs revert together.

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

## Main-loop amendment 2026-09-29 22:53 (outcome-lock decision 17, user-approved)
Measured: a full-inbox Mail `whose` search takes 20–66s, and the time is Mail's own. Replace the "Mail search via run_script ≤1s" target with a NARROW run_script on Mail (the selected message, or the newest N inbox messages), ≤1s median of 5 warm runs, run from Terminal.app and never cmux. Guidance and docs must say:
- Full-mailbox search goes through Mail's search field via find_elements plus perform_actions.
- Large `whose` queries stall Mail for 20–60s, which also blocks AX reads.
- cmux SIGTERMs app-targeting osascript children, so run_script fails when the host runs under cmux.

## Main-loop amendment 2026-09-30 (breadth-first find_elements walk, user-approved)
find_elements now reads the window breadth-first. Guidance that describes how to use it must say:
- Shallow window chrome (toolbar, sidebar, search field) is reached first, so a role plus label query for a toolbar
  control stops after a few levels.
- For deep content (a message row, a cell deep in a list), pass role plus label so the match is specific, or use
  get_app_state. Do not raise or tune max_nodes to reach deep content.
- No guidance, tool description or instructions text currently states a walk order, so no shipped text changed; the
  instructions keep their ≤1900-char budget.
