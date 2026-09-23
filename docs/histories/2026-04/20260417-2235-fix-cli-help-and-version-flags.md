## [2026-04-17 22:35] | Task: Fix CLI help and version flags

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> `open-computer-use -v` hangs. This CLI needs to support `-h`, `--help`, `-v`, `--version`, and let users see the supported subcommands and arguments.

### 🛠 Changes Overview
**Scope:** `apps/OpenComputerUse`, `packages/OpenComputerUseKit`, `README.md`, `docs/ARCHITECTURE.md`, `scripts/npm/build-packages.mjs`

**Key Actions:**
- **Extract CLI parsing**: Added testable CLI parsing and help-text logic in `OpenComputerUseKit`, uniformly handling global flags, subcommand help, and error messages.
- **Fix version flag behavior**: Made `-v` / `--version` / `version` print the version number directly, instead of incorrectly falling through to the default app mode.
- **Update docs and distribution notes**: Synced the repo README, architecture doc, and npm package README template to clarify the help and version command usage.

### 🧠 Design Intent (Why)
The previous entry point only matched a subcommand against the first argument and didn't handle global flags separately, so a common CLI usage like `-v` directly triggered the default onboarding branch. Consolidating the parsing logic into its own module lets help text, error messages, and version output share one set of rules, and makes it easier to guard long-term with unit tests.

### 📁 Files Modified
- `apps/OpenComputerUse/Sources/OpenComputerUse/OpenComputerUseMain.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseCLI.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MCPServer.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `README.md`
- `docs/ARCHITECTURE.md`
- `scripts/npm/build-packages.mjs`
