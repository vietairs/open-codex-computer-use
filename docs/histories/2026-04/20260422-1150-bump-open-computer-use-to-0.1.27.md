## [2026-04-22 11:50] | Task: Release 0.1.27

### Background

- The user asked to commit all remaining changes and bump the version.
- The preceding commit finished closing out official alignment for the 9 Computer Use tools, mainly covering `perform_secondary_action` error semantics, the fixture `Raise` non-physical-pointer path, and `press_key` key-table aliases.

### Changes

- **[Version Bump]**: Uniformly bumped the plugin manifest, Swift/Go version constants, the smoke suite's initialization version, the test MCP client version, and the CLI doc paths to `0.1.27`.
- **[Release Notes]**: Added `0.1.27` to the user-facing release notes, explaining that this patch release focuses on closing out the remaining tools checklist, secondary-action error shape, and filling in xdotool aliases.
- **[Release Trigger]**: Prepared to tag this version bump with `v0.1.27` for use by the subsequent release pipeline.

### Verification

- Passed: `swift test`
- Passed: `node ./scripts/npm/build-packages.mjs --skip-build --out-dir dist/release/npm-staging-check`, staging package version is `0.1.27`
- Passed: `./scripts/build-cursor-motion-dmg.sh --configuration release --arch universal --version 0.1.27`

### Files Affected

- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/README.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-04/20260422-1150-bump-open-computer-use-to-0.1.27.md`
