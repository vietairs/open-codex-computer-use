## [2026-04-23 11:51] | Task: Select the native runtime by os-arch for the three-platform npm install

## User Request

Wanted `npm i -g open-computer-use` to install successfully on macOS, Linux, and Windows, and to invoke the corresponding `.app`, Linux binary, or Windows `.exe` based on the current `os-arch`. This round also needed a patch version bump, a tag push to trigger a release, and a real test of the MCP tools list after a global npm install on a Linux VM.

## Main Changes

- **[NPM Packaging]**: Changed npm staging from a single macOS package to the three existing root/alias packages, each bundling the `darwin-arm64`, `darwin-x64`, `linux-arm64`, `linux-x64`, `win32-arm64`, and `win32-x64` runtimes.
- **[Runtime Launcher]**: Changed the root package's `bin/open-computer-use` to a cross-platform Node launcher that resolves and executes the corresponding bundled native runtime via `process.platform` / `process.arch`; gives a clear reinstall prompt when the artifact is missing.
- **[Release Flow]**: The release package build now builds the macOS app, Linux binaries, and Windows exes together; the publish script's release surface remains the three existing package names: `open-computer-use`, `open-computer-use-mcp`, and `open-codex-computer-use-mcp`.
- **[Plugin Path]**: Added Linux / Windows native payload fallback to the Codex plugin launcher and installer, while keeping the macOS app bundle path.
- **[Version Bump]**: Unified the plugin manifest, Swift version constant, Linux/Windows Go runtime, smoke/test inputs, and CLI helper docs, bumping them all to `0.1.35`.
- **[Docs]**: Synced the README, the Chinese README, the architecture doc, CI/CD notes, quality notes, the release guide, feature release notes, and related execution plans.

## Design Intent

The initial implementation used npm's native `optionalDependencies`, `os`, and `cpu` mechanism, but `v0.1.34` CI was blocked by npm permissions when publishing the newly added platform package names. `v0.1.35` instead bundles all six platform runtimes directly into the three existing npm packages, avoiding the new-package permission issue, while the launcher still performs local selection based on `process.platform` / `process.arch`.

## Files Affected

- `.github/workflows/release.yml`
- `scripts/npm/build-packages.mjs`
- `scripts/npm/publish-packages.mjs`
- `scripts/install-codex-plugin.sh`
- `plugins/open-computer-use/scripts/launch-open-computer-use.sh`
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `apps/OpenComputerUseLinux/main.go`
- `apps/OpenComputerUseWindows/main.go`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `docs/`

## Verification

- Passed: `node ./scripts/npm/build-packages.mjs --out-dir dist/release/npm-staging-check`
- Passed: `./scripts/release-package.sh`
- Passed: after installing only `open-computer-use-0.1.35.tgz` into a local npm prefix, `open-computer-use --version` printed `0.1.35`.
- Passed: after the local npm prefix install, `open-computer-use mcp`'s raw JSON-RPC `tools/list` returned 9 tools.
- Passed: `swift test`
- Passed: `(cd apps/OpenComputerUseLinux && go test ./...)`
- Passed: `(cd apps/OpenComputerUseWindows && go test ./...)`
- Passed: `node ./scripts/npm/publish-packages.mjs --skip-build --out-dir dist/release/npm-staging --dry-run`, with the release surface being the three existing root/alias packages.
- Passed: `git diff --check`
- Passed: GitHub Actions release workflow `24816330343`, with both `package-npm` and `release-cursor-motion-dmg` succeeding.
- Passed: `npm view open-computer-use@0.1.35`, `open-computer-use-mcp@0.1.35`, and `open-codex-computer-use-mcp@0.1.35` were all visible; `open-computer-use@0.1.35` no longer declares `optionalDependencies` / `os` / `cpu`.
- Passed: on an Ubuntu aarch64 VM, `npm i -g open-computer-use@0.1.35` succeeded, `open-computer-use --version` printed `0.1.35`, and `/usr/local/lib/node_modules/open-computer-use/dist/linux/arm64/open-computer-use` was confirmed to be an aarch64 ELF.
- Passed: on the Ubuntu aarch64 VM, the raw MCP `initialize` / `tools/list` returned 9 tools.
