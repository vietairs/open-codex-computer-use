## [2026-07-10 16:59] | Task: Document the macOS 14.0+ system requirement

### 🤖 Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex Desktop`

### 📥 User Query
> Make it explicit in the README and skill docs that the macOS runtime requires macOS 14.0 or later, and note that older versions can't be fixed by granting permissions.

### 🛠 Changes Overview
**Scope:** `README.md`, `README.zh-CN.md`, `skills/open-computer-use`

**Key Actions:**
- **[Bilingual README]**: add a standalone, prominent macOS 14.0+ system requirement in Quick Start, shown separately from the permissions notes.
- **[Skill workflow]**: require the agent to check the macOS version before invoking the CLI or `doctor`, avoiding misdiagnosing binary incompatibility as a permissions problem.
- **[Installation and troubleshooting]**: explain that below macOS 14.0 the binary cannot launch at all, and that granting permissions or running `doctor` cannot fix this compatibility error.

### 🧠 Design Intent (Why)
Let users and agents see the real minimum system requirement right at the installation and troubleshooting entry points, reducing cases where users on an older macOS version get misdirected into the permission-granting flow.

### 📁 Files Modified
- `README.md`
- `README.zh-CN.md`
- `skills/open-computer-use/SKILL.md`
- `skills/open-computer-use/references/installation.md`
- `skills/open-computer-use/references/troubleshooting.md`
