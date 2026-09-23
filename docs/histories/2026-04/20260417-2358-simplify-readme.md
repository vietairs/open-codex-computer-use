## [2026-04-17 23:58] | Task: Simplify the README

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Simplify the README to keep only the introduction, quick start, further subcommands, and license sections; the introduction should mention codex-computer-use and the OpenAI article, and the quick start should cover npm install, authorization, `open-computer-use doctor`, and MCP JSON configuration.

### 🛠 Changes Overview
**Scope:** `README`, `docs/histories`

**Key Actions:**
- **Rewrote the README structure**: Removed the lengthy source-run, packet-capture, and implementation-detail sections, keeping only a four-section entry-point document.
- **Kept the key onboarding path**: Clearly documented `npm i -g open-computer-use`, `open-computer-use doctor`, permission authorization, and MCP JSON configuration.
- **Added a summary of common commands**: Briefly listed the purpose of commands such as `install-claude-mcp`, `install-codex-mcp`, and `install-codex-plugin`.

### 🧠 Design Intent (Why)
The README now reads more like an install entry point than a project manual. Compressing the first-use path down to the minimum lowers the barrier to understanding for users; more detailed implementation and repository collaboration information remains in `docs/`.

### 📁 Files Modified
- `README.md`
- `docs/histories/2026-04/20260417-2358-simplify-readme.md`
