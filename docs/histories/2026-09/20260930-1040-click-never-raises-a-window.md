## [2026-09-30 10:40] | Task: remove the window raise from the default click path

### 🤖 Execution Context
* **Agent ID**: fullstack-developer
* **Base Model**: Claude Opus 5.5 (claude-opus-5-5)
* **Runtime**: Claude Code, worktree `feat/continuous-computer-use-speed`

### 📥 User Query
> The server works in the background only: no activation, no raise, no unminimize of the target app or its windows on
> any path. A click on a window element must never reorder windows.

### 🛠 Changes Overview
**Scope:** `packages/OpenComputerUseKit` (Sources + Tests), `docs/ARCHITECTURE.md`, `docs/RELIABILITY.md`,
`skills/open-computer-use/references/usage.md`.

**Key Actions:**
- **Click without raise**: the element click sequence no longer ends in a window fallback that performed `AXRaise` and
  wrote `AXMain` / `AXFocused` on an `AXWindow` target. When no press-style action handles the target, `auto` falls
  through to the existing pid-posted mouse events, and `click_method=accessibility` fails with its existing error.
- **Invariant test**: `BackgroundOperationInvariantTests` now also fails when the raise action or the main-window
  attribute is named, or `AXFocused` is written, anywhere in the kit outside the opt-in global-pointer preparation,
  the read-only click ranking and the text-field click focus write.
- **click_count**: a single click and a batch click step share one validator that accepts a whole number from 1 to 3
  and returns an argument error otherwise, instead of trapping on a huge or non-finite value. The shared whole-number
  check no longer traps at exactly 2^63.
- **Batch focus probe**: the probe that finds a background app's focused field for a batch `type_text` now uses the
  same role, subrole and role-description test as `type_text` itself, so a secure field or a web text area that a
  single call accepts is also found in a batch. Element records keep the subrole and role description for this.
- **Skill example**: the Mail `perform_actions` example clicks the search field by index instead of posting
  `cmd+option+f`, which never moves focus in a background app, and runs inside one `--calls` array after
  `get_app_state` so the index has state behind it.

### 🧠 Design Intent (Why)
`AXRaise` on a window reorders it above the user's windows without activating the app, which is exactly the intrusion
the background-only rule forbids. It was reachable only when no child press handled a click on a window element, so
removing it costs little: the click still reaches the window through pid-posted events.

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseToolDispatcher.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/BackgroundFocusResolution.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ClickTextEntryFocus.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/BackgroundOperationInvariantTests.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/BackgroundFocusResolutionTests.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/BatchActionRunnerTests.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/ARCHITECTURE.md`
- `docs/RELIABILITY.md`
- `skills/open-computer-use/references/usage.md`
