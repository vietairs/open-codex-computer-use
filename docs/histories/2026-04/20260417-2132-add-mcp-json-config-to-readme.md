## [2026-04-17 21:32] | Task: Add an MCP JSON config example to the README

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> The README needs a standard MCP JSON config example, making it clear to users whether `npm install -g open-computer-use` plus a config block is all it takes to get it working.

### 🛠 Changes Overview
**Scope:** `README.md`, `scripts/npm/build-packages.mjs`

**Key Actions:**
- **Update the repo README**: add the standard usage path of "global install + `mcpServers` JSON + first-run authorization".
- **Update the npm package README template**: so future versions published via npm automatically carry the same MCP config example.
- **Add an optional environment-variable example**: give the JSON config for disabling the visual cursor overlay.
- **Add command comments**: add a one-line explanation above the `doctor`, `mcp`, and `install-codex-plugin` commands to lower the onboarding cost.

### 🧠 Design Intent (Why)
For an MCP server, what users need most is a JSON block they can paste straight into their client config, not having to first understand the repo structure or the plugin install logic. Putting this path near the top of the README directly answers "how do I configure it after installing", and better matches real-world usage habits.

### 📁 Files Modified
- `README.md`
- `scripts/npm/build-packages.mjs`
