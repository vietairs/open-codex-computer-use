## [2026-04-17 21:55] | Task: Have doctor launch the onboarding page when permissions are missing

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> When `open-computer-use doctor` currently prints `Permissions: accessibility=missing, screenRecording=missing`, it needs to pop the onboarding page.

### 🛠 Changes Overview
**Scope:** `apps/OpenComputerUse`, `packages/OpenComputerUseKit`, `docs/`, `scripts/npm`

**Key Actions:**
- **Added doctor follow-up action**: after `doctor` prints permission status, if anything is still missing, it now launches the existing permission onboarding window directly.
- **Added a testable diagnostic result**: added `missingPermissions` to `PermissionDiagnostics`, letting the CLI decision reuse the permission layer's result, with corresponding unit tests.
- **Synced user docs**: updated the repo README, architecture doc, reliability doc, and npm README template to state clearly that `doctor` enters onboarding when permissions are missing.

### 🧠 Design Intent (Why)
The repo already had a complete permission onboarding UI, but `doctor` previously only printed the result, leaving users who saw `missing` from the CLI to go find the entry point themselves. Reusing the existing onboarding directly when permissions are missing shortens diagnosis-and-fix into one path, while avoiding a second, duplicate permission-guidance flow inside the CLI.

### 📁 Files Modified
- `apps/OpenComputerUse/Sources/OpenComputerUse/OpenComputerUseMain.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/Permissions.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `README.md`
- `docs/ARCHITECTURE.md`
- `docs/RELIABILITY.md`
- `scripts/npm/build-packages.mjs`
