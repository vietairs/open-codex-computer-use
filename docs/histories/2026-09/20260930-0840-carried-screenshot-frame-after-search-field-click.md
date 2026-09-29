## [2026-09-30 08:40] | Task: keep the returned screenshot frame after a text-only action result

### 🤖 Execution Context
* **Agent ID**: fullstack-developer
* **Base Model**: Claude Opus 5.5 (claude-opus-5-5)
* **Runtime**: Claude Code, worktree `feat/continuous-computer-use-speed`

### 📥 User Query
> Live on Mail (on stage, inactive, unchanged size): `get_app_state` with a screenshot, then an `element_index` click
> on the search field (text-only result), then an x/y click read from the first screenshot was refused with the
> "different window or window size" error. The x/y click must be accepted; resize, a different window, and off-stage
> windows must still fail closed.

### 🛠 Changes Overview
**Scope:** `packages/OpenComputerUseKit` (Sources + Tests).

**Key Actions:**
- **Cause**: focusing Mail's search field opens its search suggestions list, a separate small non-modal window
  (`AXDialog`, `AXModal = false`) in front of the viewer that overlaps it. Window selection let "a frontmost window
  that overlaps the chosen window" replace the accessibility root window, so the snapshot after the click targeted
  the suggestions window: a different window id and size than the screenshot the caller holds, which the carried
  frame rule correctly refused.
- **Fix**: `preferredWindowCaptureCandidate` skips windows that the app reports as non-modal accessibility windows
  when it looks for a covering window. Modal panels and windows whose modal flag cannot be read still win, so a new
  modal after a text-only result keeps failing closed. The modal flag is read lazily, only for windows in front of
  the chosen one.

### 🧠 Design Intent (Why)
The covering-window rule exists so a modal panel over the target is what the screenshot shows. A non-modal auxiliary
window covers a corner, is not part of the root window's accessibility tree, and should not change the coordinate
frame. Before the carried frame existed, the same selection silently mapped x/y into the suggestions window.

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/CarriedScreenshotFrameWindowSelectionTests.swift` (new)
