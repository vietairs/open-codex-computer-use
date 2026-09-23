## [2026-04-22 11:13] | Task: Align the default behavior of the remaining Computer Use tools

### 🤖 Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> `click` and `set_value` are already aligned; go through the other 7 tools one by one, drop TODOs, and align the details against the official `.app` reverse-engineering results.

### 🛠 Changes Overview
**Scope:** `OpenComputerUseKit` tool surface / input routing, fixture smoke support, docs

**Key Actions:**
- **[Execution Plan]**: added an active plan breaking the remaining 7 tools into a checklist, recording official `1.0.755` static-type clues and verification commands.
- **[scroll schema]**: aligned `scroll.pages` from `integer` to the official `number` schema, supporting fractional pages, and added official-style errors for `pages must be > 0` and invalid direction.
- **[required string]**: the dispatcher now uniformly rejects empty required strings, returning `Missing required argument: <name>`, covering tools like `type_text` / `press_key` / `set_value` / `scroll`.
- **[Non-physical pointer default path]**: `scroll` / `drag` now default to targeted `CGEvent.postToPid` events; the global `.cghidEventTap` physical pointer fallback is only allowed when `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1` is explicitly set.
- **[Smoke fixture]**: kept a strong reference to the delegate for the bare SwiftPM executable fixture, and only injected the synthetic list identifier into the internal `OpenComputerUseFixture`, restoring 9-tool smoke suite coverage.

### 🧠 Design Intent (Why)

The official binary exposes types like `MouseEventTarget`, `KeyboardEventTarget`, `EventTap`, `SystemFocusStealPreventer`, and `UIElementScrollOperation`, indicating the default action routing isn't simply dumping every fallback onto the system-level hardware cursor. The open-source version first tightens up the default paths that would still move the real mouse or activate the app: use an AX action wherever possible, otherwise use a pid-targeted event; the physical pointer fallback is kept only as an explicit debug switch.

### 📁 Files Modified
- `docs/exec-plans/active/20260422-remaining-tool-official-alignment.md`
- `docs/ARCHITECTURE.md`
- `docs/references/codex-computer-use-reverse-engineering/baseline-architecture.md`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AppDiscovery.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseToolDispatcher.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/Errors.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/FixtureBridge.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/InputSimulation.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ToolDefinitions.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `apps/OpenComputerUseFixture/Sources/OpenComputerUseFixture/main.swift`

### 🔁 Follow-up (2026-04-22, close remaining tool checklist)

- **[Concretized milestones]**: the active plan no longer uses `Milestone 1/2/3` placeholders, switching to three actionable progress entries: official-evidence baseline, action-path convergence, and read-only/keyboard-class review and wrap-up.
- **[secondary action alignment]**: `perform_secondary_action`'s invalid-action error now matches the string form exposed by the official binary; the fixture's `Raise` path no longer calls global pointer prepare.
- **[press_key key table]**: based on the key-table strings in the official `1.0.755` binary, filled out `BackSpace`, `Page_Up`, `Prior` / `Next`, `F1...F12`, and common `KP_*` xdotool aliases.
- **[Closing verification]**: the 9-tool surface from the official `1.0.755` app-server `tools/list` matches the local direct `tools/list`; both `swift test` and the 9-tool smoke suite pass.
