# FUS-via-SSH gate — verification attempt & finding

Task: close the last open PR #5 checkbox — the fast-user-switch-away (FUS) invariant the lock-detection fix rests on.

## Invariant under test
`parseSnapshot` infers unlocked from an absent `CGSSessionScreenIsLocked` key **only** when
`kCGSSessionOnConsoleKey == true`. The fix is safe iff a genuine session-not-owning-console
(FUS-away or second account) actually reports `onConsole == false`, so the guard fails closed
(`isLocked=true`) there. A same-user screen lock keeps `onConsole == true` and therefore does NOT
exercise this branch.

## What automation confirmed
- Built a live poller (mirrors `parseSnapshot` classification) and sampled the real system 416×
  over ~3 min while the same user was active. Every sample: `onConsole=true lockKey=ABSENT ->
  unlocked (inferred on-console)`. Matches the fix's expected same-user-active behavior exactly and
  reproduces the original bug's root cause (lock key genuinely absent on this OS).
- Attempted to trigger FUS-away programmatically to drive the off-console branch:
  `SACSwitchToLoginWindow` (login.framework) resolves but returns **EINVAL (22)** for every
  signature tried (no-arg, `Int32` 0/1, nil pointer). The FUS switch cannot be invoked from a
  background / non-GUI process.

## Finding: the box is genuinely human-only (now empirically grounded)
The EINVAL from a headless context is the same condition the checkbox describes: FUS-away requires
a human at the physical machine (or a real loginwindow/GUI context), and specifically an SSH/tmux
session that stays open across the switch. It cannot be automated from this background job — which
is precisely why the PR marks it human-only. This is not a fix gap; it is an OS constraint on who
can flip the console owner.

Theoretical grounding for confidence: `kCGSSessionOnConsoleKey` is, by CGSession definition, "does
this session own the console." FUS-away hands the console to another session, so the departed
session's value is definitionally `false` → `parseSnapshot` returns `isLocked=true` (fail-closed).
The off-console branch is also already unit-tested.

## Human recipe to close the box (unchanged, ~1 min)
From an SSH/tmux session that will survive the switch:
1. `OPEN_COMPUTER_USE_LIVE_PROBE=1 swift test --filter testLiveSystemProbePrintsRealLockState`
   once while on-console (sanity: prints `isLocked=false`).
2. At the physical Mac, fast-user-switch away (or open a second account's login window), leaving the
   SSH session running.
3. Re-run the same command from the still-open SSH session. Expect `isLocked=true`.

## Merge status
Nothing else blocks merge: suite green (192/1 skipped), all independent reviews PASS/clean, ship-gate
PASS. This one box is the sole remaining item and is human-only by OS constraint.
