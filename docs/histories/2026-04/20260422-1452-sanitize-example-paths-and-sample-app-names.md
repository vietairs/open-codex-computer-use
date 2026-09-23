## [2026-04-22 14:52] | Task: Consolidate example paths and sanitize sample app names

### Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### User Query
> Clean up `computer-use-cli`-related examples and doc references, unify them to the repo-root sample path, and avoid continuing to reference real product names in the README, tests, and reference logs.

### Changes Overview
**Scope:** example paths, helper docs, test samples, reference logs

**Key Actions:**
- **[Example path consolidation]**: Removed the duplicate sequence JSON under `scripts/computer-use-cli/`, switching uniformly to reference the root-level `examples/textedit-overlay-seq.json`.
- **[Sample name sanitization]**: Changed specific app names in the helper README, Go tests, Swift tests, and reference logs to generic samples like `TextEdit` or `Sample Chat`.
- **[History sync]**: Synced corrections into existing history entries whose sample-path descriptions had gone stale, so the docs no longer point to a removed location.

### Design Intent (Why)
These samples were only ever meant to illustrate call shapes; they shouldn't stay tied to a specific real product name, and the repo shouldn't maintain two sequence files with duplicate content. Unifying the paths and naming makes future manual verification, README examples, and test assertions more stable, and better suits an open-source repo's continued evolution.

### Files Modified
- `scripts/computer-use-cli/README.md`
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/main_test.go`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/references/codex-local-runtime-logs.md`
- `docs/histories/2026-04/20260420-2033-integrate-set-value-visual-cursor.md`
- `docs/histories/2026-04/20260422-1452-sanitize-example-paths-and-sample-app-names.md`
