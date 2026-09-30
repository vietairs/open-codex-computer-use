# PIPELINE COMPLETE

- [x] 1. worktree create — done 23:36 — `.claude/worktrees/sync-upstream-v0.3.5`
- [x] 2. merge v0.3.5 + resolve conflicts — done 23:38 — commit 8ce8cb0
- [x] 3. build + swift test + repo CI — done 23:39 — 221 tests pass
- [x] 4. version bump 0.3.6-vietairs.1 + notes + history — done 23:44 — commit 552a8e4
- [x] 5. PR opened — done 23:45 — vietairs/open-codex-computer-use#8
- [x] 6. pre-merge review fan-out — done 23:53 — both reviewers converged on one
      blocking finding (peer-env filter bypassed on the mcp path); fixed in
      d2c58ec, docs precision follow-up in the same branch. 223 tests pass.
      Reports: `reports/review-correctness.md`, `reports/review-security.md`
- [x] 7. merge + tag + release — done 00:00 — squash 8d0f4e7, tag
      v0.3.6-vietairs.1, release published with CursorMotion DMG asset
- [x] 8. rebuild + redeploy + restart runtime — done 00:01 — deployed app now
      reports 0.3.6-vietairs.1, accessibility and screen recording still
      granted, stale MCP process (old inode) stopped
- [x] 9. teardown — done 2026-09-22 — worktree removed; local `main` reset to
      origin/main (8d0f4e7); deferred Retina finding filed as
      vietairs/open-codex-computer-use#9

## Environment defect found mid-run

`python3` first on `PATH` (Python.framework 3.13) is SIGKILLed on any
invocation, including `python3 -V`. `/usr/bin/python3` and Homebrew's work.
This silently no-opped the repo's Linux Python regression during the first CI
pass — the `| tail` pipeline masked the killed exit status — and it killed the
app build script, which reads the package version through `python3`. Both were
re-run with `PATH=/usr/bin:$PATH`; the Linux suite genuinely passes (3 tests).

## Deferred, all confirmed pre-existing rather than merge-caused

- `firstAnyWindow` masks `recoverVisibleWindow` for hidden/minimized windows;
  off-screen windows then yield a nil capture and `screenshotPixelScale` falls
  back to 1:1, a 2x coordinate error on Retina. FILED as issue #9 (also covers
  the dead `AppScreenSession` guard and the stale `docs/SECURITY.md` claim).
- `AppScreenSession` and `ControlActivityStore.record*` are unreached.
- `AppAgentEnvironment.withOverrides` uses process-global `setenv`, so one
  client's global-pointer flag can leak into a concurrent client's click.
- `scripts/check-repo-hygiene.sh` fails on files upstream never tracked.
