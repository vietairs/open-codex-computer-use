## [2026-04-18 00:14] | Task: Switch the README to English

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Make the current README.md the English version.

### 🛠 Changes Overview
**Scope:** `README`, `docs/histories`

**Key Actions:**
- **Rewrote the README in English**: Rewrote the existing Chinese README in English, keeping the current product intro, Quick Start, additional commands, and License structure.
- **Kept the permission notes**: Preserved the guidance that the global npm install path should be treated as the stable authorization target, so the English version doesn't lose this key usage constraint.

### 🧠 Design Intent (Why)
The user asked for the main README to serve directly as the English entry-point doc, so this change doesn't add a separate bilingual file — it replaces the content directly with English, while keeping the install path and permission notes unchanged.

### 📁 Files Modified
- `README.md`
- `docs/histories/2026-04/20260418-0014-translate-readme-to-english.md`
