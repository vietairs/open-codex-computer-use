## [2026-04-17 23:50] | Task: Release 0.1.8

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Bump a minor version, commit the related changes, then git tag and push.

### 🛠 Changes Overview
**Scope:** `plugins/open-computer-use`, `packages/OpenComputerUseKit`, `apps/OpenComputerUseSmokeSuite`, `scripts/computer-use-cli`, `README.md`, `docs/`

**Key Actions:**
- **Unified the version number**: Bumped the plugin manifest, Swift/Go-side version constants, smoke suite initialization version, and test samples uniformly to `0.1.8`.
- **Synced release docs**: Updated the README, `computer-use-cli` example paths, and release notes to keep the tag-release examples consistent with the current version.
- **Recorded this release**: Added a history entry closing out this round's permission-onboarding panel follow fix with the corresponding patch release.

### 🧠 Design Intent (Why)
The focus of this patch release is to formally fold the just-fixed permission-onboarding panel follow issue into a publishable version, while re-aligning version references across the plugin manifest, the CLI's self-reported version, smoke/test samples, and docs, so users don't end up installing a stale cached path or seeing a mismatched version number.

### 📁 Files Modified
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `scripts/computer-use-cli/main.go`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/computer-use-cli/README.md`
- `README.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-04/20260417-2350-bump-open-computer-use-to-0.1.8.md`
