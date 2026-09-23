# Cross-platform npm distribution

## Goal

Make `npm i -g open-computer-use` installable on macOS, Linux, and Windows from the same existing npm package, with the root launcher invoking the matching native app or binary inside the package based on the current `os-arch`.

## Scope

- Included:
  - Change npm staging from a single macOS-app package into three-platform bundled artifacts.
  - Have the existing `open-computer-use`, `open-computer-use-mcp`, and `open-codex-computer-use-mcp` packages bundle `darwin-arm64`, `darwin-x64`, `linux-arm64`, `linux-x64`, `win32-arm64`, and `win32-x64` runtimes.
  - Keep the release/publish surface limited to the existing three npm package names.
  - Update the release workflow, README, architecture docs, release guide, and history.
  - Bump the patch version, tag the release, and use a Linux VM to actually verify the MCP `tools/list` after a global npm install.
- Excluded:
  - Adding new Linux/Windows graphical fixtures.
  - Completing an interactive Windows desktop smoke test.
  - Changing the protocol surface of the 9 tools.

## Background

- Related documents:
  - `docs/ARCHITECTURE.md`
  - `docs/CICD.md`
  - `docs/releases/RELEASE_GUIDE.md`
- Related code paths:
  - `scripts/npm/build-packages.mjs`
  - `scripts/npm/publish-packages.mjs`
  - `scripts/release-package.sh`
  - `.github/workflows/release.yml`
  - `scripts/build-open-computer-use-linux.sh`
  - `scripts/build-open-computer-use-windows.sh`
- Known constraints:
  - `open-computer-use@0.1.33` currently on the npm registry still declares `os=["darwin"]`, so Linux/Windows won't install correctly.
  - The Linux/Windows runtimes are experimental first versions, but already expose the same set of 9 MCP tools.
  - The root package needs to keep the three historical entry points `open-computer-use`, `open-computer-use-mcp`, and `open-codex-computer-use-mcp`.

## Risks

- Risk: package size is larger than the macOS-only version.
  - Mitigation: keep the existing npm package names and a reproducible install path for now; evaluate splitting into per-platform packages later once npm package permissions are ready.
- Risk: the launcher can't find the bundled runtime for the current `os-arch`.
  - Mitigation: the launcher outputs a clear message about the missing bundled artifact path and the reinstall command.
- Risk: the CI macOS runner has no Go toolchain, causing Linux/Windows cross compilation to fail.
  - Mitigation: the release workflow explicitly sets up Go.
- Risk: the Linux runtime needs an already-logged-in session of the same desktop user; a cross-user root process cannot reliably control an ordinary user's desktop.
  - Mitigation: the runtime auto-discovers the current user's session env; after publishing, verify npm install, MCP initialize, `tools/list`, and actual `list_apps` with the `leo` desktop user.

## Milestones

1. Design and implement the npm package structure.
2. Sync docs, history, and the version source.
3. Local staging / pack / MCP tools list verification.
4. Commit, tag, push, and track the release workflow.
5. Globally npm install the latest version on a Linux VM and verify the MCP tools list.

## Verification Method

- Commands:
  - `node ./scripts/npm/build-packages.mjs --out-dir dist/release/npm-staging-check`
  - `./scripts/release-package.sh`
  - `swift test`
  - `(cd apps/OpenComputerUseLinux && go test ./...)`
  - `(cd apps/OpenComputerUseWindows && go test ./...)`
  - `node ./scripts/npm/publish-packages.mjs --skip-build --out-dir dist/release/npm-staging --dry-run`
- Manual checks:
  - The root/alias packages no longer declare `optionalDependencies`.
  - The staging package contains `dist/Open Computer Use.app`, `dist/linux/`, and `dist/windows/`.
  - The npm tarball count is 3, matching the release manifest.
- Observation checks:
  - The GitHub Actions release workflow succeeded: `24816330343`.
  - `open-computer-use@0.1.35`, `open-computer-use-mcp@0.1.35`, and `open-codex-computer-use-mcp@0.1.35` are visible on the npm registry.
  - After `npm i -g open-computer-use@0.1.35` on the Linux VM, the raw MCP `tools/list` returns 9 tools.
  - The `0.1.36` prerelease binary on the Linux VM can auto-discover the session env under `env -i` for the `leo` user, and passes both raw MCP `tools/list` / `tools/call(list_apps)`.
  - GitHub Actions release workflow `24817430041` succeeded.
  - `open-computer-use@0.1.36`, `open-computer-use-mcp@0.1.36`, and `open-codex-computer-use-mcp@0.1.36` are visible on the npm registry.
  - After `npm i -g open-computer-use@0.1.36` on the Linux VM, the Codex MCP config, raw MCP `tools/list`, and `call list_apps` all pass.

## Progress Log

- [x] Confirmed the current npm package is still macOS-only.
- [x] Completed root/alias package bundled artifact staging.
- [x] Completed converging the publish surface to the existing three npm packages, and kept the CI Go toolchain adjustment.
- [x] Completed syncing version, docs, and history.
- [x] Completed local verification: staging / release tarballs / dry-run publish / Swift tests / Linux Go tests / Windows Go tests / macOS npm prefix install / MCP tools list.
- [x] Completed tagging the release, tracking CI, and npm registry verification.
- [x] Completed the Linux VM npm install and MCP tools/list verification.
- [x] Completed the Linux VM `0.1.36` prerelease binary env-less MCP tools/list and list_apps verification.
- [x] Completed the `v0.1.36` release workflow, npm registry, GitHub Release notes, and post-install verification on the Linux VM.

## Decision Log

- 2026-04-23: The initial version used npm `optionalDependencies` plus a per-platform `os`/`cpu` package, but the `v0.1.34` release was blocked by npm permissions when CI tried to publish new npm package names.
- 2026-04-23: `v0.1.35` switched to bundling all three platforms' six runtimes inside the existing three npm packages, avoiding the new-package-name permission issue; the root launcher continues to map by `process.platform-process.arch`.
