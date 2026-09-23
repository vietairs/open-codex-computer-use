## [2026-04-21 16:11] | Task: Release 0.1.22

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> bump version and ship a minor release

### 🛠 Changes Overview
**Scope:** `apps/`, `docs/`, `packages/`, `plugins/`, `scripts/`

**Key Actions:**
- **[Version Bump]**: unified the plugin manifest, Swift/Go version constants, smoke-suite init version, test MCP client version, and CLI doc paths all up to `0.1.22`.
- **[Release Notes]**: added `0.1.22` to the user-visible release notes, noting that this patch release focuses on fixing the runtime software cursor's heading and coordinate-system conversion.
- **[Release Trigger]**: prepared to push a `v0.1.22` tag to trigger a new GitHub Actions release, based on the runtime visual cursor heading fix that landed on main after `v0.1.21`.

### 🧠 Design Intent (Why)
After `v0.1.21`, main already contained a fix for the velocity/heading conversion between the runtime overlay's AppKit global coordinates and Cursor Motion's y-down screen state. Before releasing, the version sources across the npm manifest, CLI version, test inputs, and docs needed to be bumped together, to avoid a mismatch between the tag and the actual npm staging package version.

### 📁 Files Modified
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/README.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-04/20260421-1611-bump-open-computer-use-to-0.1.22.md`
