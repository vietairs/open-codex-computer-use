## [2026-04-17 22:15] | Task: Fix the app bundle display name and icon

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5.4`
* **Runtime**: `Codex CLI on macOS`

### 📥 User Query
> The System Settings `Accessibility` and `Screen *` lists currently show `OpenComputerUse` with no logo; it needs to become `Open Computer Use`, and it needs a logo.

### 🛠 Changes Overview
**Scope:** `scripts/`, `plugins/open-computer-use`, `docs/`

**Key Actions:**
- **[Bundle Identity]**: Switched the build artifact from `OpenComputerUse.app` to `Open Computer Use.app`, so macOS System Settings reads the bundle display name with a space in it.
- **[Bundle Icon]**: Added a build-time icon rendering script that generates an `icns` and writes it into the app bundle, then exposes it to the system permission panels via `CFBundleIconFile`.
- **[Packaging and Docs]**: Synced the bundle path across the plugin launcher, Codex install script, npm staging, and docs, so the packaging chain stops referencing the old name.

### 🧠 Design Intent (Why)
The name System Settings shows in these two TCC permission lists is closer to the app bundle's file name than to `CFBundleDisplayName` alone. So changing just `Info.plist` wasn't enough — the actual `.app` name had to be changed to the spaced version, and a real bundle icon resource added, to fix both the no-space name and the blank icon at the same time.

### 📁 Files Modified
- `scripts/build-open-computer-use-app.sh`
- `scripts/render-open-computer-use-icon.swift`
- `scripts/install-codex-plugin.sh`
- `scripts/npm/build-packages.mjs`
- `plugins/open-computer-use/scripts/launch-open-computer-use.sh`
- `README.md`
- `docs/CICD.md`
- `docs/exec-plans/active/20260417-permission-onboarding-app.md`
- `docs/histories/2026-04/20260417-2215-fix-bundle-display-name-and-icon.md`
