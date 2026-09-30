# Route card v2 addendum (2026-09-29 20:12) — scope expansion, see outcome-lock.md decisions 7–11

pipeline.md stays write-once as the v1 map. This addendum extends the route for PR B. PR A stages are unchanged.

```
ROUTE CARD v2 — add fast non-screenshot channels (run_script, sdef lookup, find_elements, Shortcuts/URL)
Complexity: hard → hard — second deliverable in the same plan
Risk: PR A medium; PR B HIGH — new code-execution surface (AppleScript `do shell script`), TCC Automation grants, confused-deputy precedent on the app-agent socket
Scope: multi-phase, two PRs from one plan
Change set (PR B, provisional): MCPServer.swift instructions (change), ToolDefinitions.swift (change), ComputerUseToolDispatcher.swift (change), new script-runner + sdef + find-elements sources (add), AccessibilitySnapshot.swift (change), skills/open-computer-use/SKILL.md + references (change); pending scout-260929-2010-fast-channels.md
Advice/Advise: unchanged (--counsel)
Added stages for PR B (R7 tail):
  3.  brainstorm covers both PRs (≥3 proposals each track)
  5b. red-team on PR B phases, one agent per angle — agent:code-reviewer ×3 (opus)
  10b. /ak-security (plain) on the PR B diff — agent:security-auditor
  11. /hvn:ship-gate --hard for PR B (--md for both)
  12–14 run once per PR (PR A first)
Merge: stops for you (both PRs)
```
