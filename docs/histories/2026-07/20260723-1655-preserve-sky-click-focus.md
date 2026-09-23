## [2026-07-23 16:55] | Task: Fix sky_click losing foreground focus

### 🤖 Execution Context
* **Agent ID**: `/root`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex desktop / macOS arm64`

### 📥 User Query
> Fix the issue where `sky_click`, even though it doesn't raise the target window to the front, still causes the current application to lose input focus, and strengthen verification against Codex's behavior.

### 🛠 Changes Overview
**Scope:** macOS SkyLight click runtime, snapshot recovery, fixture focus probe, tests, and docs.

**Key Actions:**
- **Target-only synthetic focus**: Removed the defocus/restore record sent to the real foreground application; now only the target application briefly enters a synthetic-active state, and only the target's state is reverted after the renderer settles.
- **Non-invasive refresh**: `sky_click`'s action-result snapshot now uses a read-only recovery policy, disallowing recovering the target window via `NSRunningApplication.activate` or `AXRaise`.
- **Focus regression**: Extended the fixture state to record AppKit active, key window, first responder, and cumulative `resignActive`/`resignKey` counts; the isolated Chrome real-machine regression now asserts on these states.
- **Compatibility boundary**: Did not change the Chromium primer, PID/window event fields, SkyLight/public dual-channel delivery, `auto`'s default behavior, or explicit fail-closed semantics.

### 🧠 Design Intent (Why)
*The old implementation mistook "without raise" for "keeps focus": it never changed the WindowServer frontmost PID or z-order, yet it actively sent `focused=false` to the real foreground application, which was enough to trigger AppKit resign/key/first-responder side effects. The new session data structure no longer stores a foreground PSN/window, structurally disallowing this kind of delivery; if a background target needs compatibility state, it can only get an independent, target-only synthetic focus.*

### ✅ Verification
- `swift build` passes.
- `swift test` passes: 149 OpenComputerUseKit unit tests, 3 StandaloneCursorSupport tests, and 1 intentionally skipped opt-in live test.
- `OPEN_COMPUTER_USE_RUN_SKY_CLICK_LIVE_TEST=1 swift test --filter SkyClickLiveTests` passes; isolated fully covered Chrome triggers exactly one DOM click.
- Foreground fixture remains frontmost, active and key; its text-field first responder and resign/key-loss counters stay unchanged.
- Real pointer position and Chrome/cover z-order remain unchanged.
- `./scripts/run-tool-smoke-tests.sh` passes the full 9-tool sequence and visual cursor idle smoke.
- `npm run package:skill` passes.

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SkyLightSPI.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SkyClickSimulation.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/FixtureBridge.swift`
- `apps/OpenComputerUseFixture/Sources/OpenComputerUseFixture/main.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/`
- `docs/` and `skills/open-computer-use/references/usage.md`
