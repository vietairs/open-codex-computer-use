# npm identity rescope + fork plugin identity — report

Worktree: `.claude/worktrees/fork-release-ready` (branch `chore/fork-release-ready`). Files touched: only the two assigned.

## A. Rescope meta package names (scripts/npm/build-packages.mjs)

- `:24-28` `metaPackageNames` renamed to `@vietairs/open-computer-use`, `@vietairs/open-computer-use-mcp`, `@vietairs/open-codex-computer-use-mcp`.
- `packageNames` (`:71-73`, unchanged shape) now carries the scoped names through arg parsing, `--package` validation, and `printHelp()` — verified via `--help` output.
- Only one path segment ever used `packageName` directly: `stageMetaPackage`'s `packageRoot = path.join(outDir, packageName)` (was `:598`, now `:632`). A scoped name contains `/`, which `path.join` would silently split into two nested dirs. Added `packageDirName(packageName)` (new function, after `metaPackageNames`) that strips the leading `@` and replaces `/` with `-` (e.g. `@vietairs/open-computer-use` → `vietairs-open-computer-use`), and `stageMetaPackage` now does `path.join(outDir, packageDirName(packageName))`.
- No separate platform/native sub-packages exist in this script — `packageNames = [...metaPackageNames]` is the only package list; the three meta packages bundle runtimes for all 6 os/cpu targets directly. Nothing else to rescope.
- Bin command names (`open-computer-use`, `ocu`, `open-computer-use-mcp`, `open-codex-computer-use-mcp`) and the launcher's install-command names are fixed strings unrelated to the npm package name — left unchanged, correct.

## B. publishConfig for scoped packages

- Already present at `renderMetaPackageJson` (`:512-514` pre-edit, unaffected by this diff): `"publishConfig": { "access": "public" }`. Pre-existing in the repo before this task — verified with `git log -p`-equivalent read; the current worktree HEAD already had it. No platform sub-packages exist, so nothing else needs it. Confirmed present in the staged output's `package.json`.

## C. Fork-derived repository URLs in generated metadata

- Hardcoded `https://github.com/iFurySt/open-codex-computer-use` removed from: README template `Source repository:` line (was `:479`), and `renderMetaPackageJson`'s `homepage`, `repository.url`, `bugs.url` (was `:502-509`).
- Added `resolveRepositoryURL()` (new function, mirrors `scripts/validate-github-release-notes.mjs:15-34`): reads `OPEN_COMPUTER_USE_RELEASE_REPO_URL` env override first, else `git remote get-url origin`, parsed via the same `github\.com[:/](.+?)(?:\.git)?$` regex, else falls back to the upstream `iFurySt` URL. No hardcoded `vietairs` string in the script.
- `renderReadme` and `renderMetaPackageJson` now take a `repositoryURL` param; `main()` computes it once via `resolveRepositoryURL()` and threads it through `stagePackage` → `stageMetaPackage`.
- Note: npmjs.com package-page URLs in `renderPostinstall`/`renderReadme` (`https://www.npmjs.com/package/${packageName}`) were left untouched — the npm URL format for scoped packages is identical (`npmjs.com/package/@scope/name`), so no fix was needed there.

## D. plugins/open-computer-use/.codex-plugin/plugin.json

- `homepage` (`:9`) and `repository` (`:10`): `iFurySt` → `vietairs`.
- `interface.websiteURL` (`:31`): `iFurySt` → `vietairs`.
- `interface.privacyPolicyURL` (`:32`) and `interface.termsOfServiceURL` (`:33`): repointed to `vietairs/.../SECURITY.md` and `vietairs/.../LICENSE` (same relative paths, this fork's repo).
- `author.name`/`author.url` (`:6-7`, "Leo" / `github.com/iFurySt`) and `interface.developerName` (`:24`, "Leo") left unchanged — correct attribution.
- `name`, `version` unchanged. No `com.ifuryst.*` bundle identifiers present in this file (none to touch).

## Verification performed

1. `node --check scripts/npm/build-packages.mjs` → syntax OK.
2. `node -e "JSON.parse(readFileSync('plugin.json'))"` → parses OK.
3. `node ./scripts/npm/build-packages.mjs --help` → lists the three `@vietairs/...` names.
4. `--skip-build --out-dir /private/tmp/npm-stage-test --package @vietairs/open-computer-use`: staged as far as `copyBundledRuntimes`, which correctly threw "Missing artifact ... dist/Open Computer Use.app" — expected, since no build artifacts exist in this environment and none were built (offline). This confirmed the package directory was created as the flat, sanitized `vietairs-open-computer-use` (not a nested `@vietairs/open-computer-use` split by `/`).
5. To verify the full metadata path end-to-end, created empty placeholder files matching `runtimeTargets[].executablePath` under a temp `/private/tmp/fake-dist`, symlinked it to the worktree's `dist` (`ln -s`), reran the same command with `--out-dir /private/tmp/npm-stage-test2` — staging completed successfully. Inspected the generated `package.json`: `name: "@vietairs/open-computer-use"`, `publishConfig.access: "public"`, `homepage`/`repository.url`/`bugs.url` all `github.com/vietairs/open-codex-computer-use`. Generated `README.md`'s `Source repository:` line also points at `vietairs`. Removed the `dist` symlink and all `/private/tmp` scratch dirs afterward; confirmed `git status` shows no changes outside the two assigned files.

All four tasks verified working end-to-end except the actual native binary build (blocked by lacking a real build toolchain in this sandbox, not by the renamed/URL logic — stubbed with empty files to prove the staging path).

## Unresolved questions

- None.

Status: DONE
Summary: Rescoped the three npm meta packages to `@vietairs/...` with a dir-safe staging path, confirmed `publishConfig.access:"public"` was already present, replaced hardcoded upstream URLs in generated package metadata with a git-remote-derived resolver (no hardcoded `vietairs`), and repointed the fork-identity fields in `plugin.json` to vietairs while preserving Leo/iFurySt authorship — verified end-to-end with a stubbed staging run.
