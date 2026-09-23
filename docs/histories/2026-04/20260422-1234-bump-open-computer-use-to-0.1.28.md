## [2026-04-22 12:34] | Task: Release 0.1.28

### Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5.4`
* **Runtime**: `Codex CLI on macOS + SwiftPM`

### Changes Overview
**Scope:** release version bump, release notes, local release verification

**Key Actions:**
- **[Version Bump]**: Uniformly bumped the plugin manifest, Swift/Go version constants, smoke suite initialization version, test MCP client version, and CLI doc paths to `0.1.28`.
- **[Release Notes]**: Added `0.1.28` to the user-facing release record, noting that this patch release focuses on aligning the runtime overlay cursor's default speed with the official recovered spring timing.
- **[Release Trigger]**: Based on the runtime cursor speed alignment commit, prepared to push a `v0.1.28` tag to trigger a new GitHub Actions release.

### Files Modified
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/README.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-04/20260422-1234-bump-open-computer-use-to-0.1.28.md`
