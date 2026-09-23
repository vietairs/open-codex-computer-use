## [2026-04-22 17:59] | Task: bump open-computer-use to 0.1.32

### Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5`
* **Runtime**: `local macOS shell`

### User Query
> bump a new version

### Changes Overview
**Scope:** release version sources, feature release notes, task history

**Key Actions:**
- **[Version bump]**: Unified Open Computer Use's primary version source and related test/doc examples, bumping them from `0.1.30` to `0.1.32`.
- **[Release record repair]**: Filled in the missing `0.1.31` feature release note, and added a version-alignment record for `0.1.32`.
- **[Version-line decision]**: First verified that a `v0.1.31` tag and GitHub Release already exist remotely, so this round does not reuse `0.1.31` and instead moves straight on to `0.1.32`, avoiding further widening the version-source inconsistency.

### Design Intent
The key point of this round is not to invent yet another new versioning rule, but to pull the repository back into a "single source of version truth" state. The current `HEAD` already corresponds to the remote `v0.1.31`, but the manifest and version constants in the repository are still stuck at `0.1.30`; if `0.1.31` continued to be reused, subsequent tags, staging artifacts, and the version number users see would still easily clash. Moving on to `0.1.32` closes the current main line back onto a consistent version line without rewriting the existing release.

### Files Modified
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/README.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-04/20260422-1759-bump-open-computer-use-to-0.1.32.md`
