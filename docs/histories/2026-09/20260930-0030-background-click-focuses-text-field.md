## [2026-09-30 00:30] | Task: let a click focus a text field in a background app

### 🤖 Execution Context
* **Agent ID**: fullstack-developer
* **Base Model**: Claude Opus 5.5 (claude-opus-5-5)
* **Runtime**: Claude Code, worktree `feat/continuous-computer-use-speed`

### 📥 User Query
> Background-only operation is a hard requirement. Clicking Mail's search field while Mail is inactive must let
> `type_text` type into it, and `set_value` must accept an empty string to clear a field.

### 🛠 Changes Overview
**Scope:** `packages/OpenComputerUseKit` (Sources + Tests), `skills/open-computer-use`, `docs/ARCHITECTURE.md`.

**Key Actions:**
- **Click focus write**: after a primary `click` by `element_index` (single call and `perform_actions` step) on a
  text-entry control whose `AXFocused` is settable, the service writes `AXFocused = true` on that element. The decision
  is a pure function in `ClickTextEntryFocus.swift` with the attribute reads and the write injected. A refused write
  is non-fatal.
- **`set_value ""`**: the `value` argument accepts an empty string in the single tool and in the batch step; an absent
  or non-string `value` is still rejected as missing.
- **Descriptions and guidance**: the macOS `click`, `set_value`, and `type_text` descriptions, the `type_text`
  no-focus error, `usage.md`, and `ARCHITECTURE.md` now say to click the field by `element_index` before `type_text`.
- **Invariant test**: the click focus path contains no activation, raise, or window-server call.

### 🧠 Design Intent (Why)
A click delivered to an inactive app, as an accessibility press or pid-posted mouse events, does not change its first
responder, and neither does a pid-posted shortcut such as `cmd+option+f`. So `type_text` correctly failed closed and
a background search could not run. Writing `AXFocused` on the clicked field was verified live to make it the app's
focused element while the app stays inactive and the user's frontmost app is unchanged. Right and middle clicks are
left alone because they mean a context menu, not a caret.

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ClickTextEntryFocus.swift` (new)
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseToolDispatcher.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ToolDefinitions.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/TypeTextDelivery.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/ClickTextEntryFocusTests.swift` (new)
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/BackgroundOperationInvariantTests.swift`
- `skills/open-computer-use/references/usage.md`
- `docs/ARCHITECTURE.md`
