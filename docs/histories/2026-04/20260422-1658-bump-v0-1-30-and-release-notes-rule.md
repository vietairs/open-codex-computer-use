## [2026-04-22 16:58] | Task: bump v0.1.30 and document release notes rule

### Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5`
* **Runtime**: `local macOS shell`

### User Query
> Bump a version; confirm whether v0.1.29's What's Changed / New Contributors were auto-generated, and write the release-notes convention going forward into the repo.

### Changes Overview
**Scope:** release version sources, release guide, feature release notes

**Key Actions:**
- **[Version bump]**: synced the Open Computer Use version source from `0.1.29` up to `0.1.30`.
- **[Release notes rule]**: clarified in `RELEASE_GUIDE.md` that the GitHub Release uses `--generate-notes` to auto-generate notes; if the auto-generated body only contains `Full Changelog`, the release agent must manually add `What's Changed`.
- **[User notes]**: recorded `0.1.30`'s Windows runtime preview and the release-notes convention in `feature-release-notes.md`.

### Design Intent
`v0.1.29` having `What's Changed` / `New Contributors` was the result of GitHub's automatic release notes categorizing merged PRs; a direct-commit release may only generate `Full Changelog`. Going forward, AI performing a version bump must check and fill in the release body, to avoid the user-visible release page lacking a change summary.

### Files Modified
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/README.md`
- `docs/releases/RELEASE_GUIDE.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-04/20260422-1658-bump-v0-1-30-and-release-notes-rule.md`
