# Pipeline

Task: Make computer-use action loops feel continuous. Today a Mail step costs ~9s (agent think ~4s + permission review ~1.3s + server ~3.5s) and jev `decide_next_action` times out, so JEV speed never reaches the user.
Task source: free text (user, 2026-09-29 19:33): "there maybe something wrong in the pipeline or in the how agents should use this mcp, as I feel it still slow, main agent still think then do call the mcp to move mouse to do action with my mac. with JEV speed, we should have the speed like actions continuosly. so improve it --semi-auto --counsel"
Created: 2026-09-29 19:45 AEST

```
ROUTE CARD — speed up the computer-use action loop (server latency, batching, agent guidance, jev cold start)
Complexity: hard → hard — evidence confirms three independent cost centres plus a locked scope constraint (6 probes, ~08:00)
Risk: medium — new public MCP tool contract and agent-guidance change; no auth/schema; a decide_and_act lease would be HIGH and is gated behind the outcome lock
Familiarity: high — repo shipped decide_next_action, remote jev backend and compact snapshots in the last 10 days (PRs #13, #18, #21)
Scope: multi-phase — Kit service + tool definitions + MCP instructions/skill docs + jev client; clean file ownership per phase
Payoff: high — the user drives their Mac through this server daily and reports it as too slow (Mail run: 18 steps ≈ 3 minutes)
Change set: ~7 files — ComputerUseService.swift (change), ToolDefinitions.swift (change), ComputerUseToolDispatcher.swift (change), MCPServer.swift instructions (change), DecisionJevClient.swift (change), skills/open-computer-use/SKILL.md + references (change), new batch-action source (add) (via scouts + transcript timing)
Effort: verify-critical — high per executor role; Agent-path: inherits the session effort
Advice: /ak-plan — handover plan + per-phase Failure Protocol; red checks in /ak-cook, /ak-test escalate to kongming (opus/max, uncapped by design) (via --counsel)
Advise: 4 gates — brainstorm approval, plan direction confirm, ship-gate attestation, before-merge approval via advisor (~4 extra opus-tier spawns) (via --counsel)
Review loop: up to 3 rounds pre-merge (review -> fix -> verify -> re-review), then a docs sweep over all of docs/ + README.md — findings land as commits on this PR, not a follow-up PR
Merge: stops for you
Route:
  0. ak-goal-warmup outcome lock — main-loop (irreducible: interview)
  1. /ak-worktree create .claude/worktrees/continuous-computer-use-speed — agent:git-manager
  2. /hvn:blindspot — agent:hvn-scout fan-out, synthesis main-loop
  3. /ak-brainstorm --html → /ak-preview --html (≥3 proposals) — agent:brainstormer + hvn:content-builder; approval main-loop (added vs R5: several viable designs remain)
  4. /ak-predict --files <change set> — agent:general-purpose; report saved to reports/
  5. /ak-plan --tdd --advice (+ task-contract-extension) — agent:planner (opus, high)
  6. /ak-plan validate + direction confirm — main-loop (irreducible: confirm)
  7. /hvn:impl-notes init — agent:hvn-scout
  8. /ak-cook --auto --parallel — agent:fullstack-developer per phase (sonnet)
  9. /hvn:impl-notes review — main-loop (irreducible: distillation)
  10. /ak-code-review — agent:code-reviewer (opus, high)
  11. /hvn:ship-gate --md — main-loop (irreducible: attestation)
  12. /ak-ship (no --merge, skip CHANGELOG step) — agent:git-manager
  13. /ak-review-pr --fix --reply loop (≤3 rounds) + /ak-docs sweep — agent:code-reviewer ×3 lenses + fullstack-developer
  14. before-merge approval + PR report-back comment — main-loop
  15. post-merge: git pull --ff-only, worktree teardown (local only), /hvn:plan-gc archive — agent:git-manager
Skips: red-team — medium risk; /ak-orchestrate arbiter — not R7
```
