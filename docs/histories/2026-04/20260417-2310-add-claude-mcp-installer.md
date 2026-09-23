## [2026-04-17 23:10] | Task: Add the Claude MCP install command

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Add another command, `open-computer-use install-clauce-mcp`, that installs into `~/.claude.json`, following the official Claude MCP docs, and it should also be idempotent.

### 🛠 Changes Overview
**Scope:** `scripts/`, `scripts/npm/build-packages.mjs`, `README.md`

**Key Actions:**
- **Added a Claude install script**: Added `scripts/install-claude-mcp.sh`, which writes into the current project's `~/.claude.json` following the local-scope structure from the official Claude MCP docs.
- **Added JSON idempotency detection**: Before writing, it first parses the existing `~/.claude.json`; if an MCP config with the same name already exists under the current project and its contents match, it is a no-op.
- **Wired up a dual command alias**: The npm CLI supports both `install-claude-mcp` and the `install-clauce-mcp` name from the user's request, both pointing to the same implementation.

### 🧠 Design Intent (Why)
Claude Code's `~/.claude.json` is not a single-purpose file that only holds MCP config — it's a mixed JSON file combining user state and project config. Simple string concatenation (as with TOML) would easily corrupt existing content here, so the safer approach, following the official docs, is to first parse the JSON and then only update the `mcpServers` entry under the current project's path. This guarantees idempotency while avoiding accidentally installing the server as a user-scope config that applies across all projects.

### 📁 Files Modified
- `scripts/install-claude-mcp.sh`
- `scripts/npm/build-packages.mjs`
- `README.md`
