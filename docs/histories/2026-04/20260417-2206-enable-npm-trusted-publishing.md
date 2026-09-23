## [2026-04-17 22:06] | Task: Enable npm Trusted Publishing

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Trusted Publishing has already been saved on npmjs; handle `.github/workflows/release.yml`.

### 🛠 Changes Overview
**Scope:** `.github/workflows/`, `scripts/npm/`, `README.md`, `docs/`

**Key Actions:**
- **Updated workflow permissions**: added `id-token: write` to `release.yml`, to satisfy npm Trusted Publishing's OIDC requirement.
- **Removed token dependency**: dropped the workflow's dependency on the `NPM_TOKEN` secret.
- **Relaxed publish script validation**: made `scripts/npm/publish-packages.mjs` no longer strictly require `NODE_AUTH_TOKEN` in the GitHub Actions OIDC scenario.
- **Synced docs**: updated the publishing instructions in README and the CI/CD docs to the Trusted Publishing path.

### 🧠 Design Intent (Why)
The core of Trusted Publishing is short-lived OIDC credentials, so the workflow should no longer depend on a long-lived npm token. Changing just the workflow wasn't enough, because the repo's own publish script would previously fail outright without `NODE_AUTH_TOKEN`, so the script and docs needed to converge on the same publishing model together.

### 📁 Files Modified
- `.github/workflows/release.yml`
- `README.md`
- `docs/CICD.md`
- `scripts/npm/publish-packages.mjs`
