## [2026-04-17 18:16] | Task: Align computer-use tool schema and result payloads

### 🤖 Execution Context
* **Agent ID**: `primary`
* **Base Model**: `gpt-5`
* **Runtime**: `Codex CLI + SwiftPM`

### 📥 User Query
> Based on the official `computer-use` / `open-computer-use` dumps captured earlier, optimize both sides' MCP call parameters and returns for parity. Explicit requirements include:
> 1. Screenshots after an action should not be written to disk, but returned directly as BASE64.
> 2. Tool descriptions and parameters must strictly align with the official ones.
> Continue optimizing other differences based on the actual dumps.

### 🛠 Changes Overview
**Scope:** `packages/OpenComputerUseKit`, `apps/OpenComputerUse`, `apps/OpenComputerUseSmokeSuite`, `docs`

**Key Actions:**
- **[Schema alignment]**: Converged the description and input schema copy of the 9 tools onto the surface the current official `computer-use` exposes to the model.
- **[Result payload alignment]**: Added a new MCP tool result content wrapper so `get_app_state` and action-type tools return `text + image/png(base64)`, instead of stuffing plain app screenshot paths into the text.
- **[State text tightening]**: Removed the open-source implementation's own `Screenshot:` path and `<element_index>` extra block, bringing the state text closer to the official `computer-use`'s `App=/Window=/tree` structure.
- **[Error semantics adjustment]**: Common official recoverable results such as `appNotFound("...")` are now returned as plain tool text instead of always being treated as an MCP error.
- **[Smoke stability]**: Fixed a non-atomic write race in the fixture state file, and had the smoke suite proactively clean up stale fixture processes and stale state files before startup, avoiding cross-contamination from leftover processes.

### 🧠 Design Intent (Why)
The goal of this optimization is not to "build an open-source version with similar functionality," but to converge the tool shape, tool result shape, and recovery semantics actually seen by the host as closely as possible onto the current calling conventions of the official `computer-use`. This way, whether doing packet-capture comparisons, running evals, or continuing to optimize focus strategy, all of it can be built on a compatibility surface closer to real host behavior, rather than being disrupted by non-essential differences like custom schemas, on-disk screenshot paths, or test fixture races.

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ToolDefinitions.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ToolResult.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MCPServer.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/Errors.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/FixtureBridge.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `apps/OpenComputerUse/Sources/OpenComputerUse/OpenComputerUseMain.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `docs/ARCHITECTURE.md`
- `docs/SECURITY.md`

### 🔁 Follow-up | 2026-04-17 19:01

**Additional Actions:**
- **[Official source discovery]**: Continued investigating via `computer-use-cli` and local binary string inspection, confirming that the official `list_apps`'s `uses`/ordering comes from Spotlight metadata's `kMDItemUseCount` and `kMDItemLastUsedDate_Ranking`, not `Knowledge/knowledgeC.db`.
- **[App list exact match]**: Rewrote `AppDiscovery`'s app catalog logic to run a metadata query against the standard application scope, then merge with running apps; local testing confirms `list_apps` produces a zero-diff match against the current official output.
- **[Safety parity]**: Added an official-style high-risk bundle denylist layer, so name queries for apps like `iTerm2` return `appNotFound(...)` and bundle-id queries return a safety denial, aligning with the official boundary behavior.
- **[State rendering tightening]**: Continued tightening `get_app_state`'s AX rendering order, traits/value copy, toolbar/group display, and secondary action filtering; complex outline scenarios are now noticeably closer to official, though samples like Activity Monitor still have a few trailing detail differences.
- **[Docs sync]**: Synced updates to the architecture, security, quality, and execution plan docs, so the repo no longer retains the stale `Knowledge` speculation or the outdated "no security policy yet" claim.

**Extra Files Modified:**
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AppDiscovery.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `docs/QUALITY_SCORE.md`
- `docs/exec-plans/active/20260417-official-tool-alignment.md`

### 🔁 Follow-up | 2026-04-17 20:30

**Additional Actions:**
- **[State text prefix tightening]**: Further tightened the text header of `get_app_state` / action tools to start directly with `App=<bundle-id> (pid ...)`, no longer emitting `Computer Use state (CUA App Version: 750)` or an `<app_state>` wrapper.
- **[Selected text formatting parity]**: Changed selected text from our own code fence + explanatory note to the current official-closer single-line `Selected text: [...]` form.
- **[Canonical app identifier in errors]**: For error messages relying on window bounds, prioritized outputting the bundle identifier, reducing the chance that subsequent tool calls drift back to the app name.
- **[Regression coverage]**: Added unit tests locking down the state text's starting format and `Selected text` rendering, preventing future refactors from reintroducing these differences.
- **[Reference correction]**: Updated the in-repo reverse-engineering sample doc, clarifying that the current baseline should be the direct MCP `content[0].text`'s `App=...`-starting format as the official baseline.

**Extra Files Modified:**
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/references/codex-computer-use-reverse-engineering/tool-call-samples-2026-04-17.md`
