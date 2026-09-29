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
