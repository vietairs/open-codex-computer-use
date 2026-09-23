## [2026-04-17 20:43] | Task: Bump open-computer-use to 0.1.2 and refresh the Codex plugin install

### 🤖 Execution Context
* **Agent ID**: `primary`
* **Base Model**: `gpt-5`
* **Runtime**: `Codex CLI + SwiftPM`

### 📥 User Query
> Bump to `0.1.2` and install it into the Codex plugin.

### 🛠 Changes Overview
**Scope:** `plugins/open-computer-use`, `packages/OpenComputerUseKit`, `apps/OpenComputerUseSmokeSuite`, `scripts`, `docs`

**Key Actions:**
- **[Version bump]**: Unified the plugin manifest, MCP server self-reported version, smoke client version, CLI version, and app bundle version to `0.1.2`.
- **[Bundle metadata sync]**: Bumped `CFBundleShortVersionString` to `0.1.2` in the packaging script and incremented `CFBundleVersion` to `3`, so locally cached app metadata does not lag behind the source version.
- **[Docs sync]**: Updated the local plugin cache path examples in the `computer-use-cli` docs so they no longer reference the old `0.1.1` directory.
- **[Codex install refresh]**: Ran `./scripts/install-codex-plugin.sh --rebuild` to refresh the local plugin cache to `~/.codex/plugins/cache/open-computer-use-local/open-computer-use/0.1.2`, and confirmed `~/.codex/config.toml` still enables `open-computer-use@open-computer-use-local`.
- **[Verification]**: Ran `swift test` successfully, and verified that `.codex-plugin/plugin.json` in the cache now shows `version = 0.1.2`.

### 🧠 Design Intent (Why)
The goal of this change is still to keep the "source version, packaged artifact version, plugin cache version, MCP handshake version" quartet consistent, so that the plugin cache Codex actually loads does not diverge from the current repo source. Doing the install step within the same pass ensures that subsequent calls through Codex hit this freshly upgraded `0.1.2`.

### 📁 Files Modified
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MCPServer.swift`
- `scripts/build-open-computer-use-app.sh`
- `scripts/computer-use-cli/main.go`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/references/codex-computer-use-cli.md`
- `scripts/computer-use-cli/README.md`
- `docs/histories/2026-04/20260417-2043-bump-open-computer-use-to-0.1.2.md`
