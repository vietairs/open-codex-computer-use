## [2026-04-17 15:54] | Task: Unify open-computer-use naming

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5.4`
* **Runtime**: `Codex CLI on macOS`

### 📥 User Query
> Besides keeping the repo name as `open-codex-computer-use`, unify all other external naming to `open-computer-use`; at minimum, align the plugin's already-adopted new naming with the MCP name first.

### 🛠 Changes Overview
**Scope:** `Package.swift`, `apps/`, `packages/`, `scripts/`, `plugins/open-computer-use`, `README.md`, `docs/`, `artifacts/`

**Key Actions:**
- **[Runtime Identity]**: Converged the current naming of the Swift package / executable / fixture / smoke suite to `OpenComputerUse*`, and changed the MCP `serverInfo.name` to `open-computer-use`.
- **[Packaging and Install]**: Switched the `.app` packaging artifact, plugin launcher, install script, and Makefile entry points to `OpenComputerUse.app` / `OpenComputerUse`, and synced the bundle display name and bundle identifier accordingly.
- **[Docs and Samples]**: Updated the README, architecture/security/reliability/quality docs, and the active exec plan; kept old directory names for historical samples but explicitly noted in the accompanying text that the current product name has switched to `open-computer-use`.

### 🧠 Design Intent (Why)
The goal of this round of changes was not just to change one string, but to converge "product name, MCP name, executable name, packaging name, plugin entry point, and doc wording" into one consistent current state, avoiding users seeing both `open-codex-computer-use` and `open-computer-use` as two parallel naming schemes in the repo at the same time. The repo name, history records, and legacy config cleanup logic were kept as-is to balance migration cost against traceability.

### 📁 Files Modified
- `Package.swift`
- `apps/OpenComputerUse/Sources/OpenComputerUse/OpenComputerUseMain.swift`
- `apps/OpenComputerUse/Sources/OpenComputerUse/PermissionOnboardingApp.swift`
- `apps/OpenComputerUseFixture/Sources/OpenComputerUseFixture/main.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/FixtureBridge.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MCPServer.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/Permissions.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/build-open-computer-use-app.sh`
- `scripts/install-codex-plugin.sh`
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `plugins/open-computer-use/scripts/launch-open-computer-use.sh`
- `README.md`
- `docs/ARCHITECTURE.md`
- `docs/SECURITY.md`
- `docs/RELIABILITY.md`
- `docs/QUALITY_SCORE.md`
- `docs/exec-plans/active/20260417-permission-onboarding-app.md`
- `docs/references/codex-computer-use-reverse-engineering/README.md`
- `docs/references/codex-computer-use-reverse-engineering/software-cursor-overlay.md`
- `artifacts/tool-comparisons/20260417-focus-behavior/README.md`
- `docs/histories/2026-04/20260417-1554-rename-open-computer-use-identifiers.md`
