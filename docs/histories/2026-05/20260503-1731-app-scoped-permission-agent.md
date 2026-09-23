## [2026-05-03 17:31] | Task: Fix macOS terminal permission attribution

### Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5`
* **Runtime**: `local macOS workspace`

### User Query
> `open-computer-use doctor` can open the permissions page, but when run from the terminal, the permission requested seems to be for iTerm/Terminal instead of `Open Computer Use.app`; we need to make sure that when iTerm has no Accessibility / Screen Recording permission, granting permission to Open Computer Use alone still works.

### Changes Overview
**Scope:** `apps/OpenComputerUse`, `packages/OpenComputerUseKit`, `docs`

**Key Actions:**
- **[App agent proxy]**: Added a hidden app-agent launch mode; the terminal CLI forwards `mcp`, `doctor`, `call`, `snapshot`, and `list-apps` over a Unix domain socket to the `.app` process launched by LaunchServices.
- **[Onboarding reuse]**: Split the permission onboarding flow out into a reusable `present()` path, letting doctor display the authorization window inside the already-running app agent's NSApplication instead of running UI directly inside the terminal subprocess.
- **[Decision tests]**: Moved the app-agent proxy-selection rules down into pure functions inside the Kit, with added unit tests covering proxying automation commands, running non-automation commands locally, not recursively proxying when LaunchServices opens the app, the disable switch, and the missing-bundle fallback.
- **[Launch mode guard]**: For a no-argument launch, distinguished between the `.app` opened by LaunchServices and the bundle executable run directly from the terminal, avoiding leaving behind an extra background agent when the app is double-clicked, while still routing the terminal entry point through the app-identity proxy.
- **[Socket permissions]**: Tightened the app-agent Unix socket, after creation, to current-user read/write only, maintaining a local-only permission boundary.
- **[Permission relaunch]**: After completing authorization inside the app agent, the current app process is still terminated, ensuring the next command uses the freshly restarted, authorized process to run the ScreenCaptureKit / AX paths.
- **[Permission wording]**: Updated the permission error messages and docs wording to make clear that the macOS authorization target is `Open Computer Use.app`, not the host terminal.
- **[Swift 6.2 build fix]**: Adapted to Swift 6.2 concurrency checking by explicitly marking the cursor reference `NSImage` static cache as `nonisolated(unsafe)`, keeping the current AppKit main-thread drawing path compilable.

### Design Intent (Why)
macOS TCC attributes responsibility for Accessibility and Screen Recording to whichever process actually calls the system API. When the terminal launches the native runtime directly, the system may prompt for iTerm/Terminal to be granted permission; putting the real automation inside an app bundle process launched via LaunchServices lets the user grant permission only to `Open Computer Use.app`, while the terminal is responsible for stdio/command proxying.

### Files Modified
- `apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift`
- `apps/OpenComputerUse/Sources/OpenComputerUse/OpenComputerUseMain.swift`
- `apps/OpenComputerUse/Sources/OpenComputerUse/PermissionOnboardingApp.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseCLI.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SoftwareCursorGlyphRenderer.swift`
- `docs/ARCHITECTURE.md`
- `docs/SECURITY.md`
- `docs/RELIABILITY.md`

### Verification
- Passed: `git diff --check`
- Passed: `./scripts/check-docs.sh`
- Passed: `xcrun swiftc -parse apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift`
- Passed: `xcrun swiftc -parse packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseCLI.swift`
- Passed: `xcrun swiftc -parse packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- Passed: `PATH="$HOME/.swiftly/bin:$PATH" swift build --product OpenComputerUse` with Swift `6.2.4`.
- Passed: `PATH="$HOME/.swiftly/bin:$PATH" ./scripts/build-open-computer-use-app.sh debug --arch native`.
- Passed: `.build/arm64-apple-macosx/debug/OpenComputerUse doctor` returned missing permission status while launching `dist/Open Computer Use (Dev).app/Contents/MacOS/OpenComputerUse __open-computer-use-app-agent ...`, confirming the terminal command hands off to the app bundle process.
- Passed: the app-agent socket was created as `srw-------`, current-user read/write only.
- Passed: after granting the dev app both macOS permissions, `OpenComputerUse doctor` reported `accessibility=granted, screenRecording=granted`.
- Passed: `OpenComputerUse call get_app_state --args '{"app":"Finder"}'` returned `isError=false` with both `text` and `image` content while iTerm did not hold the permissions.
- Passed: Codex MCP integration via `codex exec` with the bundled official `computer-use` plugin disabled called `server="open-computer-use"` for `list_apps` and `get_app_state`.
- Passed: Codex-driven action smoke covered `click`, `scroll`, `set_value`, `press_key`, `drag`, and `type_text`; Finder, Calendar, and the local fixture succeeded, while TextEdit `click` exposed an existing window-bounds edge case but TextEdit typing still succeeded.
- Blocked locally: `PATH="$HOME/.swiftly/bin:$PATH" swift test` cannot import `XCTest` from the Swift.org toolchain in this CLT-only environment.
