# Ledger — agent crash / MCP disconnect (2026-10-15)

Task: find why the open-computer-use MCP server disconnects in other Claude sessions; fix it (--auto).
Archived with `--force-review`: the progress file carries no `# PIPELINE COMPLETE` marker, because
open item 6 (upstream scout verdicts) was never recorded.

Shipped:
- PR #29 (b0762ca): non-finite-safe rendering in the shared app agent (root cause: `Int(Double)` trap
  on NaN/inf AX frame in `CGRect.renderedLocalFrame`); MCP proxy survives agent loss; sticky Quit;
  lock opt-in off on relaunch.
- PR #30 (0.3.11-vietairs.1), tag at f61ebb8.
- PR #31–#37 (0.3.12-vietairs.1); PR #43 (0.3.12-vietairs.2, tag on e6140b9, GitHub release 2026-10-16).
- PR #44 (0483ecf): this plan record.
- Mac: `@vietairs/open-computer-use@0.3.12-vietairs.2` installed globally; shared agent restarted.

Deviations / learnings:
- The NaN source app and element are still unidentified.
- Old agent (pre-fix) was stopped by SIGTERM on 2026-10-16 and relaunched from the new install.
- npm publish needs the user's Terminal (passkey 2FA); prerelease publishes need `--tag latest`.

Open (carried, not in this plan):
- Upstream scout verdicts (not recorded here).
- Follow-ups: concurrent-relaunch flock; dev/release bundles evicting each other's agent; proxyMCP
  reconnect e2e test; non-MCP CLI relaunch while quit marker set; NaN source app.
  Listed in `plans/reports/checkpoint-261016-sky-key-port-plan.md`.

Recovery: `git checkout 0483ecf -- plans/archive/261015-1131-agent-crash-mcp-disconnect ":(exclude)plans/archive/261015-1131-agent-crash-mcp-disconnect/ledger.md"`

Archived-at-SHA: 0483ecf656d4bea4597719a5dfd9a4465ef4fb43
