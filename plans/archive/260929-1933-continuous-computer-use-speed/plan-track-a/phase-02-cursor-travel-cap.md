# Phase 02: Cursor travel capped at 0.3s (lever L2)

- **Depends on:** phase 00, whose baseline must exist first.
- **Blocks:** none. Phase 08 measures it.
- **Parallel-safe with:** 01, 03, 04, 05 and 06. It touches only the overlay file and its own new test file.
- **Roles:** Tester ≠ Implementer.
- **Effort:** 1h.
- **Commit (exactly one):** `perf(cursor): cap visual cursor travel at 0.3s`
- Paths: `W`, `S` and `T` are as defined in phase 01.

## Context (verified at afb60fa)

- `animateMove` (`S/SoftwareCursorOverlay.swift:348-392`) blocks the action for its whole duration, because it runs through `performOnMain` → `DispatchQueue.main.sync` (`:19`).
- Its duration is `OfficialCursorMotionModel.calibratedTravelDuration(...)` (`:354-357`). That value is always `closeEnoughTime` (`S/CursorMotionModel.swift:493-494`), which is 1.4291667s and is pinned by the test at `T/OpenComputerUseKitTests.swift:2639`.
- The spring is time-scaled: `springTime = normalizedElapsed * springTargetDuration` (`:365-367`). Shortening `duration` therefore compresses the motion without changing its path shape.
- Both `click` and `set_value` pay this cost through `moveVisualCursor`.
- Decision 12, advisor correction 5: the cap lives in `SoftwareCursorOverlay.animateMove` only. `CursorMotionModel.swift` and its tests stay byte-identical, and exactly one new cap test is added.

## Signature

`S/SoftwareCursorOverlay.swift` (file scope, internal):
```swift
/// Upper bound on the blocking cursor travel before a click or set_value. The recovered official timing (1.43s) is
/// kept in CursorMotionModel for parity; only the overlay's wall-clock duration is capped.
let visualCursorTravelDurationCap: CGFloat = 0.3
func visualCursorTravelDuration(calibrated: CGFloat, cap: CGFloat = visualCursorTravelDurationCap) -> CGFloat
// returns min(calibrated, cap); a non-positive or non-finite calibrated value is returned unchanged (today's max(duration, 0.001) guard in animateMove still applies)
```

In `animateMove` (`:354`), the local becomes:
```swift
let duration = visualCursorTravelDuration(calibrated: OfficialCursorMotionModel.calibratedTravelDuration(distance: ..., measurement: ...))
```
`springTargetDuration` stays `OfficialCursorMotionModel.closeEnoughTime`.

## Boundaries

```
TARGET:    S/SoftwareCursorOverlay.swift (the two file-scope items above + the one `duration` line in animateMove)
           T/CursorTravelCapTests.swift (new; Tester only)
READ-ONLY: S/CursorMotionModel.swift, T/OpenComputerUseKitTests.swift (:2639, :2643-2660 must keep passing unchanged)
FORBIDDEN: any byte of S/CursorMotionModel.swift; editing tests :2639/:2643-2660; the click pulse (0.16s, :555);
           making travel non-blocking (counsel: rejected option b); an env override knob (not requested);
           every file owned by phases 01, 03-07
```

## Tasks

### Task 2.1: Failing test first (Tester)
- Goal: `T/CursorTravelCapTests.swift` (class `CursorTravelCapTests`).
- Verify (expected RED): `swift test --filter OpenComputerUseKitTests.CursorTravelCapTests 2>&1 | tail -30` exits non-zero, and the output contains `cannot find 'visualCursorTravelDuration' in scope`.

### Task 2.2: Implement (Implementer)
- Steps: add the two items, then change the single `duration` line in `animateMove`.
- Verify: `swift test --filter OpenComputerUseKitTests.CursorTravelCapTests 2>&1 | tail -30` exits 0 and contains `with 0 failures`.

### Task 2.3: Regression and commit (Implementer)
- Verify, all three:
  - `swift test 2>&1 | tail -15` exits 0 and contains `with 0 failures`.
  - `git diff --stat afb60fa -- $S/CursorMotionModel.swift` prints nothing.
  - `git diff afb60fa -- $S/SoftwareCursorOverlay.swift | grep -c '^[-+][^-+]'` prints a number ≤ 12, which is the small, local diff expected.
- Then commit with the exact subject above and report the SHA.

## Acceptance

Command: `cd $W && swift test --filter OpenComputerUseKitTests.CursorTravelCapTests`

Assertions (write first; must fail before, pass after):
- `visualCursorTravelDuration(calibrated: OfficialCursorMotionModel.closeEnoughTime)` equals 0.3, within 1e-9.
- `visualCursorTravelDuration(calibrated: 0.2)` equals 0.2.
- `visualCursorTravelDuration(calibrated: 5, cap: 0.5)` equals 0.5.
- `visualCursorTravelDurationCap < OfficialCursorMotionModel.closeEnoughTime`. This guards against a cap that silently does nothing.
- Unchanged and still green: `testOfficialCursorMotionSpringCloseEnoughTimeMatchesRecoveredReference` and `testOfficialCursorMotionTravelDurationUsesRecoveredEndpointLockTiming`.

## Lever measurement M2 (main loop)

Run `MEASURE(C2, <SHA>, extras: cycle --cursor off)` against C1.
- Expected with cursor **on**: the click and set_value medians drop by about 1.1s each. press_key and type_text stay within ±5%.
- Control with cursor **off**: every tool stays within ±5% of C1 with cursor off. This proves the delta is the cursor alone.
- Visual check by the main loop: one click on Mail with cursor on shows the arc and pulse, and the pulse still lands on the target.

## Risks

| Risk | L×I | Mitigation |
|---|---|---|
| A 0.3s travel looks abrupt. The UX change is user-visible. | M×L | Accepted in decision 12 ("cursor travel capped ~0.3s"). The spring shape is preserved. |
| The `isCloseEnough` early break fires differently when time-compressed | L×L | The existing loop already normalizes by `duration`. The visual check above covers it. |

## Rollback

`git revert <C2>`. It is independent of every other phase.

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
