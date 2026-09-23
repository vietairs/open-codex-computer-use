## [2026-09-23 10:20] | Task: translate the remaining Chinese docs to English

### 🤖 Execution Context
* **Agent ID**: `hvn:cortex --auto` controller with 18 parallel translation subagents
* **Base Model**: `claude-opus-5-5` (controller), `claude-sonnet-5` (translators)
* **Runtime**: Claude Code CLI, macOS

### 📥 User Query
> Translate the remaining Chinese docs to English.

### 🛠 Changes Overview
**Scope:** repository documentation only (`AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING.md`, `docs/**`, two experiment READMEs, one artifact README, `scripts/cursor-motion-re/README.md`)

**Key Actions:**
- **Translated 251 tracked Markdown files** in place, keeping headings, tables, code fences, link targets, commands and version strings unchanged.
- **Made the English-only doc rule explicit**: no written rule required Chinese before this change; the convention came only from the Chinese templates and existing notes. `AGENTS.md` now states that all repository documents are written in English, with `README.zh-CN.md` as the one exception. The rule that assistant replies mirror the user's language is unchanged.
- **Kept deliberate Chinese**: `README.zh-CN.md` (the Chinese translation of the README), the README language-switch badge, and literal on-screen UI strings or test input quoted from real apps (for example Feishu (飞书) menu labels), each glossed in English.

### 🧠 Design Intent (Why)
The fork's maintainer works in English, and `AGENTS.md`, the entry point every agent reads first, was Chinese. A mechanical check confirmed that every translated file keeps the original's heading count, code-fence count and link targets, and that every remaining line containing CJK (30 lines in 13 files) is intentional literal data.

Trade-off accepted: any of these files that upstream later edits will conflict on the next upstream sync.

Two files are left for the PRs that already own them: `docs/releases/RELEASE_GUIDE.md` (notarization PR) and `docs/exec-plans/active/20260922-local-decision-model-mcp-tool.md` (decision-model PR).

### 📁 Files Modified
- `AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING.md`
- `docs/**` (244 files, including every note under `docs/histories/`)
- `experiments/CursorMotion/README.md`, `experiments/StandaloneCursor/README.md`
- `artifacts/tool-comparisons/20260417-focus-behavior/README.md`, `scripts/cursor-motion-re/README.md`
