## [2026-07-16 15:48] | Task: Preserve anonymous web icon-only action buttons

### 🤖 Execution Context
* **Agent ID**: `/root`
* **Base Model**: GPT-5
* **Runtime**: Codex desktop

### 📥 User Query
> Fix the issue where a row of icon-only buttons with tooltips on a Chrome page doesn't show up in the snapshot, and so can't be clicked via `element_index`.

### 🛠 Changes Overview
**Scope:** `OpenComputerUseKit` macOS Accessibility snapshot renderer

**Key Actions:**
- **[Preserve primary clickable nodes]**: Anonymous `AXGroup` / `AXUnknown` nodes that expose `AXPress`, `AXConfirm`, or `AXOpen` are no longer cut just because the primary action was hidden from the text output.
- **[Limit noise]**: Only anonymous action nodes with a valid, compact frame are kept; zero-size nodes and generic click containers covering a large page area continue to be filtered out.
- **[Actionable output]**: These icon-only controls are now rendered as a `button` with a window-relative `Frame`, giving each control a distinguishable `element_index`.
- **[Verification]**: Added tests for primary click-action recognition, anonymous button detection, and size boundaries, and confirmed on a real Chrome page that the row of icon buttons on the right now shows up in the snapshot.

### 🧠 Design Intent (Why)
Web pages often implement buttons with textless iconfont or SVG containers. Chrome may only expose a generic AX role, frame, and primary action for such nodes; the old renderer would hide the implicit primary action like `AXPress` first, then cut the node as a meaningless wrapper. The fix preserves compact clickable nodes without restoring every empty wrapper, letting the agent operate them via frame and `element_index`.

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/ARCHITECTURE.md`
- `docs/histories/2026-07/20260716-1548-preserve-anonymous-web-actions.md`
