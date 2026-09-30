# Phase 03: One post-action settle constant (lever L3)

- **Depends on:** phase 01. Both phases edit `ComputerUseService.swift`, so this one runs after it.
- **Blocks:** phase 05, whose batch inter-step settle uses this constant.
- **Parallel-safe with:** 02, 04 and 06.
- **Roles:** Tester ≠ Implementer.
- **Effort:** 0.5h.
- **Commit (exactly one):** C3: `refactor(actions): name the post-action settle interval` (no behaviour change).
- **User decision (2026-09-29):** the 0.1s trim (formerly C3b) is dropped. It was expected to move `M_server` by about 0 (the only real-app site is `performSecondaryAction`), while it shortens the one value the batch needs to be long enough. This is a recorded trade-off against decision 5's "trim where safe", not a breach of the outcome lock.
- **Pre-authorized raise (user decision):** if the live batch check fails because steps outrun the app (phase 05 M5 or phase 08 L2 `batch`), the main loop may raise `postActionSettleInterval` to **at most 0.3s** without escalation. See "Pre-authorized settle raise" below.
- Paths: `W`, `S` and `T` are as defined in phase 01.

## Context (verified at afb60fa)

`S/ComputerUseService.swift` holds 0.15s sleeps with two different meanings. Line numbers are at afb60fa; phase 01 shifts them, so find the sites by the function they sit in.

- **Post-action settles**, 7 sites, which get the constant:
  - `click` fixture branch `:642`
  - `performSecondaryAction` `:807`, the only real-app site
  - `scroll` fixture `:828`
  - `drag` fixture `:858`
  - `typeText` fixture `:880`
  - `pressKey` fixture `:909`
  - `setValue` fixture `:929`
- **Click-success detection gates**, which stay as literals because trimming them risks false "not handled" results and double clicks (predict §ComputerUseService):
  - `performAXClickSequence` `:1140, :1147, :1154, :1169, :1184, :1205`
  - `selectContainingListItem` `:1095`
- The other literals (0.1 after an AX set, 0.08 after activation, 0.05 in fallback loops) and `S/InputSimulation.swift` stay untouched. They are out of Track A's owned surface.

Expected effect on the Mail combio mix: close to zero. No real-app path in that mix hits these sites. The constant matters as the batch inter-step settle in phase 05. The lever is therefore measured on the fixture smoke timing and on the batch live check. It is not expected to move `M_server`.

## Signature

```swift
// S/ComputerUseService.swift, file scope, internal
/// Settle time after an action before its result is read, and between steps of a perform_actions batch.
let postActionSettleInterval: TimeInterval = 0.15   // C3; may later be raised to at most 0.3 (pre-authorized raise below)
```

## Boundaries

```
TARGET:    S/ComputerUseService.swift (the constant + the 7 post-action sites above, nothing else)
           T/PostActionSettleTests.swift (new; Tester only)
READ-ONLY: S/InputSimulation.swift
FORBIDDEN: the 7 detection-gate literals (performAXClickSequence, selectContainingListItem); the 0.1/0.08/0.05 literals;
           S/InputSimulation.swift; files owned by phases 01, 02, 04-07; Track B files
```

## Tasks

### Task 3.1: Failing test first (Tester)
- Create `T/PostActionSettleTests.swift` (class `PostActionSettleTests`) with `XCTAssertEqual(postActionSettleInterval, 0.15, accuracy: 1e-9)`.
- Verify (RED): `swift test --filter OpenComputerUseKitTests.PostActionSettleTests 2>&1 | tail -20` exits non-zero and contains `cannot find 'postActionSettleInterval' in scope`.

### Task 3.2: Introduce the constant, C3 (Implementer)
- Steps: add the constant, then replace the 7 post-action literals with `Thread.sleep(forTimeInterval: postActionSettleInterval)`.
- Verify, all of:
  - `grep -c 'Thread.sleep(forTimeInterval: postActionSettleInterval)' $S/ComputerUseService.swift` prints `7`.
  - `grep -c 'Thread.sleep(forTimeInterval: 0.15)' $S/ComputerUseService.swift` prints `7` (the 7 gates).
  - `swift test 2>&1 | tail -15` exits 0 and contains `with 0 failures`.
- Commit C3 and report the SHA.

## Acceptance

Command: `cd $W && swift test --filter OpenComputerUseKitTests.PostActionSettleTests`

Assertions (write first):
- The constant equals 0.15 at C3 (and equals the raised value after a pre-authorized raise, if one lands).
- The mechanical grep counts in Task 3.2 hold.

## Lever measurement M3 (main loop)

C3 is a behaviour-neutral refactor, so M3 is a no-regression check, not a lever delta. Run `MEASURE(C3, <SHA>)` against C2 (cursor on) and record the per-tool deltas; `M_server(C3)` must be within +2% of C2. Record "settle: named, not trimmed (user decision)" in the M1–M4 lever table. The constant's real job is the batch inter-step settle, which phase 05 M5 checks live.

## Pre-authorized settle raise (main loop; only on a failed live batch check)

Trigger: phase 05 M5 or phase 08 L2 `batch` aborts because a step outran Mail (the probe round or `require_search_value` fails, or a step reports a focus or element error), with the scene verified correct (phase 00 B-5).

1. In the Track A worktree, after phase 05 has landed: Tester sets the expected value in `PostActionSettleTests` to the new value (RED), and Implementer sets `postActionSettleInterval` to it (GREEN). Try `0.2` first, then `0.3`. **Never above 0.3.**
2. Verify: the filtered test exits 0, and `swift test 2>&1 | tail -15` exits 0 and contains `with 0 failures`. The Task 3.2 grep counts still hold (7 constant uses, 7 gate literals at 0.15).
3. Commit: `fix(actions): lengthen the post-action settle interval`. If 0.2 still fails the live check, a second commit with the same subject sets 0.3; do not amend.
4. Re-run the failed live check. Record the value, the SHA, and the `M_server` delta (the raise also lengthens the 7 single-action settle sites: 6 fixture-only branches plus `performSecondaryAction`).
5. If the check still fails at 0.3s, stop and use the Failure Protocol. The class is "wrong domain rule": a fixed settle is not what makes Mail accept the next step.

## Risks

| Risk | L×I | Mitigation |
|---|---|---|
| 0.15s is too short for the batch inter-step settle on Mail (predict: "high") | M×H | The trim is dropped; the pre-authorized raise (≤ 0.3s) runs on a failed M5/L2 batch check. The constant is shared by design (decision 12: "one settle constant"). |
| Someone trims the gates | L×H | FORBIDDEN list plus the grep count of 7 gate literals |

## Rollback

`git revert <C3>` removes the constant and restores the literals, but only if phase 05 has not landed (phase 05 uses the constant). A pre-authorized raise reverts on its own with `git revert <raise SHA>`, which returns the value to 0.15.

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
