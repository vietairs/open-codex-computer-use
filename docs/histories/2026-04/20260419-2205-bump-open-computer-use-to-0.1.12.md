## [2026-04-19 22:05] | Task: Release 0.1.12

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> I deleted the 0.1.12 tag on GitHub; delete it locally too, and re-tag once it's fixed.

### 🛠 Changes Overview
**Scope:** `apps/`, `docs/`, `packages/`, `plugins/`, `scripts/`

**Key Actions:**
- **[Tag Cleanup]**: Deleted the local `v0.1.12` tag to avoid continuing to use a tag that still pointed at the wrong npm artifact version before the version source was fixed.
- **[Version Bump]**: Unified the plugin manifest, Swift/Go version constants, smoke suite init version, the client version used in unit tests, and doc examples, bumping them all to `0.1.12`.
- **[Release Notes]**: Updated the feature release record, logging the permission overlay animation/repositioning fix together with this release workflow's version reconciliation under `0.1.12`.
- **[Publish Validation]**: Re-ran `swift test` and the npm staging build locally, confirming the generated package version changed from `0.1.11` to `0.1.12` and no longer triggers npm's "cannot overwrite a published version" 403.

### 🧠 Design Intent (Why)
This wasn't new feature development, but a fix for version consistency in the release toolchain. The tag had already moved to `v0.1.12`, but the npm staging artifact was still reading `0.1.11` from the plugin manifest, causing CI to fail outright when trying to re-publish the old version. After reconciling the "release source version" with every externally exposed version string, the tag, runtime, smoke/test, and npm artifacts became consistent again.

### 📁 Files Modified
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/README.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-04/20260419-2205-bump-open-computer-use-to-0.1.12.md`
