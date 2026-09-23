## [2026-04-20 18:10] | Task: Release 0.1.19

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Commit the related changes, bump the version, push a git tag

### 🛠 Changes Overview
**Scope:** `apps/`, `docs/`, `packages/`, `plugins/`, `scripts/`

**Key Actions:**
- **[Version Bump]**: Bumped the plugin manifest, Swift/Go version constants, smoke suite init version, test MCP client version, and CLI doc path all to `0.1.19`.
- **[Release Notes]**: Added a note in the user-facing release record for `0.1.19` about consolidating the installer's runtime dependencies, stating this patch release's core change is removing the `install-*` commands' dependency on Python.
- **[Release Trigger]**: Locked in the release input based on `HEAD` after the installer fix, preparing to push a `v0.1.19` tag to trigger a new GitHub Actions release.

### 🧠 Design Intent (Why)
The installer error `python3 with tomllib is required` is a real release issue that a user could hit on their very first onboarding — not something that should stay a local-script-only fix. Bundling this fix together with the version source into a new patch release lets the npm package and the tag-driven GitHub Release both reflect the new behavior of "the installer no longer has a Python runtime dependency."

### 📁 Files Modified
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/README.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-04/20260420-1810-bump-open-computer-use-to-0.1.19.md`
