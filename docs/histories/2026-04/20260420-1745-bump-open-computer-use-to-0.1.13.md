## [2026-04-20 17:45] | Task: Release 0.1.13

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> You can bump the version yourself, bump the patch version everywhere.

### 🛠 Changes Overview
**Scope:** `apps/`, `docs/`, `packages/`, `plugins/`, `scripts/`

**Key Actions:**
- **[Version Bump]**: Unified the plugin manifest, Swift/Go version constants, smoke suite init version, unit test client version, and CLI doc paths to `0.1.13`.
- **[Release Notes]**: Appended `0.1.13` to `docs/releases/feature-release-notes.md`, documenting the `Cursor Motion` naming cleanup and the DMG GitHub Releases flow.
- **[Release Guide Sync]**: Updated the local DMG build, tag push, and tag deletion examples in `docs/releases/RELEASE_GUIDE.md` to `0.1.13` uniformly, so the examples no longer stay on the old version.
- **[Validation]**: Re-ran `swift test` and the npm staging build, and directly checked `open-codex-computer-use-mcp/package.json` to confirm the staging version moved from `0.1.12` to `0.1.13`.

### 🧠 Design Intent (Why)
This isn't new feature development — it's advancing every user-facing version source and example in the repo forward by one patch version, so that future tags, docs, and smoke/CLI runs don't stay mixed between `0.1.12` and the new release content.

### 📁 Files Modified
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/README.md`
- `docs/releases/RELEASE_GUIDE.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-04/20260420-1745-bump-open-computer-use-to-0.1.13.md`
