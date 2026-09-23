## [2026-04-17 18:12] | Task: Clean up absolute-path links within the repo

### 🤖 Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Clean up directory references in the repo that are written as absolute paths from the repo root, change them to relative paths, and emphasize in the corresponding `AGENTS.md` documentation that only relative paths may be used going forward.

### 🛠 Changes Overview
**Scope:** `README.md`, `docs/REPO_COLLAB_GUIDE.md`, `docs/histories`

**Key Actions:**
- **[Clean up links]**: Changed the two absolute-path links in `README.md` pointing to in-repo reference docs to relative paths.
- **[Add constraint]**: Added a rule to the documentation discipline section of `docs/REPO_COLLAB_GUIDE.md` clarifying that in-repo path references must not use machine-specific absolute paths.
- **[Preserve change]**: Added this history entry recording the purpose and scope of the path-convention cleanup.

### 🧠 Design Intent (Why)
If in-repo documentation hardcodes local-machine absolute paths, the links become non-portable and environmental incidentals leak into the repo's knowledge. Standardizing repo-local references to relative paths ensures they remain reliably usable across different machines, user directories, and collaborators.

### 📁 Files Modified
- `README.md`
- `docs/REPO_COLLAB_GUIDE.md`
- `docs/histories/2026-04/20260417-1812-normalize-repo-path-links.md`
