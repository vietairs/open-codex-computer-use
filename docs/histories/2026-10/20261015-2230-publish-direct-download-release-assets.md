# Publish direct-download release assets

Port of the direct-download release assets from the upstream project (iFurySt/open-codex-computer-use), adapted to the
fork's release workflow.

## Changes

- New `scripts/package-github-release-assets.sh` packages the already-built universal `.app` (verified for both
  architectures and `codesign --verify --deep --strict`), the Linux and Windows CLI binaries for arm64 and amd64, and the
  `open-computer-use` skill into `dist/release/github/`, then writes `SHA256SUMS` and `release-assets-manifest.json`. It
  rejects a version that differs from the plugin manifest and checks archive contents. Linux CLI tarballs are created
  with `tar --no-xattrs --no-acls --no-fflags --no-mac-metadata`, so no extended-attribute pax headers or AppleDouble
  entries leak in; the raw archive headers were inspected, not only the file listing.
- `--output-dir` is guarded because it is wiped before packaging: it must resolve (symlinks followed through the nearest
  existing ancestor, before anything is created) to a strict subdirectory of the repository, outside `.git`, and must not
  be, contain or lie inside the app bundle, the native runtimes or the staged skill directory. An existing directory is
  wiped only when it is empty or holds the `.ocu-release-assets` marker file written by an earlier run; the marker is
  excluded from `SHA256SUMS` and the manifest. Relative paths resolve against the repository root and a leading `./` is
  accepted.
- `scripts/release-package.sh` calls it after staging and records the asset manifest path in `release-manifest.json`.
  `make release-assets` and `npm run package:release-assets` wrap it.
- `release.yml`: the npm job uploads the direct-download artifacts and, on public repositories and tag pushes only,
  attaches a build provenance attestation. Workflow permissions are read-only by default; `id-token` and `attestations`
  write are granted on the npm job and `contents: write` only on the publish job, whose checkout does not persist git
  credentials because it publishes through `gh` with the job token. GitHub Release creation moved out of the Cursor Motion job into one `publish-github-release`
  job that needs both build jobs, so a release is never published with a partial asset set. The release body still comes
  from `docs/releases/github/<tag>.md`.
- No separate app notarization step: this fork's build script already signs, notarizes and staples the app when the notary
  secrets are present, and the asset script packages that same bundle. Without secrets the zip is ad-hoc signed and not
  notarized.
- Docs: `CICD.md`, `RELEASE_GUIDE.md`, `ARCHITECTURE.md` and the feature release notes describe the new assets. The
  release guide documents the Gatekeeper quarantine behavior of an ad-hoc or non-notarized zip, the
  `OPEN_COMPUTER_USE_ALLOW_ADHOC_RELEASE=1` override that local ad-hoc release builds need, and the output-directory
  marker behavior; the GitHub Release notes template gained a macOS download note.

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
- `docs/releases/github/TEMPLATE.md`

## Validation

- Shell syntax, shellcheck, workflow YAML parse, action pinning, docs and repo hygiene checks pass.
- A scratch repository copy with a fake build tree confirms that `--output-dir` pointing at `.git`, `docs`, a symlink
  into `.git` and the app bundle internals is refused with contents intact, that `./out`, `out/` and the default
  location work, and that a second run into the same marked directory succeeds.
