## [2026-09-29 23:00] | Task: speed up continuous Computer Use turns and teach agents to batch

### 🤖 Execution Context
* **Agent ID**: hvn-atomic-worker
* **Base Model**: Claude Sonnet 5.5 (claude-sonnet-5-5)
* **Runtime**: Claude Code, worktree `feat/continuous-computer-use-speed`

### 📥 User Query
> Make continuous Computer Use sessions faster: fewer turns per task and lower per-call latency, without adding any
> server-side planner. The server proposes and executes; the agent still owns the goal.

### 🛠 Changes Overview
**Scope:** `packages/OpenComputerUseKit` (Sources + Tests), `apps/OpenComputerUseSmokeSuite`, `skills/open-computer-use`,
`docs/ARCHITECTURE.md`, `docs/QUALITY_SCORE.md`, `docs/SECURITY.md`.

**Key Actions:**
- **Text-only action results**: action results skip the window screenshot and its ScreenCaptureKit capture unless
  `include_screenshot: true` is passed or the window exposes no accessibility elements below its root (menu-bar items
  do not count). x/y coordinates reuse the last returned screenshot's pixel size, or fail closed when the window
  changed, including inside a batch after an earlier step resized the window.
- **Cursor travel cap**: the overlay caps blocking cursor travel at 0.3s by time-compressing the same spring; the
  recovered 1.4291667s timing stays in `CursorMotionModel`.
- **Named settle interval**: the post-action settle sleep is one named constant shared by every action (no value change).
- **Batched AX reads**: per-node attributes are read in one `AXUIElementCopyMultipleAttributeValues` round trip.
- **`perform_actions`**: a macOS-only tool that runs up to 10 `{tool, args}` steps in order on one app, stops at the
  first failure and returns one final state with a line per step. Element indices refer to the last received state;
  a batch with any `element_index` step is refused before it runs when the session holds no state for the app.
- **jev letter cache**: the resolved jev letter table is persisted per base_url and model (0600, 7-day TTL), so a
  fresh process skips the `/tokenize` round trips. The shared owner-only reader names each caller's file in its errors.
- **Agent guidance**: server instructions, the skill and the usage reference keep the start-of-turn `get_app_state`,
  stop the per-action `get_app_state`, describe when to batch, and document text-only results (macOS only) and the
  Mail search pattern. Architecture and quality notes count 10 macOS tools; the security notes describe the cache file.

### 🧠 Design Intent (Why)
Most of a task's wall time went to per-action screenshots, long cursor travel, redundant `get_app_state` calls and
one model turn per keystroke-level step. Each lever removes one of those costs while keeping advisory-only
behavior. Per-lever measurements (before/after latency and turn counts on real apps) are still pending; they will be
recorded once the live acceptance runs complete.

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilityAttributePrefetch.swift` (new)
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/BatchActionRunner.swift` (new)
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseToolDispatcher.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/DecisionJevClient.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/DecisionJevLetterDiskCache.swift` (new)
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/DecisionJevPrompt.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/DecisionRemoteBackend.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MCPServer.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SoftwareCursorOverlay.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ToolDefinitions.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/`: `AXAttributePrefetchTests.swift`,
  `ActionResultScreenshotPolicyTests.swift`, `BatchActionRunnerTests.swift`, `CursorTravelCapTests.swift`,
  `DecisionJevLetterDiskCacheTests.swift`, `PostActionSettleTests.swift`, `ServerInstructionsGuidanceTests.swift` (new);
  `DecisionAdvisorTests.swift`, `OpenComputerUseKitTests.swift` (updated)
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `skills/open-computer-use/SKILL.md`
- `skills/open-computer-use/references/usage.md`
- `docs/ARCHITECTURE.md`
- `docs/QUALITY_SCORE.md`
- `docs/SECURITY.md`
