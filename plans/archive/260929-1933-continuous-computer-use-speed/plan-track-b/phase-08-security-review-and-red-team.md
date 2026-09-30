# Phase 08: security review and red-team (PR B risk = high)

Depends on: phases 06 and 07. Blocks: 09. Effort 2.5h (24 threat rows).
Owner: a **reviewer** agent (code-reviewer tier, opus/fable) that implemented none of phases 01-07, plus a 4-persona
red-team pass (Assumptions, Failure, Scope, Security). Reviewers do not edit code; fixes go back to an implementer as a
new task under the owning phase's Boundaries.

## Execution constants

- `WT=/Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/fast-macos-channels`; read-only in the worktree.
- Reports go to `/Users/hvnguyen/Projects/open-codex-computer-use/plans/260929-1933-continuous-computer-use-speed/reports/track-b/`:
  `review-<yymmdd-hhmm>-pr-b-security.md` and `red-team-<yymmdd-hhmm>-pr-b.md`.
- No live MCP, no app agent, no osascript against other apps.

## Task 8.1: review against the threat model

- Goal: every row T1-T25 of `threat-model.md` (this directory) is traced to code and to a passing test (T24 is a
  documented residual: trace the docs instead).
- Steps:
  1. `cd "$WT" && git diff afb60fa --stat` and read the full diff.
  2. For each threat row, cite the control's `file:line` and the test name; mark `verified`, `gap`, or `wrong`.
  3. Check specifically: router passthrough when disabled does no parsing; no local tool name appears in
     `ToolDefinitions` or the dispatcher; `sanitizePeerEnvironment` strips the flag; `posix_spawn` uses
     `POSIX_SPAWN_CLOEXEC_DEFAULT` and dup2's only 0-2; `F_SETNOSIGPIPE` on the stdin pipe; process-group kill;
     audit open flags include `O_NOFOLLOW` and mode 0600 and the file write precedes the child spawn; the `.request`
     entry for run_script / open_url / run_shortcut is written before the lock guard, argument validation and the
     filter, and a filter rejection writes a `rejected:filter` result; the audit writer re-checks dev/ino after
     `flock`; stderr lines carry no payload and no raw control characters; `XMLDocument` is never given a URL and
     `.documentXInclude` is never set; definition files are opened `O_NOFOLLOW|O_NONBLOCK` and `fstat`-checked;
     include count, expanded-bytes and xpointer-shape limits exist; no `OSACopyScriptingDefinitionFromURL`; include
     path check uses `realpath` + trailing `/`; `open_url` rejects before calling the opener and the opener receives
     the checked handler URL; shortcut names starting with `-` rejected; the runner's drain is bounded after the
     leader exits and only one thread reaps; the child's cwd is `/`; `find_elements` rows escape AX text; hit
     allocator is process-global, monotonic and seeded per process; merge checks window id AND bounds; hits-only
     snapshots carry focus; agent launch environment unchanged.
  4. Run `cd "$WT" && swift build && swift test 2>&1 | tail -15` and record the result line.
- Success criteria: report lists all 25 rows with a status; every `gap`/`wrong` has severity (Critical/High/Medium/Low)
  and a concrete fix naming the owning phase.
- Verify: the report file exists and contains `T1` through `T25`, and `Executed` with `0 failures`.

## Task 8.2: red-team

- Goal: adversarial pass with the four personas; at minimum try, on paper against the code: filter bypass forms beyond
  the list (document, do not demand fixes: decision 8 says best-effort); a JSON-RPC line with a local tool name inside
  a batch; a `tools/call` whose `params.name` differs only in case (`Run_Script`) -> must be forwarded and refused by
  the agent, not run; an sdef include through a symlinked directory; `open_url` with `%`-encoded scheme tricks;
  `find_elements` stale index after `get_app_state` with `max_tree_nodes` 2_000_000; relay killed mid-script (audit
  request line exists, no result line); an AX title carrying a newline plus a fake `[<index>]` row; an sdef with 100
  includes, a hostile xpointer, or a FIFO named `*.sdef`; two relays rotating the audit log at once; a
  `sleep 30 &` descendant holding the output pipes; `open_url` with `smb:`, `vnc:`, `help:` or an automation-app
  handler.
- Verify: the red-team report exists and ends with a table `finding | severity | disposition`.

## Gate

- Pass condition: zero open Critical or High findings across both reports. Medium findings either fixed or accepted by
  the main loop with a one-line rationale in the report.
- Fix loop: each Critical/High becomes an implementer task under the owning phase (its Boundaries apply), with a failing
  test first; then re-run Task 8.1 step 4 and update the report status.

## Rollback

Nothing to roll back (read-only). If a finding cannot be fixed inside decision 7-10/14-16, STOP and hand it to the main
loop; do not redesign.

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
