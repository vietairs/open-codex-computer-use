# CI/CD

This repository ships a CI/CD skeleton that does not assume any particular
language stack.

## Current release entry points

- `scripts/release-package.sh`: builds the universal `Open Computer Use.app`, cross-compiles the Linux / Windows runtimes, and stages the three existing root/alias npm packages. Every package embeds the macOS app, the Linux binaries and the Windows executables, and exposes the `open-computer-use` / `ocu` npm bin entry points. It also calls `scripts/package-github-release-assets.sh`, so one run produces the npm tarballs, the GitHub Release direct-download assets and their manifests: `dist/release/npm/*.tgz`, `dist/release/release-manifest.json` and `dist/release/github/`. Release builds sign with the `Developer ID Application` identity when the `OPEN_COMPUTER_USE_CODESIGN_*` secrets exist and otherwise fall back to ad-hoc signing, which the workflow allows explicitly; local debug/dev builds may use the developer machine's own signing identity.
- `scripts/package-github-release-assets.sh`: packages the already-built universal `.app`, the two Linux binaries, the two Windows `.exe` files and the `open-computer-use` skill into `dist/release/github/`, and writes `SHA256SUMS` and `release-assets-manifest.json`. macOS must ship the whole app bundle; the executable inside the bundle is not a standalone install package.
- `scripts/build-cursor-motion-dmg.sh`: builds `Cursor Motion.app` locally and packages `dist/release/cursor-motion/CursorMotion-<version>.dmg`. Supports `native` / `arm64` / `x86_64` / `universal`.
- `scripts/build-open-computer-use-linux.sh`: builds the experimental Linux `open-computer-use` binary locally for `arm64` / `amd64`. The release package embeds both artifacts into the existing npm packages under `dist/linux/`.
- `scripts/build-open-computer-use-windows.sh`: builds the experimental Windows `open-computer-use.exe` locally for `arm64` / `amd64`. The release package embeds both artifacts into the existing npm packages under `dist/windows/`.
- `.github/workflows/release.yml`: releases automatically on a pushed semver tag, and can also be triggered manually. A tag push builds the npm / direct-download artifacts and the `Cursor Motion` DMG in parallel; only when both build jobs succeed does the single `publish-github-release` job create or update the GitHub Release and upload the full asset set. The `Open Computer Use` npm and app artifacts default to ad-hoc signing; when the `OPEN_COMPUTER_USE_CODESIGN_*` secrets are configured, the workflow first imports the `Developer ID Application` certificate and then signs the release `.app` under that identity. The `Cursor Motion` DMG reuses the same `Developer ID Application` certificate to sign the app; when the `APPLE_NOTARY_*` secrets are also configured, the `.dmg` is notarized and stapled before upload. The direct-download app zip is packaged from the same `.app` the build script already signed, notarized and stapled, so it needs no separate notarization step. This fork's CI has no signing or notary secrets configured, so the app zip it produces is ad-hoc signed and not notarized, matching the npm artifacts; a browser download of it is quarantined by macOS and Gatekeeper blocks the first launch until the user approves it (see the Gatekeeper note in `docs/releases/RELEASE_GUIDE.md`). `SHA256SUMS` covers the Open Computer Use direct-download assets only, not the Cursor Motion DMG. For public repositories, on a tag push only, the workflow also attaches a build provenance attestation to the direct-download archives. Workflow permissions are least-privilege: read-only by default, with `id-token` and `attestations` write on `package-npm` and `contents: write` only on `publish-github-release`.

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
- `dist/release/github/Open-Computer-Use-<version>-macOS-universal.app.zip`
- `dist/release/github/open-computer-use-cli-<version>-linux-{arm64,amd64}.tar.gz`
- `dist/release/github/open-computer-use-cli-<version>-windows-{arm64,amd64}.zip`
- `dist/release/github/open-computer-use-skill.zip`
- `dist/release/github/open-computer-use.skill`
- `dist/release/github/SHA256SUMS`
- `dist/release/github/release-assets-manifest.json`
- `dist/release/cursor-motion/CursorMotion-<version>.dmg`
- the npm and direct-download release artifacts uploaded from GitHub Actions
- the direct-download assets above plus the tag-aligned `CursorMotion-<version>.dmg` on GitHub Releases

In other words, even before the project reaches a more complex deployment
stage, the repository already has a real, reusable npm artifact packaging path and a
git-tag-driven direct-download path covering macOS, Linux, Windows and the skill.
