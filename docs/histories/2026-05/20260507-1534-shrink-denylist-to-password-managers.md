## [2026-05-07 15:34] | Task: Shrink the built-in denylist

### 🤖 Execution Context
* **Agent ID**: `primary`
* **Base Model**: `gpt-5`
* **Runtime**: `Codex CLI + SwiftPM`

### 📥 User Query
> Look at GitHub Issue #12 and trace why a list was added previously; the user thinks this block should be removed. It was then explicitly requested that everything except password managers be removed from the built-in denylist.

### 🛠 Changes Overview
**Scope:** `packages/OpenComputerUseKit`, `docs`

**Key Actions:**
- **[Denylist scope]**: shrunk macOS `AppSafetyPolicy`'s built-in denylist to password managers: 1Password, Bitwarden, Dashlane, LastPass, NordPass, and Proton Pass.
- **[Non-password unblock]**: removed the built-in blocking of terminal-type apps, Chrome / Atlas, and system components, to avoid the normal app automation path being blocked by hardcoded policy.
- **[Regression coverage]**: added unit tests confirming Chrome, iTerm2, Atlas, and SecurityAgent are not built-in block targets, while still keeping password-manager blocking covered.
- **[Docs sync]**: updated the security, architecture, quality-score, and official-alignment plan docs to record Chrome's historical inclusion in the denylist, the judgment that it lacked an official refusal sample to back it up, and the current product decision to block only password managers.

### 🧠 Design Intent (Why)
The original denylist commit aimed to replicate the official security boundary, but the samples archived in the repo only proved refusal behavior for iTerm2; Chrome only ever appeared in `list_apps` output. Continuing to hardcode terminals, browsers, and system components into the built-in block list would make the normal app automation path unusable. For now, only clearly high-sensitivity targets like password managers are kept blocked; policy for other sensitive apps is left to future session-approval / policy design.

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AppDiscovery.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/ARCHITECTURE.md`
- `docs/SECURITY.md`
- `docs/QUALITY_SCORE.md`
- `docs/exec-plans/active/20260417-official-tool-alignment.md`
