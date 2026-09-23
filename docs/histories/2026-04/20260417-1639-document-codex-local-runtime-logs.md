## [2026-04-17 16:39] | Task: Document Codex local log observability

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Write the conclusion "check the LLM call dump first, and only fall back to Codex's own logs if that's insufficient" into `docs/references/`, as a standalone file placed next to `codex-network-capture.md`, and update `docs/references/README.md`.

### 🛠 Changes Overview
**Scope:** `docs/references`, `docs/histories`

**Key Actions:**
- **[Standalone runbook]**: Added `docs/references/codex-local-runtime-logs.md`, explaining when to additionally check Codex's local `logs_2.sqlite`, and how to query the parameters and results of a local `stdio` MCP such as `computer-use`.
- **[Priority note]**: Added a "check upstream capture first, then local logs" default order note to `docs/references/codex-network-capture.md`.
- **[Index update]**: Added an entry for the new doc in `docs/references/README.md`, making clear it's a supplementary path to the capture doc, not the default entry point.

### 🧠 Design Intent (Why)
Upstream capture and local logs solve different problems. Splitting the two observability paths into separate docs and making the priority explicit avoids reaching for the highly invasive interception route as soon as a local MCP / `computer-use` issue comes up; in most cases, checking the LLM call dump first is already enough, and the Codex host logs are only needed when that falls short.

### 📁 Files Modified
- `docs/references/codex-local-runtime-logs.md`
- `docs/references/codex-network-capture.md`
- `docs/references/README.md`
- `docs/histories/2026-04/20260417-1639-document-codex-local-runtime-logs.md`
