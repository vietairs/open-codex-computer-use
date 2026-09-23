## [2026-04-17 22:55] | Task: Add a Codex MCP install command

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Add one more `open-computer-use install-codex-mcp`, which can install into Codex's `~/.codex/config.toml`; before installing, it should check via TOML parsing whether the config is already installed, to avoid duplicate runs.

### 🛠 Changes Overview
**Scope:** `scripts/`, `scripts/npm/build-packages.mjs`, `README.md`

**Key Actions:**
- **New MCP install script**: Added `scripts/install-codex-mcp.sh`, dedicated to writing `open-computer-use mcp` into Codex's `mcp_servers` config.
- **Added TOML idempotency check**: Before writing, parses the existing `~/.codex/config.toml` with `tomllib`; if the same MCP config already exists, it's a no-op.
- **Wired into the npm CLI entrypoint**: After a global install, `open-computer-use install-codex-mcp` proxies directly to this script, with help text and the README updated to match.

### 🧠 Design Intent (Why)
This requirement is essentially "make the npm CLI itself a self-installable Codex MCP server." It's a different path from installing via the plugin marketplace, and the most important thing is not to crudely keep appending duplicate blocks to the end of `config.toml`. Doing a real TOML parse first, then idempotently upserting into the target section, preserves the existing file format while avoiding config clutter from repeated runs.

### 📁 Files Modified
- `scripts/install-codex-mcp.sh`
- `scripts/npm/build-packages.mjs`
- `README.md`
