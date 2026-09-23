## [2026-04-20 18:42] | Task: Release 0.1.16 and split local Dev app identity

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5.4`
* **Runtime**: `Codex CLI on macOS`

### 📥 User Query
> Let's do it this way then: keep what's on CI as it already is (I'll deal with it once I have a certificate in the future), so CI-published builds stay canonical. Local development should just use local signing. But when building locally in DEBUG or dev mode, the app should have a `(Dev)` suffix, to make it clearer.

### 🛠 Changes Overview
**Scope:** `.github/workflows/`, `apps/`, `docs/`, `packages/`, `plugins/`, `scripts/`

**Key Actions:**
- **[CI Boundary Reset]**: removed the certificate import step from the release workflow, and `package-npm` again explicitly uses ad-hoc packaging, restoring the boundary of "CI artifacts publish the same way as before".
- **[Dev App Split]**: local non-release builds now uniformly output `Open Computer Use (Dev).app`, with the display name changed to `Open Computer Use (Dev)` and the bundle identifier changed to `com.ifuryst.opencomputeruse.dev`, so it no longer shows up as the same authorization object as the official release.
- **[Permission Routing]**: the permission discovery logic now prefers binding to the current dev app when running from a dev bundle, while the release runtime still prefers finding the stably installed official bundle; the launch/install scripts were also updated for the new `(Dev)` package name.
- **[Release Bump]**: unified the plugin manifest, Swift/Go version constants, smoke-suite init version, test MCP client version, CLI doc paths, and the user-visible release note all up to `0.1.16`.

### 🧠 Design Intent (Why)
The goal this time was not to keep forcing local ad-hoc builds and CI-distributed artifacts to share one signing chain, but to first clearly split the "official release identity" from the "local development identity". CI keeps serving as the stable, repeatable release entry point; local dev/debug builds now explicitly carry the `(Dev)` suffix and a separate bundle id, so they're neither mistaken for being fully equivalent to the official release, nor indistinguishable from it in the system's permission list.

### 📁 Files Modified
- `.github/workflows/release.yml`
- `scripts/build-open-computer-use-app.sh`
- `scripts/install-codex-plugin.sh`
- `plugins/open-computer-use/scripts/launch-open-computer-use.sh`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/Permissions.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `apps/OpenComputerUse/Sources/OpenComputerUse/PermissionOnboardingApp.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/README.md`
- `README.md`
- `README.zh-CN.md`
- `docs/ARCHITECTURE.md`
- `docs/CICD.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-04/20260420-1842-bump-open-computer-use-to-0.1.16.md`
