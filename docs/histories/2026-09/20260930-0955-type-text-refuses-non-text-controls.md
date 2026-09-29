## [2026-09-30 09:55] | Task: make type_text refuse settable non-text controls

### 🤖 Execution Context
* **Agent ID**: fullstack-developer
* **Base Model**: Claude Opus 5.5 (claude-opus-5-5)
* **Runtime**: Claude Code, worktree `feat/continuous-computer-use-speed`

### 📥 User Query
> type_text must fail closed: never post keystrokes when the focused element is not a text-entry control, and never
> activate the app. A settable non-text focus (slider, list) currently gets a value write and, when that is refused,
> posted keys.

### 🛠 Changes Overview
**Scope:** `packages/OpenComputerUseKit` (Sources + Tests), `docs/RELIABILITY.md`.

**Key Actions:**
- **Text-entry decision**: `canUseKeyboardTextFallback` now judges role, subrole and role description only. It reuses
  the click-focus text-entry classification (text field, text area, text view, combo box, secure field, search and
  secure subroles) plus the existing "text field" / "text area" / "text entry" role-description match for web text
  entry. Value settability is no longer a signal.
- **Route gate**: `typeTextRoute` refuses any focus that is not text entry before the value write, so a slider or list
  receives neither a write nor keys. A text field is unchanged: value write, then keys if the write is refused.
- **Testable seam**: `makeTypeTextFocus` builds the focus from the element's attributes; the service calls it, and the
  tests drive it with real role inputs instead of a hand-built focus that production could never produce.

### 🧠 Design Intent (Why)
The old "refused write on a non-text element fails closed" branch was unreachable, because any settable value counted
as accepting keyboard text. Keys posted to such an app reach its first responder, where type-select can move a list
selection. Deciding from the role closes that path while keeping every genuine text field on its existing route.

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/TypeTextDelivery.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/TypeTextDeliveryTests.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/RELIABILITY.md`
