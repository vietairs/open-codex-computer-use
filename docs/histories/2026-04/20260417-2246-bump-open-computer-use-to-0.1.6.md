## [2026-04-17 22:46] | Task: Release 0.1.6

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Bump a minor version, commit the related changes, tag it, and push.

### 🛠 Changes Overview
**Scope:** `apps/OpenComputerUseSmokeSuite`, `packages/OpenComputerUseKit`, `plugins/open-computer-use`, `scripts/computer-use-cli`, `README.md`, `docs`

**Key Actions:**
- **Unify version numbers**: bumped the plugin manifest, CLI version constant, MCP server version, and smoke/test samples to `0.1.6` consistently.
- **Sync doc paths**: switched the local plugin cache example path in the `computer-use-cli` docs to `0.1.6`.
- **Wrap up this round's features**: folded the CLI `help/version` fix and the post-npm-install `doctor` onboarding guidance into this patch release.
- **Prepare the tag release**: kept the source and doc versions consistent for the subsequent `git tag` / `git push origin <tag>`.

### 🧠 Design Intent (Why)
This release isn't just a standalone version-number refresh; it wraps up two already-finished but not-yet-released user-facing changes together: the CLI basic-usability fix, and the permission-onboarding flow for a first npm install. Unifying the version identifiers in the source, docs, and plugin cache paths before tagging avoids the release artifacts, README, and local install path clashing with each other.

### 📁 Files Modified
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/README.md`
- `docs/references/codex-computer-use-cli.md`
- `README.md`
- `docs/histories/2026-04/20260417-2246-bump-open-computer-use-to-0.1.6.md`
