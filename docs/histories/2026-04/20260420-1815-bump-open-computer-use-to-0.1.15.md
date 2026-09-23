## [2026-04-20 18:15] | Task: Release 0.1.15

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5.4`
* **Runtime**: `Codex CLI on macOS`

### 📥 User Query
> Commit the related changes, then add a version-numbered git tag and push it to trigger a run and see.

### 🛠 Changes Overview
**Scope:** `apps/`, `docs/`, `packages/`, `plugins/`, `scripts/`

**Key Actions:**
- **[Version Bump]**: Unify the plugin manifest, Swift/Go version constants, the smoke suite's init version, the MCP client version in unit tests, and the CLI doc path, bumping them all to `0.1.15`.
- **[Release Notes]**: Append `0.1.15` to the user-facing release notes, explaining that the core of this release is unifying the cross-channel permission identity and signing chain of `Open Computer Use.app`.
- **[Release Trigger]**: Close out the release input based on the preceding feature commit, preparing to push the `v0.1.15` tag to trigger the GitHub Actions npm package and DMG release pipeline.

### 🧠 Design Intent (Why)
What the user needs to verify this time isn't just a local fix, but whether "unifying the signing identity" can actually make it through the release pipeline. Bundling the version bump, tag, and CI trigger into a single patch release keeps the external distribution behavior on npm/GitHub Releases aligned with the local verification results, avoiding a situation where the feature fix already sits in a local commit while the release input is still stuck on the old version.

### 📁 Files Modified
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/README.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-04/20260420-1815-bump-open-computer-use-to-0.1.15.md`
