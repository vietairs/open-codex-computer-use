## [2026-05-07 15:53] | Task: Release 0.1.39

### 🤖 Execution Context
* **Agent ID**: `primary`
* **Base Model**: `gpt-5`
* **Runtime**: `Codex CLI + SwiftPM`

### 📥 User Query
> Commit, push, and release.

### 🛠 Changes Overview
**Scope:** `release`, `plugins/open-computer-use`, `apps`, `packages`, `scripts`, `docs`

**Key Actions:**
- **[Version bump]**: Bumped the Open Computer Use version source from `0.1.38` to `0.1.39`.
- **[Release notes]**: Added the `0.1.39` user-facing release entry, noting the macOS app denylist has been narrowed down to password managers.
- **[Release prep]**: Prepared the npm / GitHub Release verification material corresponding to the `v0.1.39` tag.

### 🧠 Design Intent (Why)
This release narrows the app safety-blocking policy from a broad hardcoded high-risk list down to password managers, reducing false blocks on routine automation targets like Chrome, terminals, and system components. The version source, release notes, and history need to stay consistent with the tag to avoid version drift between the npm artifact and the GitHub Release.

### 📁 Files Modified
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `apps/OpenComputerUseLinux/main.go`
- `apps/OpenComputerUseWindows/main.go`
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/README.md`
- `docs/releases/feature-release-notes.md`
