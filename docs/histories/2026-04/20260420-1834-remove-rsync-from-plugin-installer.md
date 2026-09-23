## [2026-04-20 18:34] | Task: Remove the plugin installer's dependency on rsync

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Why is there an `rsync`? What's it for?
>
> Swap it out — Node's `cpSync` will work.

### 🛠 Changes Overview
**Scope:** `scripts/`

**Key Actions:**
- **Removed the `rsync` dependency**: `scripts/install-codex-plugin.sh` no longer calls out to external `rsync` to copy the plugin directory and `.app` bundle.
- **Extended the shared helper**: added a `copy-into-dir` subcommand to `scripts/install-config-helper.mjs` that uses Node's `cpSync` to recursively copy multiple source paths into a target directory.
- **Kept install behavior unchanged**: the plugin cache directory structure and the subsequent `config.toml` write logic stay the same; only the host command prerequisite is tightened.

### 🧠 Design Intent (Why)
`rsync` was never a business-required capability here — it was just the implementation vehicle for "recursively copy a directory." Since `open-computer-use`'s npm distribution path already takes Node as a natural prerequisite, there's no need for `install-codex-plugin` to carry an extra system-command dependency. Switching to `cpSync` makes the installer's runtime prerequisites more consistent, and it's in line with the earlier direction of removing the Python dependency.

### ✅ Verification
- `node --check scripts/install-config-helper.mjs`
- Ran `./scripts/install-codex-plugin.sh --configuration release` under a temporary `CODEX_HOME`
- `node ./scripts/npm/build-packages.mjs --skip-build --package open-computer-use --out-dir dist/tmp/npm-stage-check`
- `rg -n "rsync" dist/tmp/npm-stage-check/open-computer-use -S`

### 📁 Files Modified
- `scripts/install-codex-plugin.sh`
- `scripts/install-config-helper.mjs`
