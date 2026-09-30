# Tool Surface Map: `perform_actions` Batch Implementation

## 1. Tool Registration & Dispatch

| File | Line(s) | Purpose |
|------|---------|---------|
| ToolDefinitions.swift | 31–157 | Swift enum `ToolDefinitions.all[]` array; 9 base tools + optional `decideNextAction` |
| ToolDefinitions.swift | 178–183 | `ToolDefinitions.listed(environment:)` — conditionally adds `decideNextAction` |
| ComputerUseToolDispatcher.swift | 57–130 | `callTool(name, arguments)` switch statement; 9 cases for base tools + `decide_next_action` |
| ComputerUseToolDispatcher.swift | 344–366 | `runOpenComputerUseCall` handles `.sequence()` case for batch CLI calls |
| MCPServer.swift | 112–118 | `tools/list` JSON-RPC handler calls `ToolDefinitions.listed(environment:)` |
| MCPServer.swift | 119–126 | `tools/call` JSON-RPC handler invokes `dispatcher.callTool()` |
| apps/OpenComputerUseLinux/main.go | 1139–1234 | `toolDefinitions()` Go function; 9 base tools hardcoded |
| apps/OpenComputerUseLinux/main.go | 1633–1641 | `tools/list` JSON-RPC handler; `tools/call` handler |
| apps/OpenComputerUseWindows/main.go | 710 | `toolDefinitions()` function (Windows mirrors Linux) |
| apps/OpenComputerUseWindows/main.go | 1204–1205 | `tools/list` handler |

## 2. MCP Server Instructions

| File | Line(s) | Content |
|------|---------|---------|
| MCPServer.swift | 3–18 | `baseComputerUseServerInstructions` constant; "Begin by calling get_app_state..." guidance |
| MCPServer.swift | 25–30 | `computerUseServerInstructions(environment:)` — appends cascade guide if `decide_next_action` listed |
| MCPServer.swift | 97 | Instructions injected into JSON-RPC `initialize` response |
| apps/OpenComputerUseLinux/main.go | 30 | `serverInstructions` constant (Linux-specific: mentions AT-SPI2, coordinate fallbacks) |
| apps/OpenComputerUseWindows/main.go | ~30 | `serverInstructions` constant (Windows variant) |

## 3. Skill & Agent Guidance

| File | Sections/Lines |
|------|---------|
| skills/open-computer-use/SKILL.md | Lines 20–32: Core workflow (steps 1–11, emphasizes `get_app_state` per turn) |
| skills/open-computer-use/SKILL.md | Lines 34–42: Operating rules (element-targeted actions, verify after each action) |
| skills/open-computer-use/references/usage.md | Lines 55–69: Batch/sequence guidance (`--calls` JSON array for multi-step reuse of process state) |
| skills/open-computer-use/references/usage.md | Lines 101–106: Choosing targets (run `get_app_state` before element actions, re-run after navigation) |
| skills/open-computer-use/references/decision-model.md | Lines 111–116: Cascade guide — "follow advice only when margin ≥ min AND operation non-destructive AND chosen_row_text matches intent" |

## 4. Test Coverage

| File | Key Tests/Fixtures |
|------|---------|
| Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift | Line 256: `ToolDefinitions.all.count == 9` assertion |
| Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift | Lines 699–768: Dispatcher tests (`callToolAsResult` for type_text, click, press_key, set_value) |
| Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift | Lines 2963–3146: Session guard tests (locked/unlocked/opt-in scenarios) |
| FixtureBridge.swift | Lines 1–70: `FixtureAppState`, `FixtureElementState` structures for snapshot fixtures |
| apps/OpenComputerUseFixture/Sources/OpenComputerUseFixture/main.swift | Fixture app for live test scenarios |

## 5. Existing Sequence/Batch Infrastructure

- **CLI:** `--calls` flag in OpenComputerUseCLI.swift (line 17) and runOpenComputerUseCall (lines 344–366) already supports JSON array of `{"tool": "name", "args": {...}}` objects with optional inter-call delay.
- **Dispatcher:** callToolAsResult is idempotent per call; sequence loop breaks on first error (line 358).
- **MCP:** No batch/sequence tool currently exposed; each `tools/call` is independent.

## Impact Summary

**New `perform_actions` tool must touch:**
1. Add tool definition in ToolDefinitions.swift (lines 31–157)
2. Add dispatch case in ComputerUseToolDispatcher.callTool (lines 62–130)
3. Update instructions in MCPServer.swift if needed for guidance on when to use batch vs single calls
4. Mirror definitions in both Go servers (Linux/Windows toolDefinitions functions)
5. Update skill docs (SKILL.md, usage.md) to cover batch semantics and verification per action
6. Add test coverage for batch tool in OpenComputerUseKitTests.swift

Status: DONE
Summary: Mapped all tool registration sites (Swift/Go), MCP instruction sources, skill guidance, and test layouts. Identified existing sequence CLI infrastructure that can inform MCP batch tool design.
