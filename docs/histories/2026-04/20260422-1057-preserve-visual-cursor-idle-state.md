## [2026-04-22 10:57] | Task: Keep the visual cursor's idle state between interactions

### Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5.4`
* **Runtime**: `Codex CLI on macOS + SwiftPM`

### User Query
> Reverse-engineer how the official `.app` manages the overlay cursor's visibility; currently, locally, the cursor disappears between `click` / `set_value` and keeps re-starting from the bottom-left `(0,0)`, while officially it idles at its current position and continues moving from there on the next action.

### Changes Overview
**Scope:** `OpenComputerUseKit` visual cursor runtime, reverse-engineering docs, architecture docs

**Key Actions:**
- **[Re-review of official lifecycle]**: re-reviewed the Swift metadata for the bundled `computer-use` `1.0.755`, confirming that `ComputerUseCursor.Window.currentInterpolatedOrigin` and `wantsToBeVisible` / `shouldFadeOut` are separate states.
- **[Cross-check against runtime logs]**: re-reviewed the official service's cursor movement via the unified log, confirming that the same cursor window is reused across multiple movements, and is only torn down by the service's idle timeout about 5 minutes after the last movement.
- **[Fix the local idle lifecycle]**: `SoftwareCursorOverlay` no longer clears its state 0.5 seconds after `click` / `set_value` finishes; instead it now stays idle for about 5 minutes, letting subsequent tool calls continue from the currently visible tip.
- **[Add tests and docs]**: added a regression test for the idle timeout constant, and synced `ARCHITECTURE.md` and the reverse-engineering docs.

### Design Intent
The official `(0,0)` starting point is the semantics of a fresh service / fresh cursor window, not the semantics of the end of every action. Changing the local short-delay hide into a longer idle cleanup preserves the `displayedTipPosition` / visual dynamics state within the current process, avoiding a repeated snap back to the bottom-left corner across consecutive tool calls.

### Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SoftwareCursorOverlay.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/npm/build-packages.mjs`
- `docs/ARCHITECTURE.md`
- `docs/references/codex-computer-use-reverse-engineering/software-cursor-overlay.md`
- `docs/histories/2026-04/20260422-1057-preserve-visual-cursor-idle-state.md`

### Follow-up (2026-04-22, turn-ended cleanup)

- **[Confirmed gap]**: re-review confirmed that the local `open-computer-use turn-ended` is just a standalone CLI process printing a confirmation; it doesn't affect a running MCP overlay. This doesn't satisfy "the cursor disappears when the task ends."
- **[MCP internal hook]**: `StdioMCPServer` now has a `notifications/turn-ended`, which, once received, immediately resets the visual cursor in the current process.
- **[Codex notify compatibility]**: the CLI `turn-ended` now accepts the after-agent payload appended by the Codex legacy notify, and notifies the running AppKit MCP process to clean up the cursor via a macOS distributed notification; `MCPAppRuntime` now listens for this notification.
- **[Sync tests and docs]**: added regression tests for CLI payload parsing and MCP notification, and updated the architecture and reverse-engineering docs.

**Follow-up Files:**
- `apps/OpenComputerUse/Sources/OpenComputerUse/MCPAppRuntime.swift`
- `apps/OpenComputerUse/Sources/OpenComputerUse/OpenComputerUseMain.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MCPServer.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseCLI.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SoftwareCursorOverlay.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/ARCHITECTURE.md`
- `docs/references/codex-computer-use-reverse-engineering/software-cursor-overlay.md`
