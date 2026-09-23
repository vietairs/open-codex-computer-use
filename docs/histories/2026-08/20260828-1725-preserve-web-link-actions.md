## [2026-08-28 17:25] | Task: Fix web link action-node parsing

### 🤖 Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex desktop`

### 📥 User Query
> Apply the fix: on the BOSS page, "Job Management" (职位管理) is parsed as a button with no independent link, so it can't be clicked to navigate.

### 🛠 Changes Overview
**Scope:** `OpenComputerUseKit` macOS Accessibility snapshot renderer

**Key Actions:**
- **[Preserve navigation semantics]**: a generic action node that contains an `AXLink` descendant with a URL is no longer promoted to a compact `button`, and its text summary is no longer merged.
- **[Keep generic button behavior]**: a compact `AXGroup` / `AXUnknown` with no URL-link descendant is still kept as an actionable `button` under the original rule.
- **[Added regression coverage]**: added a test for a compact action node with a link descendant, to prevent BOSS navigation links from being swallowed by the parent summary again.

### 🧠 Design Intent (Why)
Chrome/BOSS's Accessibility tree can expose both a generic parent action and a real URL-link child node at the same time. The parent action suits icon-only controls, but for a navigation link the child's independent `element_index` must be preserved — otherwise an AX click may only trigger the parent wrapper and never navigate to the URL.

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/ARCHITECTURE.md`
- `docs/histories/2026-08/20260828-1725-preserve-web-link-actions.md`
