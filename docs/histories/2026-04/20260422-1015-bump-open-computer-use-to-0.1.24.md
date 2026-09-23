## [2026-04-22 10:15] | Task: Release 0.1.24

### 🤖 Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Commit the click-fix-related changes, bump the version, and push.

### 🛠 Changes Overview
**Scope:** `apps/`, `docs/`, `packages/`, `plugins/`, `scripts/`

**Key Actions:**
- **[Version Bump]**: bumped the plugin manifest, Swift/Go version constants, smoke suite initialization version, the test MCP client version, and the CLI doc path all to `0.1.24`.
- **[Release Notes]**: added `0.1.24` to the user-facing release records, noting this patch release focuses on `click`'s non-intrusive default behavior and the opt-in global physical-pointer fallback.
- **[Release Trigger]**: committed based on the click global-pointer-fallback fix, preparing to push a `v0.1.24` tag to trigger a new GitHub Actions release.

### 🧠 Design Intent (Why)
Since `v0.1.23`, main has included the click behavior fix: multi-clicks that AX can handle no longer fall straight into the global mouse path, and the physical-pointer fallback after AX failure is now off by default. Before releasing, the npm manifest, CLI version, test inputs, and every version source in the docs need to be bumped together, to avoid the tag diverging from the actual npm staging package version.

### 📁 Files Modified
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/README.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-04/20260422-1015-bump-open-computer-use-to-0.1.24.md`
