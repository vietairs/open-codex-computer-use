## [2026-04-21 16:24] | Task: Document the official computer-use sender-auth change

### 🤖 Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Investigate why `computer-use-cli` calling the official bundled `computer-use` through `app-server` returns `Sender process is not authenticated`, and determine whether it can still be called directly.

### 🛠 Changes Overview
**Scope:** `docs/`, `scripts/computer-use-cli/`

**Key Actions:**
- **[Runtime Finding]**: Documented that in official `computer-use` `1.0.755`, the raw app-server helper can only reliably list tools; actual tool calls are rejected by service-side sender authorization.
- **[Docs Sync]**: Updated the `computer-use-cli` README, reference docs, and architecture boundaries to prevent future work from continuing to treat the raw `mcpServer/tool/call` as a general-purpose direct-connect entry point to the official Computer Use.
- **[CLI Test Target]**: Changed `computer-use-cli`'s bundled-plugin auto-discovery to prefer resolving `1.0.750` for local compatibility testing, and added `COMPUTER_USE_PLUGIN_VERSION` / `--plugin-version` to explicitly switch the test version; app-server mode passes the resolved test version to the Codex host as a temporary `mcp_servers."computer-use"` override, and `--plugin-version host` reverts to the host's own configuration.
- **[Verification]**: `resolve-server` by default resolves to the non-translocated legacy install root at `~/.codex/plugins/computer-use`; `list-tools --transport app-server` can list 9 tools and shows the old schema; `call list_apps --transport app-server` returns the app list in the current workspace. When the `1.0.750` in cache carries `com.apple.quarantine`, LaunchServices AppTranslocation kicks in and returns `Apple event error -1708: Unknown error`.
- **[Bug Fix]**: Fixed the app-server temporary MCP override's `-c` key syntax. The Codex CLI override doesn't parse quoted dotted keys, so `mcp_servers."computer-use".command` landed on the wrong key; changing it to `mcp_servers.computer-use.command` makes the override actually take effect.
- **[Bug Fix]**: Made the default legacy-version test target prefer `~/.codex/plugins/computer-use`, and validate via the manifest version that it's really `1.0.750`, avoiding AppTranslocation caused by quarantine on the cache directory.

### 🧠 Design Intent (Why)
The official `SkyComputerUseClient`'s parent launch constraint only explains "who can launch the client" — it doesn't explain tool calls that are still rejected after already passing Apple Events/TCC. The docs need to separate the parent constraint, Apple Events/TCC, and service-side sender authorization / active IPC client tracking into distinct sections, so future comparisons between the official and open-source implementations don't conflate the root causes.

### 📁 Files Modified
- `docs/ARCHITECTURE.md`
- `docs/exec-plans/active/20260417-official-tool-alignment.md`
- `docs/references/codex-computer-use-cli.md`
- `docs/references/codex-computer-use-reverse-engineering/runtime-and-host-dependencies.md`
- `scripts/computer-use-cli/README.md`
- `scripts/computer-use-cli/app_server.go`
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/main_test.go`
