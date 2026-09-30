## [2026-09-30 11:00] | Task: refuse a boolean click_count and keep auto clicks off window title-bar buttons

### 🤖 Execution Context
* **Agent ID**: fullstack-developer
* **Base Model**: Claude Opus 5.5 (claude-opus-5-5)
* **Runtime**: Claude Code, worktree `feat/continuous-computer-use-speed`

### 📥 User Query
> JSON `"click_count": true` must be refused, not read as 1. An `auto` click on a window must never press its close,
> minimize, zoom or full-screen button on the caller's behalf. Tighten the background-operation invariant test.

### 🛠 Changes Overview
**Scope:** `packages/OpenComputerUseKit` (Sources + Tests), `docs/ARCHITECTURE.md`, `docs/RELIABILITY.md`.

**Key Actions:**
- **Boolean click_count**: the shared whole-number check now rejects a CFBoolean before any numeric cast.
  `JSONSerialization` decodes JSON `true` as an `NSNumber` that `as? Int` bridges to 1, so the old order accepted it.
  The new tests decode their arguments from JSON text, the path real MCP and CLI input takes, for `true`, `false`,
  `"2"`, 0, 4, 1.5, 1e20 and 2^63 (refused) and 1, 2, 2.0, 3 (accepted), on the single call and a batch step.
- **Title-bar buttons**: when the target has no press action, `auto` presses its smallest pressable descendant.
  On a window those are the traffic-light buttons. Descendants whose subrole is `AXCloseButton`, `AXMinimizeButton`,
  `AXZoomButton` or `AXFullScreenButton` are now dropped from that candidate list by a pure filter. A direct click on
  such a button by its own `element_index` does not use the list and still works. The subrole is read only for
  actionable descendants.
- **Schema**: the `click_count` description states the 1 to 3 range. The Linux and Windows runtimes keep their
  text, because they do not enforce that range and no parity test pins it.
- **Invariant test**: write calls are now read up to their closing parenthesis, so an attribute on a later line
  still counts. The text-field focus write moved into a one-statement helper that is the only allowed default-path
  `AXFocused` write, with a count check. Writes of `AXMainWindow`, `AXFocusedWindow` and `AXFrontmost` fail the test
  outside the opt-in global-pointer path. Each check was confirmed to fail on a temporarily inserted violation.

### 🧠 Design Intent (Why)
A boolean slipping through only produced a single click, but the old test claimed otherwise because it passed a
Swift `Bool`, which never takes that path. Pressing a title-bar button closes or minimizes the user's window, a
destructive side effect of a click the caller aimed at the window as a whole.

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseToolDispatcher.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ClickTextEntryFocus.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ToolDefinitions.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/BackgroundOperationInvariantTests.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/BatchActionRunnerTests.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/WindowTitleBarButtonClickFilterTests.swift`
- `docs/ARCHITECTURE.md`
- `docs/RELIABILITY.md`
