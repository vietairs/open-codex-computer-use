## [2026-04-20 12:38] | Task: Confirm the official overlay cursor's tool trigger matrix

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5.4`
* **Runtime**: `Codex CLI + official computer-use app-server probe`

### 📥 User Query
> Using `scripts/computer-use-cli/`'s `app-server` to connect to the official `computer-use`, combined with bundled app binary analysis, confirm which tool calls originally trigger the overlay cursor; further confirm whether `type_text / press_key` trigger it.

### 🛠 Changes Overview
**Scope:** `docs/references`, `docs/histories`

**Key Actions:**
- **[Backfilled official-path testing]**: Used an isolated `HOME` to force-enable only the bundled `computer-use`, avoiding confusion between the local `open-computer-use` and the official implementation.
- **[Captured the tool trigger matrix]**: Added the overlay-trigger conclusions for `set_value / scroll / drag / perform_secondary_action / click / type_text / press_key` into the reverse-engineering doc.
- **[Recorded the click fork]**: Clarified that element-scoped `click` and coordinate `click` do not necessarily go through the same execution path.

### 🧠 Design Intent (Why)
If conclusions like these are left only in temporary logs and chat context, it's easy to repeat the same pitfalls next time, especially since the current machine's default config has the official plugin off and the local open-source implementation on. Documenting both "must switch to the official path first" and "which tools actually raise `Software Cursor`" together directly reduces future reverse-engineering misjudgments.

### 📁 Files Modified
- `docs/references/codex-computer-use-reverse-engineering/software-cursor-overlay.md`
- `docs/histories/2026-04/20260420-1238-confirm-official-overlay-trigger-matrix.md`
