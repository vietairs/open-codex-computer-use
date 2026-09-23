## [2026-04-22 18:16] | Task: Add MCP install support for Gemini and opencode

### 🤖 Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5 family (Codex)`
* **Runtime**: `Codex CLI on macOS`

### 📥 User Query
> add quick support for gemini and opencode, you can test it by run gemini and opencode from command line

### 🛠 Changes Overview
**Scope:** install scripts, npm launcher, README docs

**Key Actions:**
- **[Installer Support]**: Added `scripts/install-gemini-mcp.sh` and `scripts/install-opencode-mcp.sh`, targeting the Gemini CLI's and opencode's respective MCP config formats.
- **[Shared Config Helper]**: Extended `scripts/install-config-helper.mjs` to support writing Gemini JSON config, as well as idempotent install and stale-alias cleanup for opencode's `mcp.<name> = { type: "local", command: [...] }`.
- **[Packaging and Docs]**: Updated `README.md`, `README.zh-CN.md`, and the npm launcher/build scripts, so the npm-installed `open-computer-use` can also directly forward `install-gemini-mcp` / `install-opencode-mcp`.
- **[Repo Hygiene]**: Added `.gemini/` to `.gitignore`, avoiding Gemini's default project-scope install from bringing local config noise into the workspace.

### 🧠 Design Intent (Why)
This change continues the repo's existing "built-in install subcommand" pattern, rather than requiring users to manually look up different host CLIs' config formats. Gemini defaults to a project-level `.gemini/settings.json`, while opencode merges multiple JSON config files, so the helper needs to explicitly handle target file selection, idempotent writes, and stale-alias cleanup, avoiding leaving duplicate config or a dirty workspace after a user installs once.

### 📁 Files Modified
- `.gitignore`
- `README.md`
- `README.zh-CN.md`
- `scripts/install-config-helper.mjs`
- `scripts/install-gemini-mcp.sh`
- `scripts/install-opencode-mcp.sh`
- `scripts/npm/build-packages.mjs`
