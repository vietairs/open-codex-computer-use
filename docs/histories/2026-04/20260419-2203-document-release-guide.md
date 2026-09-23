## [2026-04-19 22:03] | Task: Capture a must-read release guide

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Split this release process into its own standalone md under docs, then add a pointer in AGENTS.md for "must-read before releasing." That way future releases will all know how to do it.

### 🛠 Changes Overview
**Scope:** `docs/`, `AGENTS.md`

**Key Actions:**
- **[Release Guide]**: Added `docs/releases/RELEASE_GUIDE.md`, capturing the version source of truth, the release checklist, tag-push commands, how to troubleshoot GitHub Actions, and the fix path for a mistakenly created tag.
- **[Agent Routing]**: Added a "must-read before releasing" navigation entry in `AGENTS.md`, so tasks like version bumps, tagging, or investigating a failed release land on the correct doc from the start.
- **[Docs Index Sync]**: Updated `docs/releases/README.md` to separate the user-facing release-notes entry point from the maintainer-facing release guide.

### 🧠 Design Intent (Why)
This release fix exposed a typical problem: if the version source of truth and tagging conventions only live in chat, the next release will easily hit the same pitfalls again. Capturing "which version files must be changed first, how to verify the staging package actually became the new version, what to check first when CI fails" into a standalone doc, with the shortest-path navigation added in `AGENTS.md`, lets future agents and humans follow the same process without relying on memory.

### 📁 Files Modified
- `AGENTS.md`
- `docs/releases/README.md`
- `docs/releases/RELEASE_GUIDE.md`
- `docs/histories/2026-04/20260419-2203-document-release-guide.md`
