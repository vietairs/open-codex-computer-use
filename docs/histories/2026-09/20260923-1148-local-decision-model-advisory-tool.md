## [2026-09-23 11:48] | Task: Ship the local decision-model advisory MCP tool (workstream D)

### 🤖 Execution Context
* **Agent ID**: docs-manager subagent (phase 07a); phases 01-06 by separate implementer/tester subagents on the same branch
* **Base Model**: Claude Sonnet 5
* **Runtime**: macOS, `.claude/worktrees/decision-model` (branch `feat/decision-model`)

### 📥 User Query
> Build `decide_next_action`, an opt-in, read-only MCP advisory tool: prune the accessibility tree into an
> actionable candidate table, run a constrained-choice readout against a local llama-server sidecar, and return the
> chosen operation/target with full probability distributions. Measure the design's P1-P3 gates with a local eval
> set and report the results honestly, whether they pass or fail.

### 🛠 Changes Overview
**Scope:** `packages/OpenComputerUseKit` (Swift advisory pipeline), `scripts/decision-model/` (sidecar + eval
tooling, Node), `experiments/DecisionModelEval` (dev-only eval harness), `skills/open-computer-use/` (cascade guide
doc), `docs/exec-plans/active/20260922-local-decision-model-mcp-tool.md` (English translation + measured gates).

**Key Actions:**
- **Candidate pruning and labeling**: pruned the rendered accessibility text into an actionable candidate table,
  paged to <= 52 rows, labeled A-Z/a-z.
- **Readout client**: a loopback-only `llama-server` client that reads pre-sampling logprobs for two sequential
  heads (operation, then target) in one `/completion` call per page, with special-token scrubbing on all
  screen-derived text.
- **Tool wiring**: `decide_next_action` is listed by `tools/list` only when `OPEN_COMPUTER_USE_DECISION_MODEL_URL`
  is set to a loopback URL; it never actuates.
- **Eval**: built a 254-item local eval set (27 fixture, 227 real; 175 dev / 79 test) and a Node-driven eval runner
  against the shipped Swift pipeline. Gate results (test split): top-1 accuracy 0.443 (threshold >= 0.80, **FAIL**);
  margin AUROC 0.8286 (threshold >= 0.70, **PASS**); correct-target-pruned rate 0.0938 (threshold <= 0.05, **FAIL**);
  p50 latency 509 ms (threshold < 1500 ms, **PASS**, optimistic bound on Apple M4 Max 48 GB). `recommended_min_margin`
  (tau) set to 0.72 from the eval (dev precision 0.90 at 0.1714 coverage).
- **Docs (this task)**: translated the exec plan to English with the measured-gates table and updated decisions;
  wrote this history note; added `skills/open-computer-use/references/decision-model.md` (setup, cascade guide,
  result fields, measured quality, security notes) and linked it from `SKILL.md`.

### 🧠 Design Intent (Why)
The tool stays strictly advisory so open-computer-use keeps its identity as an MCP tool server rather than gaining a
second, server-side planning loop (rejected: `run_goal`; deferred: bounded delegated execution). Failed gates are
reported rather than hidden or silently patched, per the accepted decision to build P1-P3 even with an open P0 gate:
a host can still use the tool profitably above the measured margin threshold, and the failure modes (wrong
operation/target, pruned targets) are documented so hosts know when not to trust it.

### 📁 Files Modified
- `docs/exec-plans/active/20260922-local-decision-model-mcp-tool.md`
- `docs/histories/2026-09/20260923-1148-local-decision-model-advisory-tool.md`
- `skills/open-computer-use/references/decision-model.md`
- `skills/open-computer-use/SKILL.md`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/DecisionCandidates.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/DecisionPrompt.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/DecisionModelClient.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/DecisionAdvice.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/DecisionAdvisor.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ToolDefinitions.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseToolDispatcher.swift`
- `scripts/decision-model/` (model manifest, sidecar scripts, eval dataset/runner/metrics)
- `experiments/DecisionModelEval/`
