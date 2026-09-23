## [2026-04-20 19:08] | Task: Upgrade the release workflow to Node 24-compatible GitHub Actions versions

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5.4`
* **Runtime**: `Codex CLI on macOS`

### 📥 User Query
> No problem there, now fix this warning issue

### 🛠 Changes Overview
**Scope:** `.github/workflows/`, `docs/`

**Key Actions:**
- **[Action Pin Refresh]**: Updated `actions/setup-node` in `release.yml` to the SHA corresponding to the official `v6.4.0`, and updated `actions/upload-artifact` to the SHA corresponding to the official `v7.0.1`.
- **[Warning Removal]**: Cleared the "Node.js 20 actions are deprecated" warning that GitHub Actions surfaced during the `v0.1.18` release run, avoiding this known noise once runners later default to Node 24.

### 🧠 Design Intent (Why)
The `0.1.18` release already succeeded functionally, but the workflow still depended on old action versions based on Node 20. Since the warning already made clear that runners would later default to Node 24, the pinned SHAs should be bumped to the latest official releases as early as possible, rather than letting this known compatibility risk surface all at once later.

### 📁 Files Modified
- `.github/workflows/release.yml`
- `docs/histories/2026-04/20260420-1908-refresh-node24-compatible-actions.md`
