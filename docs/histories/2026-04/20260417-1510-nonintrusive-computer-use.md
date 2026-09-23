## [2026-04-17 15:10] | Task: Converge on non-focus-stealing interaction

### 🤖 Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5 / Codex`
* **Runtime**: `Codex CLI`

### 📥 User Query
> We now have two toolsets — the official `computer-use` and the repo's own `open-codex-computer-use` — and I want a parallel comparison, with the tool calls / results from each side saved to two separate subdirectories under the same directory; the most obvious current problem is that our implementation steals the user's mouse and focus, and I want improvements focused on that.

### 🛠 Changes Overview
**Scope:** `OpenCodexComputerUseKit`, `docs/`, `artifacts/`

**Key Actions:**
- **[Non-intrusive-first input path]**: Removed the forced app activation from `get_app_state`, and changed `type_text` / `press_key` to deliver keyboard events targeted by PID.
- **[Click strategy fix]**: Fixed an issue where raw AX actions were incorrectly filtered, and added an AX hit-test-first path for coordinate clicks, only falling back to global HID when the hit test fails.
- **[Comparison samples archived]**: Added `artifacts/tool-comparisons/20260417-focus-behavior/`, saving call samples and foreground/background observations for both the official `computer-use` and the repo implementation.
- **[Documentation sync]**: Updated the architecture and quality docs, and added the execution plan and this history entry.

### 🧠 Design Intent (Why)
"Stealing focus/mouse" is fundamentally a result of the current implementation building too many paths on top of `activate + cghidEventTap`. The goal of this change is not to pretend all mouse paths can be made entirely side-effect-free, but to converge state reads, keyboard input, and most AX-resolvable clicks onto gentler channels, while explicitly minimizing the scenarios that truly need global HID.

### 📁 Files Modified
- `packages/OpenCodexComputerUseKit/Sources/OpenCodexComputerUseKit/InputSimulation.swift`
- `packages/OpenCodexComputerUseKit/Sources/OpenCodexComputerUseKit/ComputerUseService.swift`
- `packages/OpenCodexComputerUseKit/Sources/OpenCodexComputerUseKit/AccessibilitySnapshot.swift`
- `docs/ARCHITECTURE.md`
- `docs/QUALITY_SCORE.md`
- `docs/exec-plans/completed/20260417-nonintrusive-computer-use.md`
- `artifacts/tool-comparisons/20260417-focus-behavior/README.md`
- `artifacts/tool-comparisons/20260417-focus-behavior/computer-use/get_app_state-activity-monitor.json`
- `artifacts/tool-comparisons/20260417-focus-behavior/open-codex-computer-use/get_app_state-activity-monitor.json`
- `artifacts/tool-comparisons/20260417-focus-behavior/open-codex-computer-use/click-activity-monitor-coordinate.json`

### 🔁 Follow-up (2026-04-17 17:02)

The same task continued in a later round of MITM debugging, adding two more rounds of convergence:

- **[AX-raise before global mouse]**: `InputSimulation` no longer treats "needs global pointer" as automatically equivalent to `activate()`; it now first tries `AXRaise`, `kAXMainAttribute`, and `kAXFocusedAttribute`, and only falls back to `NSRunningApplication.activate` if all of those fail.
- **[Tool intrusion hints]**: The intrusiveness preference of all 9 tools is now written directly into `ToolDefinitions` and the plugin manifest, making it easier for the model to prefer `get_app_state` / `press_key` / `type_text` / `set_value` / `perform_secondary_action`, reducing unnecessary coordinate clicks and drags.
- **[MITM debugging methodology captured]**: Added notes to `docs/references/codex-network-capture.md` on prompt-anchoring differences and the "host cancellation vs. MCP server failure" triage order, to avoid repeating the same pitfalls in future A/B tests or evals.

The focus of this follow-up wasn't to add another layer of abstraction, but to push the "model-side preference" and the "runtime fallback strategy" in the same direction together. Runtime optimization alone still leaves the model frequently choosing high-side-effect tools; prompt hints alone still leave premature focus-stealing when it truly degrades to global pointer use. Closing both loops together gets us more reliably closer to the official `computer-use` behavior of "keyboard first, AX first, global mouse last."

**Follow-up Files:**
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/InputSimulation.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ToolDefinitions.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `docs/ARCHITECTURE.md`
- `docs/references/codex-network-capture.md`

### 🔬 Follow-up (2026-04-17 17:20)

While continuing to debug the Codex host side, formally brought "isolate the other plugin and rerun the case" into the repo workflow:

- **[Isolated exec helper]**: Added `scripts/run-isolated-codex-exec.sh`, unifying the `computer-use` / `open-computer-use` / `all` three modes into a single entry point, implemented under the hood via a single `codex exec -c 'plugins."...".enabled=false'` temporary override, without touching the global `~/.codex/config.toml`.
- **[A/B routing guidance]**: Added an "isolated plugin path" section to `docs/references/codex-network-capture.md`, clarifying that when comparing the official and repo plugins, the other one should be disabled by default, to avoid prompt anchoring and co-installed plugins jointly polluting the conclusion.
- **[Verification outcome]**: On this machine, the isolated verification result was: with only the official `computer-use` enabled, `list_apps` works normally; with only `open-computer-use` enabled, `list_apps` still returns `user cancelled MCP tool call`; while a direct JSON-RPC call to the repo plugin's launcher works fine. So the current main bottleneck is not the two plugins interfering with each other, but rather something more like a gate the Codex host applies to third-party plugin calls.

The value of this step isn't just "getting a shell alias working." Previously, the `prompt` copy, plugin co-installation state, and host policy were all tangled together, making it easy to misattribute routing differences as runtime behavior differences. With the isolation entry point now in the repo, future focus-behavior comparisons, MITM sample captures, and evals can at least pin down "who is actually being called" first.

**Isolation Files:**
- `scripts/run-isolated-codex-exec.sh`
- `docs/references/codex-network-capture.md`
