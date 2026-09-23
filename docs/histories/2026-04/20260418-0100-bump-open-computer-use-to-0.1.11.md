## [2026-04-18 01:00] | Task: Release 0.1.11

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5.4`
* **Runtime**: `Codex CLI on macOS`

### 📥 User Query
> Bump a patch version, commit all changes, push the git tag.

### 🛠 Changes Overview
**Scope:** `apps/`, `docs/`, `packages/`, `plugins/`, `scripts/`

**Key Actions:**
- **[Version Bump]**: Uniformly bumped the plugin manifest, Swift/Go version constants, smoke suite init version, and the unit test client version to `0.1.11`.
- **[Release Scope]**: Folded into this patch release the fix for the permission popover not appearing on first cold-start `System Settings`, along with the newly added Chinese README entry at the repo root.
- **[Release Notes]**: Updated the feature release notes, adding user-facing value and a change summary for `0.1.11`.

### 🧠 Design Intent (Why)
The remaining changes in this round were small, but they directly affect the first-authorization experience and the repo's entry-point docs. Cutting a separate patch release lets the "first cold-start visibility fix" and "Chinese README restoration" be split out from `0.1.10`'s permission-identity work, so subsequent tags stay disentangled from actual user-visible behavior.

### 📁 Files Modified
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/README.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-04/20260418-0100-bump-open-computer-use-to-0.1.11.md`
