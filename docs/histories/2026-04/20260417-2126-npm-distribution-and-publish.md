## [2026-04-17 21:26] | Task: Wire up npm distribution and publish

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Help me package this so it can be published to npm, one-click installable as `open-computer-use-mcp`, `open-codex-computer-use-mcp`, or `open-computer-use` — any of these works; the current packaging bar is too high. Publish it directly to the user's npmjs account, then switch to GitHub Actions publishing later.

### 🛠 Changes Overview
**Scope:** `scripts/`, `.github/workflows/`, `docs/`, `README.md`, `package.json`

**Key Actions:**
- **Implemented the npm distribution pipeline**: Added `scripts/npm/build-packages.mjs` and `scripts/npm/publish-packages.mjs`, which can stage and publish the three package names.
- **Upgraded app packaging**: Extended `scripts/build-open-computer-use-app.sh` to support building a universal `Open Computer Use.app` for npm precompiled distribution.
- **Made the npm package independently installable into Codex**: The npm package bundles the plugin directory, marketplace config, and `install-codex-plugin.sh`; after install, `open-computer-use install-codex-plugin` can be run directly.
- **Replaced the release placeholder artifact**: Changed `scripts/release-package.sh` from packaging repo metadata to producing real npm tgz artifacts, and generating a release manifest.
- **Added a GitHub Actions skeleton**: Added `.github/workflows/release.yml`, supporting manual packaging and publishing to npm via `NPM_TOKEN`.
- **Actually published to npm**: Published `open-computer-use@0.1.2`, `open-computer-use-mcp@0.1.2`, `open-codex-computer-use-mcp@0.1.2`.

### 🧠 Design Intent (Why)
The core of this change is shifting "installation cost" from the end user's side to the publishing side. Rather than requiring every user to have a Swift/Xcode build environment, it's better to produce a universal `.app` at publish time and bundle it directly into the npm package, so it runs immediately after install and can be installed straight into the Codex plugin system. This preserves the real build pipeline within the repo while also letting subsequent GitHub Actions reuse the same set of scripts.

### 📁 Files Modified
- `.github/workflows/release.yml`
- `Makefile`
- `README.md`
- `docs/ARCHITECTURE.md`
- `docs/CICD.md`
- `docs/exec-plans/completed/20260417-2115-npm-distribution.md`
- `package.json`
- `scripts/build-open-computer-use-app.sh`
- `scripts/ci.sh`
- `scripts/install-codex-plugin.sh`
- `scripts/npm/build-packages.mjs`
- `scripts/npm/publish-packages.mjs`
- `scripts/release-package.sh`
