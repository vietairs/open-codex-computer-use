## [2026-04-20 18:45] | Task: Release 0.1.20

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> bump version, push a git tag

### 🛠 Changes Overview
**Scope:** `apps/`, `docs/`, `packages/`, `plugins/`, `scripts/`

**Key Actions:**
- **[Version Bump]**: Uniformly bumped the plugin manifest, Swift/Go version constants, smoke suite init version, test MCP client version, and CLI doc paths to `0.1.20`.
- **[Release Notes]**: Added `0.1.20` to the user-visible release record, noting this patch release's core change is removing the plugin installer's host-command dependency on `rsync`.
- **[Release Trigger]**: Based on `HEAD` after the `rsync -> cpSync` fix, prepared the release input to push a `v0.1.20` tag and trigger a new GitHub Actions release.

### 🧠 Design Intent (Why)
`rsync` in `install-codex-plugin` is just an implementation detail for recursively copying a directory, not a business necessity. Since the previous version already removed the installer's Python dependency, this kind of unnecessary external command prerequisite should continue to be consolidated into npm/Node itself, making the access path more stable and predictable for users installing via npm.

### 📁 Files Modified
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/README.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-04/20260420-1845-bump-open-computer-use-to-0.1.20.md`
