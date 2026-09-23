## [2026-04-20 18:06] | Task: Remove the install-* commands' runtime dependency on Python

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> `open-computer-use install-codex-mcp` now reports `python3 with tomllib is required`; in principle the install command shouldn't depend on Python. Consider using something like Swift instead, and check and fix all of the `install-*` commands.

### 🛠 Changes Overview
**Scope:** `scripts/`, `scripts/npm/`, `docs/histories/`

**Key Actions:**
- **Extracted a shared install-config helper**: Added `scripts/install-config-helper.mjs`, centralizing the read/write logic for Claude JSON, Codex TOML, and the plugin manifest.
- **Removed the install-* Python dependency**: `install-claude-mcp.sh`, `install-codex-mcp.sh`, and `install-codex-plugin.sh` were all changed to call the Node helper, no longer requiring `python3` / `tomllib` on the local machine.
- **Synced npm distribution contents**: Updated `scripts/npm/build-packages.mjs` to bundle the new helper into the npm package as well, avoiding missing files in the globally installed package.

### 🧠 Design Intent (Why)
These install commands are essentially part of the npm CLI; additionally requiring Python at runtime doesn't match user expectations, and it would let the simplest install path get tripped up by the system's Python version. Compared to a runtime `swift` script, Node is already a prerequisite for the npm package to work at all, so consolidating the config-rewrite logic directly into a helper distributed with the package means fewer dependencies and more consistent behavior.

### ✅ Verification
- `node --check scripts/install-config-helper.mjs`
- Ran `./scripts/install-codex-mcp.sh` with a temporary `CODEX_HOME`, verifying legacy-alias migration and no-op on repeated runs
- Ran `./scripts/install-claude-mcp.sh` with a temporary `CLAUDE_CONFIG_PATH`, verifying idempotent JSON writes
- Ran `./scripts/install-codex-plugin.sh --configuration release` with a temporary `CODEX_HOME`, verifying plugin cache and `config.toml` updates
- `node ./scripts/npm/build-packages.mjs --skip-build --package open-computer-use --out-dir dist/tmp/npm-stage-check`

### 📁 Files Modified
- `scripts/install-config-helper.mjs`
- `scripts/install-claude-mcp.sh`
- `scripts/install-codex-mcp.sh`
- `scripts/install-codex-plugin.sh`
- `scripts/npm/build-packages.mjs`
