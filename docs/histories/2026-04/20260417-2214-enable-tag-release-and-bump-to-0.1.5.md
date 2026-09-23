## [2026-04-17 22:14] | Task: Enable tag-based releases and bump to 0.1.5

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Set up the workflow via gh so releases are subsequently done via git tag; once that's done, commit the related changes, cut a 0.1.5 release, then watch the results.

### 🛠 Changes Overview
**Scope:** `.github/workflows/`, `plugins/`, `packages/`, `apps/`, `scripts/`, `docs/`

**Key Actions:**
- **Adjusted the release trigger**: Made `release.yml` auto-publish on push of `v*` and `*.*.*` tags, while keeping manual triggering.
- **Preserved Trusted Publishing**: The publish step continues to go through GitHub Actions OIDC, without relying on a long-lived npm token.
- **Version bump**: Uniformly updated the version in the plugin manifest, MCP server, self-tests, and CLI docs to `0.1.5`.
- **Synced docs**: Updated the README and CI/CD docs to clearly describe the "push a git tag to auto-publish to npm" usage.
- **Fixed the GitHub runner**: Adjusted the release workflow from `macos-14` to `macos-26`, avoiding the fact that GitHub Hosted Runner's default Xcode 15.4 / Swift 5.10 cannot build a package with `swift-tools-version: 6.2`.

### 🧠 Design Intent (Why)
Since Trusted Publishing is already configured on the npm side, the most natural release path is "commit -> tag -> GitHub Actions auto-publish." This way the publish action is bound to an explicit Git tag, which also better matches the maintenance convention of a one-to-one correspondence between npm package versions and Git versions.

### 📁 Files Modified
- `.github/workflows/release.yml`
- `README.md`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `docs/CICD.md`
- `docs/references/codex-computer-use-cli.md`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MCPServer.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `scripts/computer-use-cli/README.md`
- `scripts/computer-use-cli/main.go`
