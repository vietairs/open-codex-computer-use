## [2026-04-20 18:36] | Task: Release 0.1.18

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5.4`
* **Runtime**: `Codex CLI on macOS`

### 📥 User Query
> Okay, bump the patch version, push the tag, and see what happens

### 🛠 Changes Overview
**Scope:** `apps/`, `docs/`, `packages/`, `plugins/`, `scripts/`

**Key Actions:**
- **[Version Bump]**: Uniformly raised the plugin manifest, Swift/Go version constants, the smoke suite's initialization version, the test MCP client version, and the CLI doc path to `0.1.18`.
- **[Release Notes Correction]**: Added an accurate note for `0.1.17`, documenting that its `package-npm` succeeded but `Cursor Motion` notarization failed due to a missing hardened runtime; added `0.1.18` as the actual patch release that fills in the hardened runtime.
- **[Release Trigger]**: Settled the new version on `HEAD` after the hardened-runtime fix, ready to push the `v0.1.18` tag to trigger a new GitHub Actions release.

### 🧠 Design Intent (Why)
`0.1.17` had already successfully published its npm package, so it is no longer suitable to keep retrying all release steps under the same version. The safest approach is to land the hardened-runtime fix that notarization actually needs into a new patch release, making `0.1.18` the first version to have both Developer ID signing and a notarizable `Cursor Motion` asset.

### 📁 Files Modified
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/README.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-04/20260420-1836-bump-open-computer-use-to-0.1.18.md`
