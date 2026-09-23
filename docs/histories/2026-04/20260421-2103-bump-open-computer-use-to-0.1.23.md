## [2026-04-21 21:03] | Task: Release 0.1.23

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Commit the related changes, bump the version, and push.

### 🛠 Changes Overview
**Scope:** `apps/`, `docs/`, `packages/`, `plugins/`, `scripts/`

**Key Actions:**
- **[Version Bump]**: raised the plugin manifest, Swift/Go version constants, smoke suite init version, test MCP client version, and CLI doc paths together to `0.1.23`.
- **[Release Notes]**: added `0.1.23` to the user-visible release record, noting that this patch release focuses on native `open-computer-use call` and JSON-array sequential action orchestration.
- **[Release Trigger]**: based on the CLI call feature commits on main after `v0.1.22`, preparing to push the `v0.1.23` tag to trigger a new GitHub Actions release.

### 🧠 Design Intent (Why)
After `v0.1.22`, main already included the native `open-computer-use call` entry point, a shared MCP/CLI dispatcher, and sequential-action JSON orchestration. Before release, the npm manifest, CLI version, test inputs, and version sources in docs all needed to be raised together, to avoid the tag drifting out of sync with the actual npm staging package version.

### 📁 Files Modified
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/README.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-04/20260421-2103-bump-open-computer-use-to-0.1.23.md`
