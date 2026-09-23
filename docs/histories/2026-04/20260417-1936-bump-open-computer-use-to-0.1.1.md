## [2026-04-17 19:36] | Task: Bump open-computer-use to 0.1.1 and refresh the Codex plugin install

### 🤖 Execution Context
* **Agent ID**: `primary`
* **Base Model**: `gpt-5`
* **Runtime**: `Codex CLI + SwiftPM`

### 📥 User Query
> Bump the version to `0.1.1`, then update the plugin in Codex.

### 🛠 Changes Overview
**Scope:** `plugins/open-computer-use`, `packages/OpenComputerUseKit`, `apps/OpenComputerUseSmokeSuite`, `scripts`, `docs`

**Key Actions:**
- **[Version bump]**: Unify the plugin manifest, the MCP server's self-reported version, the smoke client version, the CLI version, and the app bundle version, bumping them all to `0.1.1`.
- **[Docs sync]**: Sync-fix the example plugin cache path in the docs so it no longer references the old `0.1.0` directory.
- **[Codex install refresh]**: Run `./scripts/install-codex-plugin.sh --rebuild`, refreshing the local plugin cache to `~/.codex/plugins/cache/open-computer-use-local/open-computer-use/0.1.1`, and update `~/.codex/config.toml`.
- **[Verification]**: Run `swift test`, which passes, and verify that `plugin.json` in the cache now shows `version = 0.1.1`.

### 🧠 Design Intent (Why)
The focus of this change is to unify the version identifiers the repo exposes externally onto a single semantic version, avoiding inconsistency between the plugin manifest, the Codex cache directory, the MCP handshake version, and the CLI docs. Once the version number is unified, refreshing the local Codex plugin via the install script is what ensures subsequent real-world calls and the local source stay on the same version.

### 📁 Files Modified
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `scripts/build-open-computer-use-app.sh`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MCPServer.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/README.md`
- `docs/references/codex-computer-use-cli.md`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/histories/2026-04/20260417-1936-bump-open-computer-use-to-0.1.1.md`
