# Publish direct-download release assets

Port of the direct-download release assets from the upstream project (iFurySt/open-codex-computer-use), adapted to the
fork's release workflow.

## Changes

- New `scripts/package-github-release-assets.sh` packages the already-built universal `.app` (verified for both
  architectures and `codesign --verify --deep --strict`), the Linux and Windows CLI binaries for arm64 and amd64, and the
  `open-computer-use` skill into `dist/release/github/`, then writes `SHA256SUMS` and `release-assets-manifest.json`. It
  rejects a version that differs from the plugin manifest and checks archive contents.
- `scripts/release-package.sh` calls it after staging and records the asset manifest path in `release-manifest.json`.
  `make release-assets` and `npm run package:release-assets` wrap it.
- `release.yml`: the npm job uploads the direct-download artifacts and, on public repositories, attaches a build
  provenance attestation. GitHub Release creation moved out of the Cursor Motion job into one `publish-github-release`
  job that needs both build jobs, so a release is never published with a partial asset set. The release body still comes
  from `docs/releases/github/<tag>.md`.
- No separate app notarization step: this fork's build script already signs, notarizes and staples the app when the notary
  secrets are present, and the asset script packages that same bundle. Without secrets the zip is ad-hoc signed and not
  notarized.
- Docs: `CICD.md`, `RELEASE_GUIDE.md`, `ARCHITECTURE.md` and the feature release notes describe the new assets.

## Design intent

macOS must ship the whole app bundle to keep a stable permission identity, while Linux and Windows fit per-platform
archives. One publish job gated on every build job avoids a half-populated Release.

## Files modified

- `scripts/package-github-release-assets.sh`
- `scripts/release-package.sh`
- `.github/workflows/release.yml`
- `package.json`
- `Makefile`
- `docs/ARCHITECTURE.md`
- `docs/CICD.md`
- `docs/releases/RELEASE_GUIDE.md`
- `docs/releases/feature-release-notes.md`

## Validation

- Shell syntax, action pinning, docs and repo hygiene checks pass.
