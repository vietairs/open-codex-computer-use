## [2026-04-17 13:25] | Task: Implement open-source Swift computer-use

### 🤖 Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI / Swift 6.2.4 / macOS`

### 📥 User Query
> Based on the already-completed `codex-computer-use` analysis material, implement an open-source Swift version; land the todos in `docs/`, keep pushing the implementation forward, and get all 9 tools fully tested.

### 🛠 Changes Overview
**Scope:** `apps/OpenCodexComputerUse`, `apps/OpenCodexComputerUseFixture`, `apps/OpenCodexComputerUseSmokeSuite`, `packages/OpenCodexComputerUseKit`, `docs/`, `scripts/`

**Key Actions:**
- **[Implement Swift MCP server]**: Added a new Swift Package, a `stdio` JSON-RPC transport, 9 tool schemas, and `ComputerUseService`.
- **[Implement local macOS automation]**: Wired up app discovery, snapshots, input simulation, and `doctor` / `snapshot` diagnostic entry points.
- **[Fill out the deterministic smoke path]**: Added a fixture app, a fixture bridge, and a smoke suite, covering end-to-end verification of all 9 tools.
- **[Converge real app snapshots]**: Fixed the AX frame coordinate conversion for normal apps so that real apps like Finder produce a stable window-relative frame, and added manual verification against real apps.
- **[Sync documentation]**: Updated the README, architecture, quality score, security/reliability notes, release notes, and execution plan.

### 🧠 Design Intent (Why)
The priority for this round was delivering an "open-source, runnable implementation plus a repeatable verification loop," rather than continuing to sit on closed-source reverse-engineering analysis or prematurely replicating the official private host boundaries. Keeping the AX / screenshot / CGEvent path for real apps, and adding a test-only bridge for the fixture, is meant to balance capability authenticity with regression stability.

### 📁 Files Modified
- `Package.swift`
- `apps/OpenCodexComputerUse/Sources/OpenCodexComputerUse/main.swift`
- `apps/OpenCodexComputerUseFixture/Sources/OpenCodexComputerUseFixture/main.swift`
- `apps/OpenCodexComputerUseSmokeSuite/Sources/OpenCodexComputerUseSmokeSuite/main.swift`
- `packages/OpenCodexComputerUseKit/Sources/OpenCodexComputerUseKit/`
- `packages/OpenCodexComputerUseKit/Tests/OpenCodexComputerUseKitTests/OpenCodexComputerUseKitTests.swift`
- `scripts/run-tool-smoke-tests.sh`
- `README.md`
- `docs/ARCHITECTURE.md`
- `docs/QUALITY_SCORE.md`
- `docs/SECURITY.md`
- `docs/RELIABILITY.md`
- `docs/exec-plans/active/20260417-open-source-swift-computer-use.md`
- `docs/releases/feature-release-notes.md`

### ➕ Follow-up Progress
- **[Added app-mode permission onboarding]**: `OpenCodexComputerUse` now enters a permission onboarding window when launched without a subcommand, supporting `Accessibility` / `Screen & System Audio Recording` deep links, drag tiles, and `.app` packaging.
- **[Converged permission-state detection]**: The permission card no longer relies solely on in-process runtime APIs; it now also reads TCC's persisted authorization record, so the GUI app and CLI subprocess no longer see different states.
- **[Added functional verification]**: This round re-ran `swift test`, `./scripts/run-tool-smoke-tests.sh`, `doctor`, and a real `System Settings snapshot`, confirming the functional paths of all 9 tools still work correctly.
- **[Tightened permission-window visual density]**: Shrunk the onboarding window, title, and card font sizes, tightened card height and spacing, and changed the `Allow` button in the missing-permission state to a hand-drawn pill button closer to the reference image; also condensed the card's secondary copy to a shorter phrasing to reduce overall bulkiness.

### 🔎 Additional Files
- `apps/OpenCodexComputerUse/Sources/OpenCodexComputerUse/OpenCodexComputerUseMain.swift`
- `apps/OpenCodexComputerUse/Sources/OpenCodexComputerUse/PermissionOnboardingApp.swift`
- `packages/OpenCodexComputerUseKit/Sources/OpenCodexComputerUseKit/Permissions.swift`
- `scripts/build-open-codex-app.sh`
- `docs/exec-plans/active/20260417-permission-onboarding-app.md`
