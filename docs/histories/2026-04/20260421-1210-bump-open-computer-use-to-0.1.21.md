## [2026-04-21 12:10] | Task: Release 0.1.21

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Bump a version on main, push a git tag, and use gh to track whether the action runs through cleanly.

### 🛠 Changes Overview
**Scope:** `apps/`, `docs/`, `packages/`, `plugins/`, `scripts/`

**Key Actions:**
- **[Version Bump]**: Raised the plugin manifest, Swift/Go version constants, smoke suite init version, test MCP client version, and CLI doc paths uniformly to `0.1.21`.
- **[Release Notes]**: Added `0.1.21` to the user-facing release record, noting that the core of this patch release is tightening the runtime software cursor's visual look and the app icon's margins.
- **[Release Trigger]**: Based on the software cursor rendering and icon fixes committed to main after `v0.1.20`, prepared to push a `v0.1.21` tag to trigger a new GitHub Actions release.

### 🧠 Design Intent (Why)
Since `v0.1.20`, main already includes the runtime overlay glyph, initial orientation, draw direction, and app icon safe-margin fixes. Before releasing, the npm manifest, CLI version, test inputs, and every version source in the docs need to be bumped together, to avoid the tag ending up out of sync with the actual npm staging package version.

### 📁 Files Modified
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/README.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-04/20260421-1210-bump-open-computer-use-to-0.1.21.md`
