## [2026-04-21 16:59] | Task: Archive official computer-use bundle zips

### 🤖 Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Add the two official `computer-use` version zips from the local bundled plugin cache into a specific directory in the repo, and manage them with Git LFS.

### 🛠 Changes Overview
**Scope:** official `computer-use` reverse-engineering reference material archive

**Key Actions:**
- **[Archive]**: Added `official-bundles/computer-use/` directory, archiving `1.0.750.zip` and `1.0.755.zip`.
- **[LFS]**: Added `.gitattributes` rules so zips under this directory are tracked via Git LFS.
- **[Docs]**: Added asset directory documentation and SHA-256 checksum info to facilitate future reproduction and version comparison.

### 🧠 Design Intent (Why)
Placing the official zips under the reverse-engineering asset directory makes clear they are reference inputs, not source code or build dependencies; using Git LFS avoids polluting normal Git objects with large binaries, while keeping a traceable version sample.

### 📁 Files Modified
- `.gitattributes`
- `docs/references/codex-computer-use-reverse-engineering/assets/README.md`
- `docs/references/codex-computer-use-reverse-engineering/assets/official-bundles/computer-use/README.md`
- `docs/references/codex-computer-use-reverse-engineering/assets/official-bundles/computer-use/SHA256SUMS`
- `docs/references/codex-computer-use-reverse-engineering/assets/official-bundles/computer-use/1.0.750.zip`
- `docs/references/codex-computer-use-reverse-engineering/assets/official-bundles/computer-use/1.0.755.zip`
