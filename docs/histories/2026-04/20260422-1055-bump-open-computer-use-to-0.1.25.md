## [2026-04-22 10:55] | Task: Release 0.1.25

### User Request

> Commit the related changes, bump the version, and push.

### Changes This Round

- **[Version Bump]**: raised the plugin manifest, Swift/Go version constants, smoke suite init version, test MCP client version, and CLI doc paths together to `0.1.25`.
- **[Release Notes]**: added `0.1.25` to the user-visible release record, noting that this patch release focuses on tightening the settable-accessibility-element boundary for `set_value`.
- **[Release Trigger]**: based on the commit converging `set_value` to official semantics, preparing to push the `v0.1.25` tag to trigger a new GitHub Actions release.

### Design Rationale

`0.1.24` fixed the global physical pointer fallback issue for `click`, but `set_value` still leaked the underlying `-25200` error for AX nodes that are readable but not writable, such as in Sublime. This patch release converges `set_value` to the official settable-only semantics, shipped as its own version so installed users get a clear error message.

### Files Affected

- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/README.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-04/20260422-1055-bump-open-computer-use-to-0.1.25.md`
