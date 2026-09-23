## [2026-04-17 21:54] | Task: Release 0.1.4

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Re-release 0.1.4

### 🛠 Changes Overview
**Scope:** `plugins/`, `packages/`, `apps/`, `scripts/`, `docs/`

**Key Actions:**
- **Unify version number**: Bumped the plugin manifest, MCP server version, smoke suite client version, and `computer-use-cli` version all to `0.1.4`.
- **Update doc examples**: Updated the CLI doc's example version path for the plugin cache directory from `0.1.3` to `0.1.4`.
- **Prepare re-release**: Regenerated and republished the `0.1.4` package based on the already-fixed npm symlink launcher template.

### 🧠 Design Intent (Why)
`0.1.3` already shipped the new bundle name and icon, but the npm global symlink launch path still had a bug. Cutting a new patch release lets the launcher fix land officially on npm, instead of continuing to rely on a local hotfix.

### 📁 Files Modified
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `docs/references/codex-computer-use-cli.md`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MCPServer.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `scripts/computer-use-cli/README.md`
- `scripts/computer-use-cli/main.go`
