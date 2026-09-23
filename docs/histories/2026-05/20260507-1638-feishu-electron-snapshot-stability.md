## [2026-05-07 16:38] | Task: Stabilize Feishu Electron snapshots

### Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5`
* **Runtime**: `macOS local CLI/MCP`

### User Query
> Compare whether `computer-use` and `open-computer-use` operate Feishu correctly; focus on verifying sending a message to xuyusong and investigating `open-computer-use`'s intermittent UI tree / screenshot instability, verifying first, then fixing, then verifying again.

### Changes Overview
**Scope:** macOS snapshot rendering in `OpenComputerUseKit`

**Key Actions:**
- **[Electron AX tree]**: Increased the AX traversal depth budget and compressed empty generic wrappers so Feishu/Electron WebView content can expose chat messages and the entry area within the existing 500 node cap.
- **[AX noise filtering]**: Stopped treating empty strings, `selected=false`, `expanded=false`, and `AXScrollToVisible` as meaningful output, reducing tree noise and making action-critical nodes visible sooner.
- **[Screenshot timeout]**: Added a ScreenCaptureKit capture timeout so screenshot stalls omit the image block instead of blocking the full app state call.
- **[Smoke reliability]**: Made the smoke suite disable the app-agent proxy for `.build/debug/OpenComputerUse mcp`, so local smoke verifies the just-built server and visual cursor observation file.
- **[Verification]**: Compared official `computer-use` and fixed local `open-computer-use` against `com.electron.lark`; both sent test messages to xuyusong after the fix.

### Design Intent (Why)
Feishu is an Electron app, and its WebView exposes a much deeper and noisier AX tree than native AppKit controls. The old renderer stopped at depth 16 and preserved empty wrapper nodes, so the screenshot could be present while the useful UI tree missed the chat input. The fix keeps the global 500-node safety cap but spends that budget on semantic nodes.

### Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `docs/ARCHITECTURE.md`
- `docs/RELIABILITY.md`
- `docs/exec-plans/completed/20260507-feishu-electron-snapshot-stability.md`
