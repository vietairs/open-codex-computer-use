## [2026-05-08 10:45] | Task: Headless smoke fixture

### Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### User Query
> `./scripts/run-tool-smoke-tests.sh` pops up an orange window every time it runs; get rid of this unnecessary window.

### Changes Overview
**Scope:** OpenComputerUseFixture, OpenComputerUseSmokeSuite, OpenComputerUseKit, docs

**Key Actions:**
- **Headless fixture mode**: Added an `OPEN_COMPUTER_USE_FIXTURE_HEADLESS` switch to the smoke fixture; when headless, it does not activate or bring windows to the front.
- **Smoke runner default**: The smoke suite now injects the headless environment variable by default when launching the fixture.
- **Discovery compatibility**: Allowed the internal fixture to still be discoverable by tests even when running under the accessory activation policy.
- **Architecture docs**: Documented that the smoke scripts now use the headless fixture by default, so no test window pops up on the user's desktop.

### Design Intent (Why)
The smoke tests need a real fixture to host AX controls and test commands, but they don't need a visible test window popping up on the user's desktop. Making headless an explicit environment switch on the fixture lets the scripts run quietly by default, while still preserving the ability to open a visible window for manual debugging.

### Files Modified
- `apps/OpenComputerUseFixture/Sources/OpenComputerUseFixture/main.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AppDiscovery.swift`
- `docs/ARCHITECTURE.md`
