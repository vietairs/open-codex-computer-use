# Pipeline — notarize, translate, decision model, publish

Task: Continue the fork's latest plan with four workstreams: (A) notarize the macOS app for
local and CI builds, (B) translate the remaining Chinese docs to English, (C) publish the
`@vietairs/*` npm packages now that npm is logged in, (D) implement the SemIf / jev-ultrafast-style
local classifier (P1 eval, P2 readout prototype, P3 `decide_next_action`) from
`docs/exec-plans/active/20260922-local-decision-model-mcp-tool.md`.
Task source: free text via /hvn:cortex --auto --counsel
Timestamp: 2026-09-23 09:39 AEST
Base: main @ 4ac1d5e (v0.3.7-vietairs.1 tagged; npm publish failed ENEEDAUTH in CI run 35751040227)

ROUTE CARD — notarize + translate + publish + local decision model
Complexity: hard -> hard — four independent workstreams. The evidence pass found two external
  blockers and a privacy constraint: no notarytool credentials exist on this machine, so a
  notarized build is not possible yet; and real-app snapshots contain personal data (6 probes, ~10:00)
Risk: medium overall. A = medium (release build path). B = low (docs only, no behavior change).
  C = medium (outward-facing and irreversible, since an npm version can never be reused).
  D = medium (a new MCP tool and a loopback HTTP client; read-only and advisory; no actuation
  and no trust-boundary change). Conservative bias applied to D: not low.
Familiarity: high — same lineage; the proposal (rev 4) and exec plan already exist, and P0 shipped in PR #10
Scope: multi-phase — four disjoint workstreams, clean file ownership, one PR each (A, B, D)
Payoff: high — fork users still have no install path (npm never published); agents pay full
  frontier-model cost per UI step; AGENTS.md and 250+ docs are Chinese for an English-only maintainer
Change set: ~270 files —
  A: scripts/build-open-computer-use-app.sh (change), scripts/npm/build-packages.mjs (change),
     .github/workflows/release.yml (change), docs/releases/RELEASE_GUIDE.md (change)
  B: 255 tracked .md files incl. AGENTS.md, CLAUDE.md, CONTRIBUTING.md, docs/** (change);
     README.zh-CN.md and plans/** excluded
  D: packages/OpenComputerUseKit/Sources/** (add/change), Tests (add), scripts/decision-model/** (add),
     docs/exec-plans/active/20260922-local-decision-model-mcp-tool.md (change), skill prompt (add)
  (via scout fan-out + direct probes)
Advice: /ak-plan (D) — handover plan + per-phase Failure Protocol; red checks in cook escalate
  to kongming (fable/max, uncapped by design) (via --counsel)
Advise: 2 gates — plan-validation direction (D), before-merge (A, D) via kongming (--auto) (via --counsel)
Review loop: up to 3 rounds pre-merge per PR, then a docs sweep over docs/ + README.md
Merge: B = AUTO-MERGE if all four conditions hold (--auto + risk low + ship-gate PASS + checks
  green + loop converged clean). A and D stop for you (medium risk). C runs only after A merges
  and notary credentials exist.

Route:
  0. ak-goal-warmup (auto-locked) — main-loop
  1. Evidence scouts — Explore (haiku) + main-loop probes — DONE
  2. Worktrees x3 (/ak-worktree) — git-manager
  3A. Notarization implementation — fullstack-developer (sonnet)
  3B. Docs translation fan-out (~12 units) — general-purpose (sonnet)
  3D-i. /ak-plan --tdd --advice (P1-P3) — planner (opus)
  3D-ii. Plan validation (direction auto-logged, kongming counsel) — main-loop
  3D-iii. /ak-cook P1 eval + P2 readout + P3 tool — fullstack-developer (sonnet), tester != implementer
  4. Verify: swift build/test, make ci, check-docs — tester (sonnet)
  5. /ak-code-review per PR (correctness / security / docs lenses) — code-reviewer (opus)
  6. /hvn:ship-gate per PR — main-loop (attestation auto-logged)
  7. /ak-ship per PR + pre-merge review loop + docs sweep — git-manager / code-reviewer
  8. Merge B (auto, if eligible); A and D handed over
  9. Publish C: local notarized build + npm publish — main-loop (blocked on notary credentials + A merged)
 10. Terminal session-report + teardown

Skips: /hvn:blindspot — the scouts plus the rev-4 proposal already mapped D's unknowns.
  /ak-brainstorm — D's design was approved in proposal rev 4 (decisions locked); A, B and C have no
  design fork. /ak-predict on B — a docs-only change has no behavior to predict.
  Linux/Windows Go runtimes for D — macOS-only for P3, as the exec plan's non-goals and runtime section allow.
