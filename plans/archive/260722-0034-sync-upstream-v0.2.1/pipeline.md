# Pipeline — sync upstream v0.2.1

Task: catch fork up with upstream iFurySt/open-codex-computer-use latest release (v0.2.1), keep all fork features
Task source: free text (/hvn:cortex --semi-auto)
Timestamp: 2026-07-22 00:34 AEST

Classification:
- Risk: low — upstream ahead by 1 commit (460d281, version bump 0.2.1 only); PR #45 fix already in merge-base c8a7758
- Familiarity: high — prior v0.2.0 merge (486c79d) done in this fork
- Scope: small — 10 files upstream, 1 overlapping file (OpenComputerUseKitTests.swift)
- Payoff: medium — fork version/tag/npm alignment with upstream release line

Route (semi-auto):
1. worktree + branch (worktree-sync-upstream-v0.2.1)
2. merge v0.2.1 into branch; resolve overlap: upstream version strings win, fork test additions kept
3. build/test verification (swift test where feasible)
4. push + draft PR --repo vietairs/open-codex-computer-use
5. HARD STOP — before-merge approval (semi-auto gate)

Skips: blindspot/predict/plan/brainstorm/red-team — version-bump merge, no unknowns. Security-scan n/a (no HIGH keywords).
