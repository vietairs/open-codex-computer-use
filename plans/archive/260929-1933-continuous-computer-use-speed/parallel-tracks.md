# Parallel tracks — isolation contract (2026-09-29 20:16, user: "set 2 dynamic workflows to not clash each other with main agents")

| | Track A — speed (PR A) | Track B — fast channels (PR B) |
|---|---|---|
| Outcome-lock decisions | 1–6, 11 | 7–10 |
| Worktree / branch | .claude/worktrees/continuous-computer-use-speed / feat/continuous-computer-use-speed | .claude/worktrees/fast-macos-channels / feat/fast-macos-channels |
| Report dir (only write target before cook) | reports/track-a/ | reports/track-b/ |
| Plan dir (stage 5) | plan-track-a/ | plan-track-b/ |
| Owns (edits) | ComputerUseService.swift action path + refreshSnapshot, AccessibilitySnapshot.swift capture + AX multi-attribute batch reads, SoftwareCursorOverlay/CursorMotionModel, DecisionJev*, new batch-action source, batch tests | new router / script-runner / sdef / find-elements / launcher sources + their tests; MacOSAppAgentProxy.swift, OpenComputerUseMain.swift, MCPAppRuntime.swift, MacSessionGuard.swift (router + sanitizer strip). No entitlements/Info.plist change (P2). |
| Shared files (append-only, own region) | ToolDefinitions.swift, ComputerUseToolDispatcher.swift, MCPServer.swift instructions, SKILL.md/usage.md, OpenComputerUseKitTests tool-count test | same. B rebases onto main after PR A merges and resolves these by hand |

Rules:
1. Each workflow writes only to its own worktree and report dir. It never touches pipeline*.md, outcome-lock.md, parallel-tracks.md, the other track's worktree, or the main checkout.
2. The main loop owns every gate: Artifact publish, the AskUserQuestion approvals, the pipeline-progress.md updates and ship-gate. It never edits files inside either worktree.
3. No live MCP / app-agent use inside workflows. Both bundles share one agent socket (memory `app-agent-socket-eviction-between-bundles`), so live Mail measurements run from the main loop, one track at a time.
4. Builds: each worktree uses its own `.build`. Never run `swift build`/`swift test` in the main checkout.
5. Each workflow runs one gate-to-gate segment and then returns. The --semi-auto hard stops return control to the main loop between segments.

Additions 2026-09-29 20:50 (after gate 3):
6. Medium-clash seam: Track B's find_elements cache-merge hook sits next to Track A's refreshSnapshot rewrite in ComputerUseService.swift. B adds its hook in a new extension file where possible and touches ComputerUseService.swift only to append. B's lean walker keeps its own private multi-attribute AX read in its own file; dedupe against A's helper happens during B's rebase, not before.
7. Both tracks' tool-count tests: A goes 9→10; B goes 10→11 after the rebase (the relay-local tools are listed by the router, not ToolDefinitions, unless the plan decides otherwise — the plan must state the count it expects).
8. Line MCPServer.swift:10 (tool list) and :16 (AppleScript line) are edited by both tracks; A edits :8/:10/:14 only, B edits :16 and appends; B resolves :10 by hand on rebase.
