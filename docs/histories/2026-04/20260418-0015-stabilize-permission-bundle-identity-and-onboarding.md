## [2026-04-18 00:15] | Task: Lock down the permission bundle identity and simplify the onboarding lifecycle

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5.4`
* **Runtime**: `Codex CLI on macOS`

### 📥 User Query
> Change the bundle identifier to `com.ifuryst.opencomputeruse`, and use it going forward; permissions should be keyed on the path from an `npm install -g open-computer-use` install. Also, once everything is already authorized, don't keep popping up onboarding repeatedly — the window should close automatically once authorization is complete.

### 🛠 Changes Overview
**Scope:** `apps/OpenComputerUse`, `packages/OpenComputerUseKit`, `scripts/`, `docs/`

**Key Actions:**
- **[Bundle Identity]**: Unified the app bundle identifier from `dev.opencodex.OpenComputerUse` to `com.ifuryst.opencomputeruse`, and updated the packaging artifact verification logic to match.
- **[Onboarding Lifecycle]**: Both default launch and `doctor` now check permissions first; if both are already granted, onboarding no longer pops up. Once both permissions are completed within the window, it now closes and exits the app automatically.
- **[Stable Permission Target]**: Docs and the permission-detection logic now consistently emphasize that the `Open Computer Use.app` from an npm global install is the long-term authorization target, avoiding treating the source repo's temporary `dist` path as the final stable identity.
- **[NPM Path Priority]**: When launched from source, permission detection and the drag-and-drop target now prefer looking for `Open Computer Use.app` in the npm global install directory; it only falls back to the repo's `dist/` when there's no global install artifact, further reducing the chance that a dev-time path participates in the long-term authorization identity.

### 🧠 Design Intent (Why)
For the permission experience to approach "authorize once, no repeated hassle on future upgrades," the key isn't stacking more detection branches, but consolidating as much as possible onto a stable bundle identity and a stable install path. At the same time, since onboarding is a one-time setup flow, it shouldn't keep interrupting the user once permissions are already all granted, nor should it require the user to manually close the window as a final step.

### 📁 Files Modified
- `apps/OpenComputerUse/Sources/OpenComputerUse/OpenComputerUseMain.swift`
- `apps/OpenComputerUse/Sources/OpenComputerUse/PermissionOnboardingApp.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/Permissions.swift`
- `scripts/build-open-computer-use-app.sh`
- `scripts/npm/build-packages.mjs`
- `README.md`
- `docs/ARCHITECTURE.md`
- `docs/RELIABILITY.md`
- `docs/histories/2026-04/20260418-0015-stabilize-permission-bundle-identity-and-onboarding.md`
