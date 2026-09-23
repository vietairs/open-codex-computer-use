## [2026-04-17 23:26] | Task: Release 0.1.9

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Cut another release based on 0.1.8.

### 🛠 Changes Overview
**Scope:** plugin manifest, version constants, smoke/test, release docs

**Key Actions:**
- **Unify version numbers to `0.1.9`**: synced the plugin manifest, Swift/Go-side version constants, the smoke suite's initialization version, and the client version in unit tests.
- **Update release docs**: updated the tag example in the release workflow, and recorded `0.1.9`'s release purpose ("fix a release build failure") in the feature release notes.
- **Build on the previous fix**: moved forward with a new version based on the just-fixed Xcode 26 compile issue, rather than reusing the already-failed `v0.1.8` tag.

### 🧠 Design Intent (Why)
The release runs for `v0.1.7` and `v0.1.8` had both already failed. Continuing to reuse the old tag would be neither clean nor easy to reason about as the boundary of the release that actually contains the fix. Releasing `0.1.9` directly lets "fix the CI build error" be cut as a clear, distinct new version, making it easier to trace npm and GitHub release records afterward.

### 📁 Files Modified
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/README.md`
- `README.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-04/20260417-2326-bump-open-computer-use-to-0.1.9.md`
