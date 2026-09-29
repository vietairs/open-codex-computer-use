## [2026-09-29 23:48] | Task: stop Computer Use from taking focus from the user's frontmost app

### 🤖 Execution Context
* **Agent ID**: fullstack-developer
* **Base Model**: Claude Opus 5.5 (claude-opus-5-5)
* **Runtime**: Claude Code, worktree `feat/continuous-computer-use-speed`

### 📥 User Query
> Open Computer Use should control and screenshot the app in the background and should not take the focus while I'm
> working in another tab or app.

### 🛠 Changes Overview
**Scope:** `packages/OpenComputerUseKit` (Sources + Tests), `skills/open-computer-use`, `docs/ARCHITECTURE.md`,
`docs/RELIABILITY.md`.

**Key Actions:**
- **Background focus signal**: `AXFocused` joins the batched per-node attribute read. When the app-level
  `AXFocusedUIElement` is nil (a background app), the deepest rendered control reporting `AXFocused` (never a window
  or other container) becomes the snapshot's focused element and focus line. A `perform_actions` step re-reads
  `AXFocused` live on the pinned focus and the pinned text-entry elements.
- **`type_text` never activates**: the activate, type, re-activate branch is gone from the single call and the batch
  step. A settable focus gets the accessibility value write, a non-settable text control gets keys posted to the
  process, and anything else fails with an error asking the agent to focus the field or use `set_value`.
- **Launch and window recovery**: launching a non-running app sets `activates = false`; snapshot window recovery only
  unhides a hidden app and otherwise fails with the official no-window error plus a sentence saying why.
- **Invariant test**: `BackgroundOperationInvariantTests` allows `.activate(` only inside the gated global-pointer
  preparation, and forbids `/usr/bin/open` in the kit.

### 🧠 Design Intent (Why)
A background target reported no focus, so `type_text` activated it for at least 80 ms. Keys the user typed in that
window went to the target, and window order changed on restore. Window recovery and app launch could also bring the
target to the front. Background operation is a hard product requirement, so every default path now either works
without activation or fails with an actionable error. The opt-in paths (global pointer fallbacks, `sky_click`, an
explicit Raise action) are unchanged.

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilityAttributePrefetch.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AppDiscovery.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/BackgroundFocusResolution.swift` (new)
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/Errors.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ToolDefinitions.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/TypeTextDelivery.swift` (new)
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/`: `BackgroundFocusResolutionTests.swift`,
  `BackgroundOperationInvariantTests.swift`, `TypeTextDeliveryTests.swift` (new); `AXAttributePrefetchTests.swift`
  (updated)
- `skills/open-computer-use/references/usage.md`
- `docs/ARCHITECTURE.md`
- `docs/RELIABILITY.md`
