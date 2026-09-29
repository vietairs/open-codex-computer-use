## [2026-09-30 01:00] | Task: explain and handle Stage Manager off-stage windows

### 🤖 Execution Context
* **Agent ID**: fullstack-developer
* **Base Model**: Claude Opus 5.5 (claude-opus-5-5)
* **Runtime**: Claude Code, worktree `feat/continuous-computer-use-speed`

### 📥 User Query
> Off-stage (Stage Manager strip) windows: return the full AX tree plus a clear note that the window is off stage and
> has no screenshot; element_index actions keep working; x/y clicks on such a window fail with a clear error. Never
> switch stages, activate, or move the cursor.

### 🛠 Changes Overview
**Scope:** `packages/OpenComputerUseKit` (Sources + Tests), `skills/open-computer-use`, `docs/ARCHITECTURE.md`.

**Key Actions:**
- **Detection**: `StageManagerOffStageWindow.swift` (new) compares the window-server frame of the AX window's own id
  with its AX frame. Below an area ratio of 0.5 the window is off stage; a minimized window, or a window the window
  server does not list, is not. The decision is a pure function with the frame reads injected.
- **Snapshot**: an off-stage window uses its AX frame as the window bounds and skips every capture, including the
  empty-tree screenshot fallback of action results. The state text of `get_app_state`, action results, and the
  `perform_actions` final state carries one note line after the `Window:` line.
- **x/y input**: an x/y `click`, `drag`, and every pointer-event fallback (scroll events, non-AX click fallback,
  explicit click methods) fail with a clear error on an off-stage window instead of posting events. An `element_index`
  click skips the software cursor, which would point at empty space.
- **Batch geometry**: a `perform_actions` step on an off-stage window keeps the pinned AX frame as the window bounds,
  because the live window-server frame is the thumbnail.
- **Invariant tests**: the detection file contains no activation, raise, stage, SkyLight, or pointer call, and each
  pointer-event path refuses an off-stage window first.

### 🧠 Design Intent (Why)
Under Stage Manager the off-stage window is the same window, but the window server reports it as a ~115x129 strip
thumbnail while AX reports the full frame. Every capture API returns only the thumbnail, and no non-disruptive way to
bring the window on stage was found. Before this change `get_app_state` matched no window by size and silently
returned text only, so an agent could not tell why. Accessibility actions were verified to work off stage, so the
server keeps them and explains the missing screenshot instead of changing what the user sees.

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/StageManagerOffStageWindow.swift` (new)
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/StageManagerOffStageWindowTests.swift` (new)
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/BackgroundOperationInvariantTests.swift`
- `skills/open-computer-use/SKILL.md`
- `skills/open-computer-use/references/usage.md`
- `docs/ARCHITECTURE.md`
