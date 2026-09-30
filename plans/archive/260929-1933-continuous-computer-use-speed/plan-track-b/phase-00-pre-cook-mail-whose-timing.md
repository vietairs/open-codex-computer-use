# Phase 00: pre-cook check, time a warm Mail `whose` search (main loop)

Owner: **main loop only** (not a workflow agent; parallel-tracks rule 3). No code, no worktree edits.
Depends on: nothing. Blocks: phases 01, 02, 05 (cook start).

## Why

Acceptance "Mail search via `run_script` returns results in <=1s" is bounded by Mail's own `whose` evaluation, which is
unmeasured. osascript spawn costs 0.04-0.17s (brainstorm probe). If Mail alone takes more than ~0.8s warm, the target
is Mail-bound and the script text or mailbox must be pinned before cook, not discovered after (counsel check 3).

## Constraint

Claude Code's Bash sandbox blocks Apple Events (osascript to another app fails with -600/-1743/-10822). Do not retry
with the sandbox disabled. The **user** runs the commands in Terminal.app and pastes the output back.

## Task 0.1: user runs the timing in Terminal.app

- Goal: six timings of each pinned script, first run cold, runs 2-6 warm.
- Target files and symbols: none.
- Steps (give the user this exact block to paste into Terminal.app; Mail must be open on the inbox):

  ```zsh
  S1='tell application "Mail" to count (messages of inbox whose subject contains "combio")'
  S2='tell application "Mail" to get subject of (messages of inbox whose subject contains "combio")'
  for s in "$S1" "$S2"; do
    echo "== $s"
    for i in 1 2 3 4 5 6; do
      /usr/bin/time -p /usr/bin/osascript -e "$s" 2>&1 | grep -E '^real|^[0-9]|combio' | tr '\n' ' '; echo
    done
  done
  ```
- Success criteria: 12 `real` values captured; first call may show the Automation prompt (Terminal -> Mail), approve it.
- Verify: the pasted output contains exactly 12 lines starting with or containing `real`.

## Task 0.2: main loop records and decides

- Goal: a go / pin decision recorded before cook.
- Steps:
  1. Compute the median of runs 2-6 for S2 (the pinned `run_script` text used again in phase 10).
  2. Record raw numbers and the median in `reports/track-b/precook-mail-whose-timing.md` (main loop writes it).
  3. Decide:
     - median <= 0.8s: go; phase 10 uses S2 verbatim.
     - 0.8s < median <= 1.0s: go, flag the margin in the report; phase 10 still uses S2.
     - median > 1.0s: the target is Mail-bound. Ask the user (AskUserQuestion) to pin a narrower script (one
       mailbox, e.g. `messages of mailbox "INBOX" of account "<name>"`) or accept the Mail-bound number. Record the
       pinned text; phase 10 uses it.
- Verify: the report file exists and contains `median_warm_s=` and one of `decision=go`, `decision=go-flagged`,
  `decision=pinned`.

## Rollback

Nothing to roll back (read-only measurement).

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
