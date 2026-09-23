## [2026-04-22 17:05] | Task: Clean up app packaging build warnings

### 🤖 Execution Context
* **Agent ID**: `codex-main`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Running `./scripts/build-open-computer-use-app.sh debug` produces a lot of warnings.

### 🛠 Changes Overview
**Scope:** `OpenComputerUseKit`, `docs`

**Key Actions:**
- **[Modernize app launch path]**: Removed the deprecated `NSWorkspace.launchApplication(...)` and `fullPath(forApplication:)` in `AppDiscovery`, replacing them with standard application-directory resolution plus the modern `openApplication(at:configuration:)`.
- **[Modernize window capture path]**: Removed the deprecated `CGWindowListCreateImage` in `AccessibilitySnapshot`, replacing it with single-window screenshotting based on `ScreenCaptureKit`.
- **[Trim test-only warning]**: Removed the now-ineffective `activateIgnoringOtherApps` option in the `CursorMotion` experimental target, avoiding an extra deprecation warning from `swift test`.
- **[Sync docs]**: Updated the screenshot implementation notes in the architecture doc.

### 🧠 Design Intent (Why)
The goal of this task wasn't to just suppress the warnings, but to actually migrate off system APIs that already have replacements, ensuring `./scripts/build-open-computer-use-app.sh debug` stays clean under the current Xcode/Swift combination and reduces noise from future SDK upgrades.

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AppDiscovery.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `experiments/CursorMotion/Sources/CursorMotion/CursorMotionApp.swift`
- `docs/ARCHITECTURE.md`
- `docs/histories/2026-04/20260422-1705-build-warning-cleanup.md`
