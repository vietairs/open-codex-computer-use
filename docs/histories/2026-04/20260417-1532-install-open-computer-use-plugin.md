## [2026-04-17 15:32] | Task: Install the open-computer-use Codex plugin

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5.4`
* **Runtime**: `Codex CLI on macOS`

### 📥 User Query
> Install our open-codex-computer-use into the Codex app's plugins, with the plugin named open-computer-use.

### 🛠 Changes Overview
**Scope:** `plugins/open-computer-use`, `scripts/`, `README.md`, `.agents/plugins/`

**Key Actions:**
- **[Plugin Packaging]**: Added a repo-local Codex marketplace and the `open-computer-use` plugin manifest, MCP wrapper, and display assets to the repo.
- **[Local Install Flow]**: Added `scripts/install-codex-plugin.sh`, which builds the app, registers this repo as a local Codex marketplace, installs the plugin cache package into `~/.codex/plugins/cache/...`, and enables the plugin.
- **[Docs Sync]**: Added the plugin install entry point and behavior notes to the README, so the plugin integration approach doesn't live only in chat context.

### 🧠 Design Intent (Why)
Keeping the plugin definition version-controlled in the repo is more traceable than only hand-editing `~/.codex/config.toml`, and better fits this repo's "Agent-first, knowledge on disk" constraint. The install script also cleans up old direct-connect MCP config along the way, to avoid the same set of computer-use tools being registered twice.

### 🔁 Follow-up Fix (2026-04-17 15:38)
- Filled a real install gap: Codex Desktop actually loads plugins from `~/.codex/plugins/cache/<marketplace>/<plugin>/<version>/` — simply writing `config.toml` doesn't make the plugin show up in the UI.
- Updated the launcher so it supports both:
  - Running directly from `dist/OpenCodexComputerUse.app` in the source repo
  - Running from `OpenCodexComputerUse.app` inside the Codex plugin cache directory
- Synced the README to match current real behavior, so the "it'll appear after a restart" note stops misleading future installs.

### 📁 Files Modified
- `.agents/plugins/marketplace.json`
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `plugins/open-computer-use/.mcp.json`
- `plugins/open-computer-use/assets/open-computer-use.svg`
- `plugins/open-computer-use/assets/open-computer-use-small.svg`
- `plugins/open-computer-use/scripts/launch-open-computer-use.sh`
- `scripts/install-codex-plugin.sh`
- `README.md`
- `docs/histories/2026-04/20260417-1532-install-open-computer-use-plugin.md`
