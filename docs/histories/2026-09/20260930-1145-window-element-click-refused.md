## [2026-09-30 11:45] | Task: refuse window-element clicks and stop `auto` from pressing hidden close-tab buttons

### 🤖 Execution Context
* **Agent ID**: fullstack-developer
* **Base Model**: Claude Sonnet 5.5 (claude-sonnet-5-5)
* **Runtime**: Claude Code, worktree `feat/continuous-computer-use-speed`

### 📥 User Query
> `click` on Mail's window element with `click_method` `auto` closed Mail's only window and then reported "no visible
> window". Refuse window-role element clicks, make the post-click no-window error honest, and keep the descendant
> press away from hidden close-tab buttons.

### 🛠 Changes Overview
**Scope:** `packages/OpenComputerUseKit` (Sources + Tests), `docs/RELIABILITY.md`.

**Key Actions:**
- **Root cause (proven live with the input-fallback debug log)**: Mail's window exposes only `AXRaise`, so `auto`
  fell to the descendant press and pressed an 18x18 button at the top left, Mail's hidden tab-bar "Close tab" button.
  That closed the only window. The refresh after the action then failed with the no-window error, whose text implied
  nothing had happened.
- **Window refusal**: an `element_index` click whose element role is `AXWindow` now throws `invalidArguments` right
  after the element lookup, before the visual cursor moves and before any press or posted event, when the method is
  `auto` or `accessibility`. Single clicks and `perform_actions` steps share that path. `app_post`, `sky_click`,
  `global` and x/y clicks are unchanged.
- **Honest error**: the refresh at the end of an action rewrites the no-window error to say the action was
  performed and the window could not be read afterwards (closed, re-tabbed, or off stage), and to call
  `get_app_state`. It stays a thrown error, and every other refresh error passes through unchanged. The messages
  raised before an action are untouched.
- **Descendant filter**: a second pure filter runs after the title-bar filter in the shared candidate list, so the
  hit-record descendant scan gets it too. It drops tab close buttons (identifier `_closeButton` or description
  `Close tab`) and candidates whose frame has zero width or height or does not intersect the target's frame. Labels
  are read only for actionable candidates.

### 🧠 Design Intent (Why)
A click aimed at a window as a whole has no safe meaning without raising or selecting it, which this project never
does, so refusing it is cheaper and clearer than guessing a control inside. Hidden controls stay in the AX tree, so
the press search must not treat them as visible targets. A failure that follows a delivered action must not read as
if nothing happened.

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/Errors.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/WindowElementClickRefusalTests.swift`
- `docs/RELIABILITY.md`
