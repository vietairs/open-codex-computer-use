## [2026-04-17 18:07] | Task: Move computer-use-cli and supplement repo docs

### 🤖 Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `gpt-5.4`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Move `computer-use-cli/` to the right place inside the `open-codex-computer-use` repo, and add documentation per this repo's `AGENTS.md` conventions so future AI agents know how to use this tool.

### 🛠 Changes Overview
**Scope:** `scripts/computer-use-cli`, `README`, `docs/ARCHITECTURE.md`, `docs/references`, `docs/histories`

**Key Actions:**
- **[Relocate helper CLI]**: Moved the standalone Go debugging tool to `scripts/computer-use-cli/`, placing it alongside the repo's other automation scripts.
- **[Document repo-level usage]**: Added entry points in the repo root `README.md`, the architecture doc, and the references index, so future agents don't have to rely on chat context alone to know this tool exists.
- **[Add durable reference]**: Added `docs/references/codex-computer-use-cli.md`, explaining why the official bundled `computer-use` cannot be relied on via a plain stdio client connection, and how it should be probed using app-server mode instead.

### 🧠 Design Intent (Why)
This CLI's job is debugging and probing, not being a primary repo artifact, so placing it under `scripts/` fits its boundaries better than stuffing it into `apps/` or `packages/`. At the same time, `AGENTS.md` explicitly requires repo-level knowledge to be captured in `docs/`, so a standalone reference doc carries "why it exists" and "how AI should use it," while `README` and `ARCHITECTURE` provide navigation to it — this fits this repo's documentation discipline better than piling details into `AGENTS.md`.

### 📁 Files Modified
- `scripts/computer-use-cli/README.md`
- `scripts/computer-use-cli/app_server.go`
- `scripts/computer-use-cli/go.mod`
- `scripts/computer-use-cli/go.sum`
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/main_test.go`
- `README.md`
- `docs/ARCHITECTURE.md`
- `docs/references/README.md`
- `docs/references/codex-computer-use-cli.md`
- `docs/histories/2026-04/20260417-1807-move-computer-use-cli-into-scripts.md`
