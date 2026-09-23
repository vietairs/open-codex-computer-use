## [2026-04-22 11:15] | Task: Release 0.1.26

### Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5.4`
* **Runtime**: `Codex CLI on macOS + SwiftPM`

### Changes Overview
**Scope:** release version bump, release notes, local release verification

**Key Actions:**
- **[Version Bump]**: Unified the plugin manifest, Swift/Go version constants, smoke suite init version, test MCP client version, and CLI doc paths, bumping them all to `0.1.26`.
- **[Release Notes]**: Added `0.1.26` to the user-facing release record, noting that this patch release focuses on the visual cursor's continuous-operation lifecycle, turn-ended cleanup, and the default non-physical pointer path for `scroll` / `drag`.
- **[Release Trigger]**: Based on the cursor lifecycle and the alignment commit for the remaining tools' default behavior, prepared to push the `v0.1.26` tag to trigger a new GitHub Actions release.

### Files Modified
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/README.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-04/20260422-1115-bump-open-computer-use-to-0.1.26.md`
