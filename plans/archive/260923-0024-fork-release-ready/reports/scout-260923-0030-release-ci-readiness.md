# Scout: release + CI readiness for vietairs fork

## 1. `scripts/check-repo-hygiene.sh` requirements

Pure presence check for 17 required paths (`scripts/check-repo-hygiene.sh:7-24`) — no content validation for any of them, `[[ ! -f ... ]]`. The 11 currently-missing files listed by the caller are all in this list.

Two extra content checks beyond presence (`scripts/check-repo-hygiene.sh:29-38`):
- `README.md` must not contain CRLF (`grep -q $'\r'`).
- `CONTRIBUTING.md` must contain the literal string `make check-docs`.

So closing the gap = create 11 empty/stub files with correct paths + make sure `CONTRIBUTING.md` mentions `make check-docs` (that file is itself one of the missing ones, so it's a single stub covering two requirements). Low effort — no schema/lint validation on YAML content, e.g. issue-template YAMLs and workflow YAMLs just need to exist as files.

## 2. `.github/workflows/release.yml`

**Trigger** (`release.yml:3-16`): `push` on tags matching `v*` or `*.*.*`, plus `workflow_dispatch` with `publish_to_npm` (bool) and `npm_tag` (string, default `latest`) inputs.

**Jobs**:
- `release-metadata` (`:19-31`): checks out, sets up Node 24, runs `node ./scripts/validate-github-release-notes.mjs --tag "${RELEASE_TAG}"` only on `push` events — validates the reviewed GitHub Release notes file exists/matches format.
- `package-npm` (`:33-146`, needs `release-metadata`, `runs-on: macos-26`): sets up Node 24 + Go 1.22.x, checks npm CLI is ≥11.5.1 (for trusted publishing), optionally imports a codesign cert from `OPEN_COMPUTER_USE_CODESIGN_P12_BASE64`/`_PASSWORD`/`_KEYCHAIN_PASSWORD`/`_IDENTITY` secrets (falls back to ad-hoc signing + sets `OPEN_COMPUTER_USE_ALLOW_ADHOC_RELEASE=1` if unset), runs `npm run npm:pack` (→ `scripts/release-package.sh`), uploads `dist/release/npm/*.tgz` + manifest as an artifact, then on `push` OR `workflow_dispatch.publish_to_npm` runs `node ./scripts/npm/publish-packages.mjs --skip-build --out-dir dist/release/npm-staging --tag "${NPM_DIST_TAG}"`. Needs `NPM_TOKEN` secret (or GitHub OIDC trusted publishing — no npm token needed if npm registry trusted-publisher is configured for this repo).
- `release-cursor-motion-dmg` (`:148-249`, needs `release-metadata`, only on `push`, `runs-on: macos-26`): builds `CursorMotion-<version>.dmg` via `scripts/build-cursor-motion-dmg.sh`, optionally notarizes with `APPLE_NOTARY_API_KEY_P8_BASE64`/`_KEY_ID`/`_ISSUER_ID`/`APPLE_DEVELOPER_TEAM_ID` secrets (skips notarization if unset), uploads artifact, then publishes to **GitHub Releases** via `gh release create/upload` using `docs/releases/github/${RELEASE_TAG}.md` as the notes file (must exist and be checked in ahead of tagging) and `${{ github.token }}` (no extra secret needed — works against whichever repo the workflow runs in, i.e. the fork, automatically).

**Fork compatibility**: All 4 `actions/*` calls are SHA-pinned (`checkout@93cb6efe...`, `setup-node@48b55a01...`, `setup-go@4a360112...`, `upload-artifact@043fb46d...`) — generic, not upstream-specific, works unchanged on the fork. `gh release` calls use `github.token`/`github.ref_name` — repo-relative, works on the fork unchanged. **No hardcoded owner/repo/npm-scope inside `release.yml` itself.** The one fork-specific piece already handled dynamically is `scripts/validate-github-release-notes.mjs`, which derives the changelog URL from `git remote get-url origin` (falls back to the upstream slug only if no remote) — see `scripts/validate-github-release-notes.mjs:9-11,16-33`. Secrets needed to fully exercise every optional path: `NPM_TOKEN` (or npm trusted publishing), `OPEN_COMPUTER_USE_CODESIGN_*` (4 vars, optional — ad-hoc fallback exists), `APPLE_NOTARY_*` + `APPLE_DEVELOPER_TEAM_ID` (optional — notarization is skipped if absent). None of these are present by default on a fork; the workflow degrades gracefully (ad-hoc signing, unsigned/unnotarized DMG, npm publish attempted with whatever `NPM_TOKEN`/OIDC is configured for THIS repo, not upstream's).

## 3. Release scripts — publish target

- `scripts/release-package.sh` (`:1-40`): wraps `node scripts/npm/build-packages.mjs --configuration release --arch universal --out-dir dist/release/npm-staging`, then `npm pack` each staged package dir into `dist/release/npm`, and writes `dist/release/release-manifest.json` (git sha, artifact list, staging dir). No repo/owner logic itself.
- `scripts/npm/build-packages.mjs`: hardcodes 3 **unscoped** npm package names — `open-computer-use`, `open-computer-use-mcp`, `open-codex-computer-use-mcp` (`:24-28`). Generated `package.json` per package (`renderMetaPackageJson`, `:496-520`) sets `homepage`/`repository.url`/`bugs.url` **all hardcoded to `https://github.com/iFurySt/open-codex-computer-use`** (`:502-509`), and the README template it writes also says `Source repository: https://github.com/iFurySt/open-codex-computer-use` (`:479`). **This is hardwired to upstream** — publishing as-is from the fork would still link back to iFurySt's repo in the npm package metadata/README, unlike `validate-github-release-notes.mjs` which already derives the URL from `origin`. Not a blocker for a *technical* publish, but wrong/misleading metadata for a forked release and worth fixing before shipping npm packages under the fork's own identity.
- Preconditions to actually publish: these are the same **unscoped package names** upstream may already own on npmjs.org. `scripts/npm/publish-packages.mjs` requires `NODE_AUTH_TOKEN` or GitHub OIDC trusted publishing (`:main() ~209-211`), skips publish if `npmPackageVersionExists` for that exact name@version already returns true, and otherwise attempts `npm publish` — if the vietairs npm account doesn't already own `open-computer-use` etc. on the registry (npm names are global, first-come), the publish will fail outright unless upstream explicitly granted access or the fork renames its packages. This is the single biggest release-readiness gap: **no evidence in this repo of package-name ownership resolution for a fork** — it's a runtime npm-registry fact, not discoverable from source.

## 4. `scripts/ci.sh` python3 dependency

Confirmed present (not re-run, per instruction): `scripts/ci.sh` invokes `python3 -m unittest` for `apps/OpenComputerUseLinux`. In this scout's environment `python3` was reported to be SIGKILLed (exit 137); did not attempt to run it. This means `scripts/ci.sh` cannot be exercised end-to-end in this sandbox regardless of the hygiene-file gaps — a separate, environmental blocker from the missing-files gap in item 1.

## 5. `swift build`

Ran `swift build` (no `swift test`). **Builds clean** — `Build complete! (8.03 sec.)`, wall time 9.23s total (well under 5 min). Only warnings, no errors: repeated `'nonisolated(unsafe)' is unnecessary for a constant with 'Sendable' type 'NSImage?'` at `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SoftwareCursorGlyphRenderer.swift:59`. All targets (OpenComputerUseKit, OpenComputerUse, CursorMotion, StandaloneCursor, OpenComputerUseFixture, OpenComputerUseSmokeSuite, and their `-product` variants) built successfully (311 build steps completed).

## 6. `scripts/check-action-pinning.sh`

Ran it directly: **passes**. Output: `GitHub Action 固定 SHA 检查通过` (exit 0). Script logic (`scripts/check-action-pinning.sh:1-19`): greps all `uses:` lines under `.github/workflows`, fails any that aren't pinned to a 40-hex-char SHA. Confirmed manually in item 2 above that all 4 actions in `release.yml` are SHA-pinned. Since `.github/workflows/` contains only `release.yml`, this check currently has a single file to validate and it's already correct.

## Summary — release readiness gap, ranked by effort

1. **Cheapest**: repo-hygiene 11 missing files — pure stub/presence files, ~few minutes (item 1). Unblocks `scripts/ci.sh`'s hygiene gate.
2. **Cheap but consequential**: `scripts/npm/build-packages.mjs` hardcodes `iFurySt/open-codex-computer-use` in 3 places (homepage, repository.url, bugs.url, README text) — should read from git remote like `validate-github-release-notes.mjs` already does, or the fork ships npm packages that point users back to upstream.
3. **Not discoverable from source, needs a runtime check**: whether `vietairs` npm account/org can publish under the existing unscoped package names (`open-computer-use`, `open-computer-use-mcp`, `open-codex-computer-use-mcp`) — if upstream already owns them on npmjs.org, the fork's publish step will fail unless it renames packages or gets added as a maintainer.
4. **Secrets provisioning** (optional, workflow degrades gracefully without them): `NPM_TOKEN`, `OPEN_COMPUTER_USE_CODESIGN_*`, `APPLE_NOTARY_*` — needed only for signed/notarized/real npm-published releases; unsigned ad-hoc + skip-notarize + skip-npm-publish path works with zero secrets.
5. **Environmental, not code**: `scripts/ci.sh`'s `python3 -m unittest` step is unusable in this particular sandbox (SIGKILL/exit 137) — unrelated to fork readiness, would need testing in a normal shell.
6. Swift package build and GitHub Action pinning are both already clean — no work needed there.

## Unresolved questions

- Does the `vietairs` npm account/org already own (or have publish rights to) `open-computer-use`, `open-computer-use-mcp`, `open-codex-computer-use-mcp` on npmjs.org, or does the fork need to rename/scope its packages before the `package-npm` job's publish step can succeed?
- Is `docs/releases/github/${RELEASE_TAG}.md` (required by `release-cursor-motion-dmg`'s `gh release create/edit --notes-file`) already the fork's convention, and does one exist for whatever tag would be pushed first?
- Should `scripts/npm/build-packages.mjs`'s hardcoded upstream URLs be fixed as part of this readiness pass, or is publishing to npm out of scope for this fork's first release (e.g. GitHub Releases / DMG only)?

Status: DONE
