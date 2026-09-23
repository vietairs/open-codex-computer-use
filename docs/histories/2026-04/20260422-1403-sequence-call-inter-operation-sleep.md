## [2026-04-22 14:03] | Task: Add sequence call inter-operation sleep

### Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### User Query
> Add a fixed interval to sequence calls like `swift run OpenComputerUse call --calls-file examples/textedit-overlay-seq.json`, as an optional parameter with a default value of 1 second.

### Changes Overview
**Scope:** `OpenComputerUseKit` CLI parsing, sequence execution, tests, docs

**Key Actions:**
- **[Sequence sleep option]**: Added a sequence-only `--sleep <seconds>` CLI option for `open-computer-use call --calls ...` / `--calls-file ...`, with a default inter-operation delay of 1 second.
- **[Execution behavior]**: Applied the delay only between successful neighboring sequence operations; single-tool calls still run without an extra wrapper sleep.
- **[Docs and coverage]**: Updated CLI help, README, architecture notes, and unit tests to lock in the default and custom-delay behavior.

### Design Intent (Why)
The sequence runner already preserves in-process app snapshot state, but it previously fired each step immediately after the previous one returned. Adding a small default gap makes visual cursor demos and real-app multi-step probes easier to observe, while `--sleep` keeps the pacing override explicit instead of hard-coding one fixed rhythm forever.

### Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseCLI.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseToolDispatcher.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `README.md`
- `README.zh-CN.md`
- `docs/ARCHITECTURE.md`
- `docs/histories/2026-04/20260422-1403-sequence-call-inter-operation-sleep.md`
