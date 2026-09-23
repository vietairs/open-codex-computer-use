## [2026-04-22 12:05] | Task: Fix the 0.1.27 release npm publish failure

### Background

- The GitHub Actions release triggered by the `v0.1.27` tag failed in the `package-npm` job.
- The failure point was `Publish packages to npm`: the registry's publish PUT for `open-codex-computer-use-mcp@0.1.27` returned 404; the Cursor Motion DMG job in the same run had already succeeded.
- The npm registry still showed `0.1.26` for all three packages, but not `0.1.27`.

### Changes

- **[Publish Recovery]**: before publishing each staged package, `scripts/npm/publish-packages.mjs` now checks with `npm view <name>@<version>` whether the same version already exists; if so, it skips it directly.
- **[Auth Preference]**: when GitHub Actions exposes OIDC, prefer `--provenance` and npm trusted publishing; no longer force-clear the OIDC environment just because an `NPM_TOKEN` fallback exists — the token is now only a fallback.
- **[Trusted Publishing CLI]**: the release workflow's npm package job now uses Node `24`, and checks the npm CLI is at least `11.5.1` before publishing, to satisfy npm trusted publishing's requirements.
- **[Retry]**: after an npm publish failure, retry up to 3 times, re-checking after each failure whether the version has since become visible on the registry, to cover transient registry errors or partial-publish scenarios.
- **[Release Guide]**: added guidance to the release guide on how to troubleshoot npm publish 404s, and how the script handles an already-existing version when a tag is re-pushed.

### Verification

- Passed: `node ./scripts/npm/build-packages.mjs --skip-build --out-dir dist/release/npm-staging-check`, staging package version was `0.1.27`
- Passed: `node ./scripts/npm/publish-packages.mjs --skip-build --out-dir dist/release/npm-staging-check --dry-run`
- Passed: `node --check scripts/npm/publish-packages.mjs`
- Passed: `swift test`

### Files Affected

- `scripts/npm/publish-packages.mjs`
- `docs/releases/RELEASE_GUIDE.md`
- `docs/histories/2026-04/20260422-1205-harden-npm-release-retry.md`
