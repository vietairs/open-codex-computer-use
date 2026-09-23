## [2026-07-30 14:31] | Task: Preserve action boundaries within generic nodes

### 🤖 Execution Context
* **Agent ID**: `/root`
* **Base Model**: GPT-5
* **Runtime**: Codex desktop

### 📥 User Query
> Fix an issue where the snapshot of the BOSS Zhipin (BOSS 直聘) forward dialog in Chrome merges "Forward to Colleague" (站内同事), "Forward to Other" (转发至其他), and "Forward via Email" (邮件转发) into a single container, so the targets don't get their own `element_index`.

### 🛠 Changes Overview
**Scope:** `OpenComputerUseKit` macOS Accessibility snapshot renderer

**Key Actions:**
- **[Preserve action boundaries]**: The generic text-container summary now stops merging when it encounters an `AXGroup` / `AXUnknown` child node carrying `AXPress`, `AXConfirm`, or `AXOpen`, preventing the parent summary from swallowing clickable descendants.
- **[Output actionable buttons]**: Generic primary-action nodes with a valid, compact frame are now rendered as `button`, allowing short-text descendants to become button summaries directly.
- **[Keep tree size in check]**: Plain text-only containers still use the existing summary compression; zero-size and large-area generic action containers are still not mislabeled as compact buttons.
- **[Verification]**: Added tests for action-summary boundaries and compact action nodes; the full `swift test` run passed 3 StandaloneCursor tests and 151 OpenComputerUseKit tests (1 explicit live test skipped, 0 failures), and a current local build confirmed the three options each got their own button and frame in a real Chrome dialog.

### 🧠 Design Intent (Why)
Chrome's web accessibility tree exposes text options as generic nodes carrying a primary click action, with static text placed underneath. The old summary logic only checked descendant roles, not the actions on generic child nodes, so it would cross real interaction boundaries and merge multiple options into one container that couldn't be operated on precisely. This fix only blocks the summary from crossing generic primary-action nodes; it doesn't disable plain text compression otherwise, balancing interaction semantics against the node budget.

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/ARCHITECTURE.md`
- `docs/histories/2026-07/20260730-1431-preserve-generic-action-boundaries.md`
