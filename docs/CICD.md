# CI/CD

This repository ships a CI/CD skeleton that does not assume any particular
language stack.

## Current release entry points

- `scripts/release-package.sh`: builds the universal `Open Computer Use.app`, cross-compiles the Linux / Windows runtimes, and stages the three existing root/alias npm packages. Every package embeds the macOS app, the Linux binaries and the Windows executables, and exposes the `open-computer-use` / `ocu` npm bin entry points. Outputs `dist/release/npm/*.tgz` and `dist/release/release-manifest.json`. CI still uses ad-hoc signing explicitly, matching the previous release path; local debug/dev builds may use the developer machine's own signing identity.
- `scripts/build-cursor-motion-dmg.sh`: builds `Cursor Motion.app` locally and packages `dist/release/cursor-motion/CursorMotion-<version>.dmg`. Supports `native` / `arm64` / `x86_64` / `universal`.
- `scripts/build-open-computer-use-linux.sh`: builds the experimental Linux `open-computer-use` binary locally for `arm64` / `amd64`. The release package embeds both artifacts into the existing npm packages under `dist/linux/`.
- `scripts/build-open-computer-use-windows.sh`: builds the experimental Windows `open-computer-use.exe` locally for `arm64` / `amd64`. The release package embeds both artifacts into the existing npm packages under `dist/windows/`.
- `.github/workflows/release.yml`: releases automatically on a pushed semver tag, and can also be triggered manually. A tag push runs both the npm release packaging and the `Cursor Motion` DMG packaging, then uploads the `.dmg` to the matching GitHub Releases page. The `Open Computer Use` npm artifacts default to ad-hoc signing; when the `OPEN_COMPUTER_USE_CODESIGN_*` secrets are configured, the workflow first imports the `Developer ID Application` certificate and then signs the release `.app` under that identity. The `Cursor Motion` DMG reuses the same `Developer ID Application` certificate to sign the app; when the `APPLE_NOTARY_*` secrets are also configured, the `.dmg` is notarized and stapled before upload.

## Current CI gates

Besides the release pipeline, the repository runs four independent gate
workflows on every PR and on every push to `main`. The workflow files are the
authority on the exact steps; this section is navigation only.

- `.github/workflows/ci.yml`: runs `scripts/ci.sh` (shell syntax checks, `check-docs.sh` / `check-repo-hygiene.sh` / `check-action-pinning.sh`, the Linux runtime's Python tests, and the Go tests for both the Linux and Windows runtimes), then additionally runs `swift build` and `swift test`.
- `.github/workflows/docs-check.yml`: runs `scripts/check-docs.sh` on its own.
- `.github/workflows/repo-hygiene.yml`: runs `scripts/check-repo-hygiene.sh` and `scripts/check-action-pinning.sh`.
- `.github/workflows/supply-chain-security.yml`: audits npm and Go dependencies for vulnerabilities. See `docs/SUPPLY_CHAIN_SECURITY.md` for details.

### Go toolchain pin

`ci.yml`, `release.yml` and `supply-chain-security.yml` deliberately pin the
same `go-version`. This is load-bearing rather than tidiness: `govulncheck`
reports the standard library of the toolchain it runs under, so a scanner
running on a newer Go than the release builder will report a clean result for
binaries that ship with a known-vulnerable standard library. Keep the three pins
equal when raising any one of them. The patch component must stay floating — an
exact version such as `go1.26.0` reports advisories that later patches of the
same minor already fix.

## Design principles

The goal of this default pipeline is to establish the delivery path before the
project has fully taken shape, rather than pretending we already know how a
future project should be built and deployed.

Once a new project's stack is settled, extend the real build path in
`scripts/release-package.sh` rather than starting a parallel process beside it.

All GitHub Actions are pinned to commit SHAs. Keep that constraint when
upgrading an action later.

## Suggested adoption order

1. Keep `ci.yml` as the repository's baseline gate.
2. Keep adding the project's own verification commands inside `scripts/ci.sh`.
3. Extend release artifacts on top of the real build already in `scripts/release-package.sh`.
4. Add concrete deployment jobs once the stack and environments are stable.
5. Keep supply-chain capabilities such as SBOM and provenance even if the delivery method changes.

## Default release artifacts

The current release pipeline produces:

- `dist/release/release-manifest.json`
- `dist/release/npm/vietairs-open-computer-use-<version>.tgz`
- `dist/release/npm/vietairs-open-computer-use-mcp-<version>.tgz`
- `dist/release/npm/vietairs-open-codex-computer-use-mcp-<version>.tgz`
- `dist/release/cursor-motion/CursorMotion-<version>.dmg`
- the npm release artifact uploaded from GitHub Actions
- the tag-aligned `CursorMotion-<version>.dmg` on GitHub Releases

In other words, even before the project reaches a more complex deployment
stage, the repository already has both a real, reusable npm artifact packaging
path and a git-tag-driven macOS app DMG delivery path.
