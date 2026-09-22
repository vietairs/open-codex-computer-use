# Ledger — 260718-1008-upstream-v020-merge-lockscreen

Task: Sync the fork with upstream v0.1.51 → v0.2.0, merge all locally developed
features, and settle whether agents can keep working while the macOS screen is locked.

PR: vietairs/open-codex-computer-use#2 — merged 2026-07-18 as `e5c9bb5`.

## What shipped

- Three-way merge (local main + origin/main + upstream/main) landed with zero textual
  conflicts; one *semantic* conflict surfaced only at build time —
  `WindowCaptureCandidate.isOnscreen` missing from 4 test constructors.
- Lock-screen verdict: the merged upstream code **blocks while locked** (fail-closed).
  That default was kept.
- New opt-in `MacSessionLockPolicy` gated on `OPEN_COMPUTER_USE_ALLOW_LOCKED=1`, giving
  best-effort AX control while locked for unattended agents. Default behavior unchanged.
- 172 tests green at ship; docs updated across README / ARCHITECTURE / RELIABILITY / SECURITY.

## Deviations

- Stage 2 (parallel analysis fan-out, 3 agents) was never run — the merge turned out to
  be conflict-free, so the analysis it would have fed was unnecessary. Its checkbox is
  still unchecked in `pipeline-progress.md`; the `# PIPELINE COMPLETE` marker is
  authoritative and supersedes it.
- Adversarial review found one CONFIRMED high-severity issue — an app-agent
  confused-deputy on the unauthenticated same-uid socket — fixed in `4b15ac0` before
  merge. That thread continued into PR #3 (socket peer authentication by code signature).
- The pipeline deliberately stopped at a draft PR rather than merging; the merge was
  left as the maintainer's call.

## Learnings

- A conflict-free textual merge says nothing about semantic compatibility — the only
  thing that caught the broken test constructors was actually building.
- "Absent lock key" is not the same as "unlocked"; the corroboration work that followed
  became PR #5.

Archived-at-SHA: 6b35619fce1469086edfbf377b30877125a107c1
