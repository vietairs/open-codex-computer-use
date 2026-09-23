## [2026-04-20 18:08] | Task: Release 0.1.17

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5.4`
* **Runtime**: `Codex CLI on macOS`

### 📥 User Query
> Sure, bump the patch version, push the tag, and check the outcome.

### 🛠 Changes Overview
**Scope:** `apps/`, `docs/`, `packages/`, `plugins/`, `scripts/`

**Key Actions:**
- **[Version Bump]**: Uniformly raised the plugin manifest, Swift/Go version constants, smoke suite init version, test MCP client version, and CLI doc paths to `0.1.17`.
- **[Release Notes]**: Added `0.1.17` to the user-facing release notes, describing this release's core change as wiring up unified `Developer ID Application` signing and `Cursor Motion` notarization/staple.
- **[Release Trigger]**: Finalized the release inputs based on the current `HEAD` (which includes the release signing/notarization chain and the new `Cursor Motion` video entry in the README), ready to push the `v0.1.17` tag to trigger GitHub Actions.

### 🧠 Design Intent (Why)
This wasn't a plain version bump, but actually shipping the distribution-pipeline improvements already on `main` into an external release. Only by unifying `Developer ID` signing, `Cursor Motion` notarization, and their corresponding version sources into a single new patch release would GitHub Actions build with the new flow and expose the outward-facing artifacts on tag publish.

### 📁 Files Modified
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/README.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-04/20260420-1808-bump-open-computer-use-to-0.1.17.md`
