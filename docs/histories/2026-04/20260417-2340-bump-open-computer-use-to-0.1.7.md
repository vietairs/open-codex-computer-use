## [2026-04-17 23:40] | Task: Release 0.1.7

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Bump a small version, commit the related changes, git tag it, then push.

### 🛠 Changes Overview
**Scope:** `apps/OpenComputerUse`, `packages/OpenComputerUseKit`, `plugins/open-computer-use`, `scripts/`, `README.md`, `docs/`

**Key Actions:**
- **Unified the version number**: bumped the plugin manifest, CLI version constant, MCP server version, smoke/test examples, and cache paths in docs all to `0.1.7`.
- **Wrapped up this round's features**: folded in the one-click Codex/Claude MCP install scripts, npm launcher help updates, and the permission onboarding panel positioning fix as part of this patch release.
- **Synced repo docs**: updated the README, architecture doc, active exec plan, and histories so the usage paths and described behavior stay consistent post-release.

### 🧠 Design Intent (Why)
The focus of this patch release was to formally ship two categories of real user-visible changes: one is the install path, adding idempotent MCP install commands for Codex and Claude Code; the other is the permission onboarding experience, where the helper panel now re-follows the `System Settings` `+ / -` control row instead of dropping to the bottom of a long page. Bumping the version number and docs together to `0.1.7` avoids further drift between the npm package, plugin cache, CLI self-reported version, and README examples.

### 📁 Files Modified
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/README.md`
- `docs/references/codex-computer-use-cli.md`
- `scripts/install-codex-mcp.sh`
- `scripts/install-claude-mcp.sh`
- `scripts/npm/build-packages.mjs`
- `README.md`
- `docs/ARCHITECTURE.md`
- `docs/exec-plans/active/20260417-permission-onboarding-app.md`
- `docs/histories/2026-04/20260417-2122-fix-permission-panel-tracking.md`
- `docs/histories/2026-04/20260417-2255-add-codex-mcp-installer.md`
- `docs/histories/2026-04/20260417-2310-add-claude-mcp-installer.md`
- `docs/histories/2026-04/20260417-2340-bump-open-computer-use-to-0.1.7.md`
