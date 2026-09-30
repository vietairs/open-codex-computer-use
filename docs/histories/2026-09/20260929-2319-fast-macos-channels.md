## [2026-09-29 23:19] | Task: Add fast non-screenshot channels for the macOS runtime

### 🤖 Execution Context
* **Agent ID**: implementer subagent on branch `feat/fast-macos-channels`
* **Base Model**: Claude Sonnet 5.5
* **Runtime**: macOS, dedicated git worktree

### 📥 User Query
> Cut the per-step cost of continuous computer use on macOS by adding channels that avoid a full screenshot and
> tree render: a lean element search and an opt-in scripting channel (AppleScript/JXA, URLs, Shortcuts), without
> giving the MCP server a planner.

### 🛠 Changes Overview
**Scope:** `packages/OpenComputerUseKit` (server instruction text), `skills/open-computer-use/`, `docs/`, `README.md`.

**Key Actions:**
- **Server instructions**: the base instructions list `find_elements` in the tool sentence and tell hosts when to call
  it; the AppleScript line is now interpolated from one shared constant so the relay's swap stays an exact match.
- **Guidance tests**: pin that the base text names `find_elements`, keeps the AppleScript line exactly once, and that
  the script-first guide keeps the ask-before-destructive rule and the turn-start `get_app_state` rule for UI work.
- **Skill docs**: `SKILL.md` and `usage.md` document `find_elements`; new `references/scripting.md` covers enabling,
  the five local tools, the TCC model, the audit log, timeouts and the residual risks.
- **Architecture and security docs**: tool counts (10 on macOS, 9 in the Go runtimes), the scripting exception to the
  "always `Open Computer Use.app`" rule, the relay-local router, a "Scripting channel (opt-in)" security section and a
  README trust-boundary note.

### 🧠 Design Intent (Why)
Screenshots and full-tree reads dominate step latency. A targeted element search and a scripted path for
scriptable apps remove most of that cost, while keeping the scripting channel off by default and documenting plainly
that its filter is friction and not a security boundary.

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MCPServer.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/LocalChannelGuidanceTests.swift`
- `skills/open-computer-use/SKILL.md`
- `skills/open-computer-use/references/usage.md`
- `skills/open-computer-use/references/scripting.md`
- `docs/ARCHITECTURE.md`
- `docs/SECURITY.md`
- `README.md`
- `docs/exec-plans/active/20260929-fast-macos-channels.md`

## [2026-09-30 14:42] | Round: rebase onto the action-latency work

### 🛠 Changes Overview
- **find_elements window and merge**: the search resolves its window the way a full snapshot does (an off-stage
  Stage Manager window by its own id and accessibility frame, otherwise the window-server entry of the AX window's
  own id, with non-modal overlays ignored), reads each node through the shared single-round-trip prefetch, and merges
  hits only into a cached snapshot in the same stage state, carrying the off-stage flag that gates pointer input.
- **One snapshot cache writer**: `refreshSnapshot` and `find_elements` both store through `storeSnapshot`.
- **Server instructions**: the base text leads with `perform_actions`, `find_elements` and the load-together hint,
  drops tool behavior that each tool's own description already states, and fits the 2048-character host limit again.
  The script-first guide is tightened the same way; every rule is kept. The advisory tool's cascade guide moved
  from the instructions into `decide_next_action`'s own description, so the host-visible instructions stay under
  1900 characters in every configuration (1331 without scripting, 1795 with it).

### 🧠 Design Intent (Why)
A merged snapshot must describe the same window, in the same place and stage state, as the snapshot it joins;
otherwise an index would resolve against the wrong frame or skip the off-stage guard. Hosts cut server instructions
at 2048 characters, so the newest tools' guidance has to come first and the text has to stay short.

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ElementSearchAccessibilitySource.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ElementSearchSnapshotMerge.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MCPServer.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/LocalChannelGuidance.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/DecisionAdvisor.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ToolDefinitions.swift`
- `docs/ARCHITECTURE.md`
- `skills/open-computer-use/references/decision-model.md`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/DecisionAdvisorTests.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/ElementSearchTests.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/LocalChannelGuidanceTests.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/ServerInstructionsGuidanceTests.swift`
