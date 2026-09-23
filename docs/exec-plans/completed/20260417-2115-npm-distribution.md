# npm Distribution and Release Execution Plan

## Goal

Make `open-computer-use`, this local macOS `computer-use` MCP server, directly distributable as an npm package, so users can install it via any of the package names `open-computer-use`, `open-computer-use-mcp`, or `open-codex-computer-use-mcp` and get a ready-to-run precompiled artifact plus a Codex plugin install entry point.

## Scope

- In scope:
  - Add a real, publishable npm packaging and release script set to the repo.
  - Produce a directly installable precompiled `.app` distribution artifact, not just source.
  - Support publishing the same content under three npm package names.
  - Update the README, release packaging scripts, history, and other repo docs.
- Out of scope:
  - Full code signing / notarization.
  - Automatically modifying the user's system permission settings.
  - Windows / Linux support.

## Background

- Related docs:
  - `docs/ARCHITECTURE.md`
  - `docs/CICD.md`
  - `docs/SECURITY.md`
  - `docs/SUPPLY_CHAIN_SECURITY.md`
- Related code paths:
  - `scripts/build-open-computer-use-app.sh`
  - `scripts/release-package.sh`
  - `scripts/install-codex-plugin.sh`
  - `plugins/open-computer-use/`
- Known constraints:
  - The repo's main body is currently a Swift executable, not a Node project.
  - The existing release packaging script is still a placeholder implementation, not representative of a real build artifact.
  - npm distribution should minimize the barrier to entry and must not require users to install a local Swift build toolchain.

## Risks

- Risk: shipping only a source wrapper still leaves the install barrier to the user.
- Mitigation: the npm package directly bundles the precompiled `.app` and CLI wrapper.

- Risk: shipping only a single-architecture binary would leave some macOS users unable to run it after install.
- Mitigation: prefer producing a universal macOS binary; if that isn't possible, at least explicitly restrict the platform in npm metadata.

- Risk: Codex plugin installation still depending on the source repo path would weaken the value of the npm package.
- Mitigation: have the npm package itself contain the plugin directory and install script, so it can complete installation independently.

## Milestones

1. Research and converge on an approach.
2. Phased implementation.
3. Verification, delivery, and wrap-up.

## Verification

- Commands:
  - `./scripts/build-open-computer-use-app.sh release --arch universal`
  - `node ./scripts/npm/build-packages.mjs`
  - `npm pack --dry-run`
  - `swift test`
- Manual checks:
  - After unpacking, confirm every npm package includes `dist/Open Computer Use.app`, a CLI alias, and the Codex plugin directory.
  - Locally run `doctor` / `mcp` via the command bundled inside the package.
- Observational checks:
  - Before npm publish, confirm each package name has been staged into an independent directory with a consistent version.

## Progress Log

- [x] Milestone 1
- [x] Milestone 2
- [x] Milestone 3

## Decision Log

- 2026-04-17: npm distribution does not do "compile locally at install time"; it instead prioritizes a "precompile at publish time, ready to use at install time" approach, with the goal of moving the Swift/Xcode barrier from the end user to the publish pipeline.
- 2026-04-17: the `.app` distribution artifact was changed to a universal binary, covering both `arm64` and `x86_64`, so the npm package doesn't lock Intel Mac users out.
- 2026-04-17: the npm package internally keeps a minimal repo mirror, including `.agents/plugins/marketplace.json`, `plugins/open-computer-use/`, `dist/Open Computer Use.app`, and `scripts/install-codex-plugin.sh`, so the package itself can independently complete Codex plugin installation.
- 2026-04-17: added `.github/workflows/release.yml`; subsequent GitHub Actions runs follow this real build chain based on the repo's own `scripts/release-package.sh` and `scripts/npm/publish-packages.mjs`, rather than standing up a separate release script.
