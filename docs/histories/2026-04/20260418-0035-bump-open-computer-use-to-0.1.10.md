## [2026-04-18 00:35] | Task: Release 0.1.10

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5.4`
* **Runtime**: `Codex CLI on macOS`

### 📥 User Query
> Bump a minor version, commit the changes, push a git tag

### 🛠 Changes Overview
**Scope:** `plugins/`, `packages/`, `apps/`, `scripts/`, `docs/`

**Key Actions:**
- **[Version Bump]**: Bumped the plugin manifest, Swift/Go-side version constants, smoke suite init version, and the client version in unit tests all to `0.1.10`.
- **[Release Notes]**: Added user-facing value notes for `0.1.10` in the release record, stating this release focuses on permission identity stability and consolidating the onboarding lifecycle.
- **[Release Prep]**: Established a dedicated release history entry for this round of permission and install-path fixes, to make later commits, tagging, and traceability easier.

### 🧠 Design Intent (Why)
This round's user-visible changes have crossed the line from "local tweak" — they touch bundle identity, permission persistence experience, npm install path priority, and the onboarding lifecycle. Shipping a dedicated patch version consolidates these permission-experience changes into a clear release boundary, preventing the npm package, tag, and history from drifting further out of sync.

### 📁 Files Modified
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/README.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-04/20260418-0035-bump-open-computer-use-to-0.1.10.md`
