## [2026-04-17 21:38] | Task: Release 0.1.3

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Sure, cut a version release.

### 🛠 Changes Overview
**Scope:** `plugins/`, `packages/`, `apps/`, `scripts/`, `docs/`

**Key Actions:**
- **Unified version number**: Bumped the plugin manifest, MCP server version, smoke suite client version, and `computer-use-cli` version all to `0.1.3`.
- **Updated doc examples**: Updated the CLI doc's example plugin cache directory path from `0.1.2` to `0.1.3`.
- **Prepared the release**: Had the npm distribution pipeline generate and publish the `0.1.3` package based on the new plugin version.

### 🧠 Design Intent (Why)
The previous round's README changes needed to reach the npm page, and the most direct way to do that is a patch release. Keeping the version source as a single point of consistency avoids the npm package, the MCP server's self-reported version, and the plugin cache path example drifting apart again.

### 📁 Files Modified
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `docs/references/codex-computer-use-cli.md`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MCPServer.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `scripts/computer-use-cli/README.md`
- `scripts/computer-use-cli/main.go`
