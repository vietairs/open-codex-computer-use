## [2026-04-20 15:58] | Task: Fix onboarding incorrectly popping again on app reopen after permissions were already granted

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5.4`
* **Runtime**: `Codex CLI on macOS`

### 📥 User Query
> After finishing all the `Allow` grants, reopening the app still pops two windows both asking for `Allow` again; but after closing the windows, running `open-computer-use` or `open-computer-use doctor` shows both permissions as already granted. This is a regression introduced later and needs to be fixed.

### 🛠 Changes Overview
**Scope:** `packages/OpenComputerUseKit`, `docs/histories`

**Key Actions:**
- **[Stable Permission Target]**: changed the permission-target bundle selection logic to genuinely prefer the stable `.app` installed globally via npm, instead of letting the currently running temporary/source app copy take priority.
- **[Permission Client Ordering]**: reorganized the TCC query candidates to check the stable bundle identifier first, then the stable app path, and finally fall back to the currently running app path, reducing misleading permission state from dev-mode paths.
- **[Grant Aggregation Fix]**: TCC queries no longer short-circuit on the first `false` match; now all candidates are iterated, and as long as any matching record is `granted`, it's treated as granted, preventing a stale-path record from masking the true grant.
- **[Regression Tests]**: added unit tests covering both regression points — "reopening a source/temporary app copy should still follow the stable-install identity" and "any granted match among multiple candidates counts as granted."

### 🧠 Design Intent (Why)
The root cause of this regression wasn't that permissions were actually lost, but that permission-state reading, on app reopen, had reverted to the old behavior of "the currently running copy's path takes priority + first match returned wins," which let certain temporary paths or stale records mask the truly stable grant identity. The fix aims to make app mode, `open-computer-use`, and `doctor` reach a consistent conclusion for the same stable authorization identity, so there's no longer a split where "the window says permission is missing, the CLI says it's granted."

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/Permissions.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/histories/2026-04/20260420-1558-fix-permission-relaunch-misdetection.md`
