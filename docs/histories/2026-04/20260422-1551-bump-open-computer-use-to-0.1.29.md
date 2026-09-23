## [2026-04-22 15:51] | Task: Release 0.1.29

### Background

- The user asked to submit a PR and bump the version on top of the changes already completed.
- A prior commit had already added the directed-mouse-event fallback for `click`, plus a repo-level doc note about the English-reply rule; this patch release covers only the user-visible `click` behavior improvement.

### Changes

- **[Version Bump]**: Unified the plugin manifest, Swift/Go version constants, smoke suite init version, test MCP client version, and CLI doc paths to `0.1.29`.
- **[Release Notes]**: Added `0.1.29` to the user-facing release notes, describing that this patch release focuses on `click`'s directed-mouse-event fallback after an AX failure, and a more stable semantic click ordering.
- **[Release Trigger]**: Prepared a consistent version source for the subsequent `v0.1.29` tag / GitHub Release / npm publish.
- **[Guide Fix]**: Fixed the npm staging verification command in `docs/releases/RELEASE_GUIDE.md`, defaulting it to not pass `--skip-build`, avoiding an outright failure on a clean checkout that lacks `dist/Open Computer Use.app`.
- **[Rebase Adjustment]**: Because `origin/main` had already released `0.1.28` while this PR was in flight, this branch's release bump was moved forward to `0.1.29` during conflict resolution, keeping the `0.1.28` release note already present on the main branch.

### Validation

- Passed: `swift test`
- Passed: `make check-docs`
- Passed: `node ./scripts/npm/build-packages.mjs --out-dir dist/release/npm-staging-check`, staging package version is `0.1.29`
- Passed: `./scripts/build-cursor-motion-dmg.sh --configuration release --arch universal --version 0.1.29`

### Files Affected

- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/README.md`
- `docs/releases/feature-release-notes.md`
- `docs/releases/RELEASE_GUIDE.md`
- `docs/histories/2026-04/20260422-1551-bump-open-computer-use-to-0.1.29.md`
