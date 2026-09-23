## [2026-04-22 18:28] | Task: Release 0.1.33

### Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5`
* **Runtime**: `local macOS shell`

### User Query
> bump a version and submit a pr

### Changes Overview
**Scope:** release version sources, feature release notes, task history

**Key Actions:**
- **[Version Bump]**: Uniformly bumped Open Computer Use's main version source and related test/doc examples from `0.1.32` to `0.1.33`.
- **[Release Notes]**: Recorded in `docs/releases/feature-release-notes.md` that this patch release focuses on MCP install support for Gemini CLI and opencode.
- **[PR Prep]**: Based on locally added Gemini/opencode installer commits, closed out the new release version line for subsequent branch push and PR.

### Design Intent
The goal of this version bump is not to publish an abstract "doc fix," but to formally bring the newly added Gemini / opencode host integration into the public version line. Since the current `HEAD` already has user-visible new install commands compared to the remote `v0.1.32`, it should move forward to `0.1.33`, keeping the feature commits, version sources, and user-visible release notes consistent.

### Files Modified
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/README.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-04/20260422-1828-bump-open-computer-use-to-0.1.33.md`
