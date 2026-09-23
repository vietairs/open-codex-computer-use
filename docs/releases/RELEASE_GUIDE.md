# Release Guide

This document governs this repository's patch / minor release process. Its goal is to avoid a repeat of the "git tag already pushed, but the npm staging artifact still carries the old version" kind of version-source mismatch.

## When you must read this first

- Read this document before doing any of these:
  - bumping the version
  - cutting a release tag
  - pushing a release tag
  - looking into why a GitHub Actions release run failed
  - re-cutting a failed release

## When to actually publish a public release

- For everyday fixes, official `computer-use` parity verification, and local regression testing, default to building the local app / binaries only and pointing the MCP client at the local build.
- Do not treat a patch release as a routine verification step; only move to the release checklist below once the user explicitly asks for a public release, or a fix has reached a stability level that needs to ship to external users.
- If the only goal is to have Codex use the latest local implementation, prefer updating the `open-computer-use` MCP server command in your local `~/.codex/config.toml` to point at the repo's local build artifact, instead of bumping the version, tagging, and releasing.

## Current release entry points

- Local staging / tgz packaging: `./scripts/release-package.sh`
- Local Cursor Motion DMG build: `./scripts/build-cursor-motion-dmg.sh --configuration release --arch universal --version <version>`
- Local npm package staging directory: `node ./scripts/npm/build-packages.mjs`
- Local publish: `node ./scripts/npm/publish-packages.mjs`
- CI workflow: `.github/workflows/release.yml`
- User-facing release log: `docs/releases/feature-release-notes.md`
- GitHub Release body: `docs/releases/github/vX.Y.Z.md`
- GitHub Release page: the workflow creates or updates the release using the reviewed English notes file; it does not derive the body from PR titles.

## Current version sources

This repository currently has three release version sources:

- npm staging package version: taken from `version` in `plugins/open-computer-use/.codex-plugin/plugin.json`.
- GitHub Release body: taken from `docs/releases/github/<tag>.md`; the file name must exactly match the actual tag.
- `CursorMotion-<version>.dmg` file name and the GitHub Release asset version: taken from the release tag; the workflow normalizes `vX.Y.Z` to `X.Y.Z` for the DMG file name, or you can pass `--version` explicitly for a local build.

In other words:

- Changing only the git tag, without changing this manifest, does not produce a new npm version.
- `scripts/npm/build-packages.mjs` reads the version from this manifest and generates three root/alias staging packages; each package bundles macOS, Linux, and Windows runtime artifacts.
- So the manifest must be bumped to the target version before releasing.
- If the English notes for the target tag are missing, or the notes are inconsistent with the manifest/tag, the `release-metadata` job fails before the npm and DMG jobs start.
- To get the `CursorMotion` DMG file name and release page asset name to land on the target version, you must push using the target tag, or pass the same `--version` explicitly locally.

## Release Checklist

### 1. Unify the version number first

At minimum, check and sync these locations:

- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `apps/OpenComputerUseLinux/main.go`
- `apps/OpenComputerUseWindows/main.go`
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/README.md`
- `docs/releases/feature-release-notes.md`
- `docs/releases/github/vX.Y.Z.md`
- the history entry under `docs/histories/` for this release

If this release also touches other externally visible version strings, sync those too; do not do a partial update.

### 2. Prepare and validate the GitHub Release notes

Create the file for the target tag from `docs/releases/github/TEMPLATE.md`, then run:

```bash
node ./scripts/validate-github-release-notes.mjs --tag v0.1.14
```

Validation requirements:

- The tag must be `vX.Y.Z` or `X.Y.Z`, and must match the plugin manifest version.
- The body must start with `## What's Changed` and include 1-3 user-facing changes in English.
- The body must not contain CJK characters.
- The body must contain exactly one `Full Changelog` link pointing at the current tag.

Do not tag until every item passes. After the tag is pushed, the `release-metadata` job re-runs the same validation and blocks the npm and DMG jobs on failure.

### 3. Verify locally that the version sources took effect

Run at least these four steps:

```bash
node ./scripts/validate-github-release-notes.mjs --tag v0.1.14
swift test
node ./scripts/npm/build-packages.mjs --out-dir dist/release/npm-staging-check
./scripts/build-cursor-motion-dmg.sh --configuration release --arch universal --version 0.1.14
```

Then check the staging package version and DMG file name directly:

```bash
node -p "require('./dist/release/npm-staging-check/open-computer-use/package.json').version"
test -x "dist/release/npm-staging-check/open-computer-use/dist/linux/arm64/open-computer-use"
test -f "dist/release/npm-staging-check/open-computer-use/dist/windows/arm64/open-computer-use.exe"
test -x "dist/release/npm-staging-check/open-computer-use/bin/ocu"
node -e "const bin=require('./dist/release/npm-staging-check/open-computer-use/package.json').bin; if (bin.ocu !== 'bin/ocu') process.exit(1)"
node -e "if (require('./dist/release/npm-staging-check/open-computer-use/package.json').optionalDependencies) process.exit(1)"
ls dist/release/cursor-motion/CursorMotion-0.1.14.dmg
```

If what prints here is not the target version, or the DMG was not produced under the target version name, do not tag.

If the current checkout already has a `dist/Open Computer Use.app` matching the target version, you may temporarily add `--skip-build` to skip a redundant build; but do not add this flag by default on a clean checkout, or the staging script will fail from a missing `dist/Open Computer Use.app`.

### 4. Commit the version bump

- Submit the release version bump as its own commit.
- The commit message should make clear this is a release close-out, not a regular feature commit.

### 5. Tag and push

Current convention is `vX.Y.Z`:

```bash
git tag -a v0.1.14 -m "v0.1.14"
git push origin main
git push origin v0.1.14
```

After the tag push, `.github/workflows/release.yml` automatically does two things:

- Publishes the npm packages.
- Builds `CursorMotion-0.1.14.dmg`, and creates or updates the GitHub Release asset for the matching tag.

### 6. Check the GitHub Release notes

After every tag push, check the GitHub Release page; do not just confirm the workflow went green:

```bash
gh release view v0.1.14 --json body,url
```

The workflow creates a new Release using `docs/releases/github/<tag>.md`; if the Release already exists, it overwrites the uploaded DMG and updates the body from the same file. GitHub's auto-generated notes are no longer the source of the body, so PR titles written in Chinese do not affect the language of the public Release.

Minimum requirements:

- The release body must match the target notes file in the repository.
- `What's Changed` must list 1-3 user-facing changes in English for this release.
- The `Full Changelog` link must be preserved.

## Notarization

`scripts/build-open-computer-use-app.sh` notarizes `Open Computer Use.app` with `xcrun notarytool` and staples the ticket. `OPEN_COMPUTER_USE_NOTARIZE=auto|required|skip` (default `auto`) controls it:

- `auto` notarizes **release** builds only, and only when the bundle will be signed with a "Developer ID Application" identity and credentials resolve. Anything else skips notarization with one line on stderr; debug builds skip silently.
- `required` notarizes any configuration and fails the build when the identity is not Developer ID Application or no credentials resolve.
- `skip` never notarizes.

The script makes this decision once, before signing. A 40-hex SHA-1 value in `OPEN_COMPUTER_USE_CODESIGN_IDENTITY` is mapped to its certificate name through `security find-identity` (using `OPEN_COMPUTER_USE_CODESIGN_KEYCHAIN` when set), so a hash-pinned Developer ID identity is recognized. `codesign` receives `--timestamp` only when the build will be notarized; every other signed build gets `--timestamp=none`, so debug builds, `skip`, and credential-less `auto` builds never contact Apple and keep working offline. After signing, the script confirms that `codesign -dvv` reports `Authority=Developer ID Application:` before it submits; in `required` mode a mismatch fails the build.

### One-time local setup

Store a keychain profile once per machine:

```bash
xcrun notarytool store-credentials open-computer-use-notary --apple-id <your-apple-id> --team-id 3HB354R355
```

You will be prompted for an app-specific password for that Apple ID. A local `auto` release build then picks up this profile automatically. `required` mode never probes for it, so set it explicitly:

```bash
OPEN_COMPUTER_USE_NOTARIZE=required OPEN_COMPUTER_USE_NOTARY_PROFILE=open-computer-use-notary \
  ./scripts/build-open-computer-use-app.sh --configuration release
```

### Environment variables (local / CI)

Credentials are resolved in this order, first match wins:

1. `OPEN_COMPUTER_USE_NOTARY_PROFILE=<keychain profile name>`: an explicit keychain profile.
2. An App Store Connect API key: `APPLE_NOTARY_KEY_PATH=/path/to/key.p8` (must exist and be readable) or `APPLE_NOTARY_API_KEY_P8_BASE64=<base64-encoded .p8 contents>`, together with `APPLE_NOTARY_KEY_ID` and `APPLE_NOTARY_ISSUER_ID` (`APPLE_DEVELOPER_TEAM_ID` optional). A base64 key is decoded into a `0600` temporary file that is removed when the script exits; invalid base64 or an empty result fails the build.
3. In `auto` mode only, and only for a release build signed with Developer ID, when neither of the above is set: the keychain profile `open-computer-use-notary`, if `xcrun notarytool history` can use it.

### CI secrets

The `package-npm` job in `.github/workflows/release.yml` uses these secrets:

- `APPLE_NOTARY_API_KEY_P8_BASE64`
- `APPLE_NOTARY_KEY_ID`
- `APPLE_NOTARY_ISSUER_ID`
- `APPLE_DEVELOPER_TEAM_ID` (optional)

The "Prepare Open Computer Use notarization config" step only chooses the mode and writes nothing else to `GITHUB_ENV`:

- All three required secrets set: `OPEN_COMPUTER_USE_NOTARIZE=required`, so a release that cannot be notarized (for example, because no Developer ID signing certificate is configured) fails instead of shipping unnotarized.
- None set: `OPEN_COMPUTER_USE_NOTARIZE=auto` plus a `::notice::`. The release proceeds without notarization.
- Some but not all set: the step fails with an `::error::` naming the missing secret(s).

The secret values are passed as `env:` only to the "Build npm release artifacts" step, where the build script decodes the key itself.

### Submission and stapling

The script zips the bundle with `ditto`, then runs `xcrun notarytool submit --wait --output-format json`. It reads stdout (JSON) and stderr separately and treats only `"status": "Accepted"` as success; any other status fails the build even when `notarytool` exits 0. On failure it prints the submission id and status and fetches `xcrun notarytool log <id>`. After acceptance, `xcrun stapler staple` is tried up to 3 times (waiting 10s, then 20s) to allow for ticket propagation. `xcrun stapler validate` is fatal, and `spctl -a -vvv -t exec` is printed as evidence only.

### Verification

After a notarized build, confirm the ticket is valid:

```bash
xcrun stapler validate "dist/Open Computer Use.app"
spctl -a -vvv -t exec "dist/Open Computer Use.app"
codesign -dvv "dist/Open Computer Use.app" 2>&1 | grep -E '^(Authority|Timestamp)='
```

A notarized bundle shows a `Timestamp=` line. A Developer ID build that was not notarized shows only `Signed Time=`.

## Debugging a release failure

### 1. Check the latest run first

```bash
gh run list -R vietairs/open-codex-computer-use --limit 10
gh run view -R vietairs/open-codex-computer-use <run-id> --log-failed
```

### 2. Focus on which category of error

- `release-metadata` failure
  - Run `node ./scripts/validate-github-release-notes.mjs --tag <tag>` locally first.
  - Check whether `docs/releases/github/<tag>.md` exists, whether the manifest version matches, whether the body contains CJK characters, and whether `Full Changelog` points at the current tag.
- `npm error 403 ... You cannot publish over the previously published versions`
  - Usually not a token permission issue; the staging package version is still the old one.
  - Check `plugin.json`'s `version` first, then check the actual `package.json` produced by the staging package.
- `npm error 404 Not Found - PUT https://registry.npmjs.org/<package>`
  - First confirm whether the target package's old version is still visible on the registry: `npm view <package> versions --json`.
  - The current publish script skips a package version that already exists before publishing, and does a short retry on publish failure; if GitHub Actions OIDC is available, it prefers `--provenance` trusted publishing, then falls back to `NODE_AUTH_TOKEN`. If a package was already partially published successfully before a tag re-push, re-running the same release will not abort just because that package already exists.
- `npm error need auth ... You need to authorize this machine using npm adduser`
  - If the log shows `GitHub Actions OIDC trusted publishing` was selected, check the npm CLI version in CI first; trusted publishing needs npm `11.5.1+`; the current release workflow's npm package job uses Node `24` and explicitly checks the npm version.
  - If the npm CLI version satisfies the requirement and this error still appears, it means the npmjs.com package side has not yet configured this GitHub repo / workflow file as a trusted publisher.
- Build-stage failure
  - Check `Build npm release artifacts`, `Build Cursor Motion DMG`, or Swift compilation errors first.
- GitHub Release asset upload failure
  - Check `Publish Cursor Motion DMG to GitHub Releases` first, confirm the tag exists, `GH_TOKEN` permissions are correct, and the generated `CursorMotion-<version>.dmg` path matches.
- Publish authentication failure
  - Check `.github/workflows/release.yml`, `scripts/npm/publish-packages.mjs`, and the npm trusted publishing / token fallback configuration.

## Current known boundaries

- `Open Computer Use` npm release artifacts still fall back to ad-hoc signing when `OPEN_COMPUTER_USE_CODESIGN_P12_BASE64` / `OPEN_COMPUTER_USE_CODESIGN_P12_PASSWORD` and related secrets are not configured; when configured, the workflow imports the `Developer ID Application` certificate first, then signs uniformly with that identity, and (with notary secrets also configured) notarizes and staples the app bundle.
- `Cursor Motion`'s current release asset reuses `OPEN_COMPUTER_USE_CODESIGN_*` to sign the app with `Developer ID Application` first; if `APPLE_NOTARY_API_KEY_P8_BASE64`, `APPLE_NOTARY_KEY_ID`, `APPLE_NOTARY_ISSUER_ID`, `APPLE_DEVELOPER_TEAM_ID` are also configured, the workflow proceeds to notarize and staple the `.dmg`.
- If the secrets above are missing, the workflow falls back to ad-hoc signing or skips notarization respectively, rather than blocking the whole release.
- The `open-computer-use` npm root package bundles six `os-arch` native artifacts, so the package size is larger than a macOS-only build; before releasing, confirm the staging package includes `dist/Open Computer Use.app`, `dist/linux/`, and `dist/windows/`, and confirm the launcher does not declare `optionalDependencies`.

## If the tag was already pushed wrong

If the remote tag already points at the wrong commit, delete the tag first, fix the version sources, then re-tag.

Delete locally:

```bash
git tag -d v0.1.14
```

Delete on the remote:

```bash
git push origin :refs/tags/v0.1.14
```

Once fixed, recreate and push the same-named tag.

## Documentation sync requirements

Every release must sync at least these three kinds of documents:

- `docs/releases/feature-release-notes.md`
- `docs/releases/github/vX.Y.Z.md`
- the matching release history under `docs/histories/`
- this `docs/releases/RELEASE_GUIDE.md`, if the release process itself changed

If a release surfaces a new process pitfall, do not just remember it in chat; add it to this document directly.
