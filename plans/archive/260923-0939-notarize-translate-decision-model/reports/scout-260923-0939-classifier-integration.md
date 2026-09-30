# MCP Tool Integration Scout: `decide_next_action`

## 1. Tool Registration & Dispatch Files

Files to edit for new tool `decide_next_action`:

- **ToolDefinitions.swift** line 32–156: Add ToolDefinition to `ToolDefinitions.all` array with name, description, readOnlyAnnotations(), inputSchema.
- **ComputerUseToolDispatcher.swift** line 51–113: Add case in switch statement; call `service.decideNextAction(...)`.
- **MCPServer.swift** line 10: Update `computerUseServerInstructions` string; add tool name to available tools list.
- Tools are auto-listed via `ToolDefinitions.all` (MCPServer.swift line 83); no separate manifest.
- **scripts/run-tool-smoke-tests.sh**: Smoke suite auto-discovers all tools; no changes needed.

## 2. Compact Actionable View (PR #10 Details)

**AccessibilitySnapshot.swift** (location: packages/OpenComputerUseKit/Sources/):

- **ElementRecord struct** (lines 7–36): `index: Int`, `role: String?`, `rawActions: [String]`, `prettyActions: [String]`, `isSyntheticText: Bool`.
- **compactActionableLines()** method (line 158–202): Filters actionable elements, prioritizes focused element first, flattens tree, joins multi-line spans with " — ".
- **treeLineOffsets** field (line 116): `[Int: Int]` maps element_index → line offset in full tree; compact view reuses exact rendered rows.
- **Element index invariant**: Indices assigned in full tree; compact view preserves them, so `element_index` stays valid for click/set_value/scroll.
- **RenderStyle enum** (line 309): `case compactActionable` selects rendering style.
- **Default limits** (lines 49–50): `maxNodeCount = 1200`, `maxDepth = 64`; overridable via `max_tree_nodes`/`max_tree_depth` args.

## 3. Process Spawning & Environment

**Environment flags** (read via ProcessInfo.processInfo.environment):
- `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS` — enable system pointer move
- `OPEN_COMPUTER_USE_DEBUG_INPUT_FALLBACKS` — debug input fallbacks
- `OPEN_COMPUTER_USE_VISUAL_CURSOR` — enable visual cursor overlay
- `OPEN_COMPUTER_USE_AGENT_SOCKET_NAMESPACE` — app-agent socket namespace
- `OPEN_COMPUTER_USE_RUN_SKY_CLICK_LIVE_TEST` — test flag

**Process spawning**: No production child processes in OpenComputerUseKit. Environment passed via NSProcessInfo inheritance.

## 4. Which Process Runs Handlers

**App-agent (TCC-privileged) process** runs all tool handlers:
- **OpenComputerUseMain.swift** lines 41–50: MCP server created in main app process.
- **MCPAppRuntime.swift** line 46: NSApplication runs server; line 58 detaches thread for stdio.
- Tool dispatch: StdioMCPServer → ComputerUseToolDispatcher → ComputerUseService (all in app-agent).
- **HTTP client implications**: URLSession calls would execute in TCC-privileged app context. No existing HTTP code in codebase.

## 5. Test Layout

- **Test target**: `OpenComputerUseKitTests` (Package.swift lines 69–72).
- **Test file**: `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift` (~1300 lines).
- **Compact tests** (lines 1022, 1031, 1055+): `.compactActionable` rendering; line 1001 fixture helper.
- **Fixture app**: `OpenComputerUseFixture` executable; provides test app state with known elements.

## 6. HTTP Client Code

**None exists**. To implement HTTP for `decide_next_action` → llama-server sidecar:
- Add URLSession to new ComputerUseService method.
- Use loopback host binding.
- Handle network errors gracefully (fallback behavior).

## Integration Checklist

| Task | Location |
|------|----------|
| Define tool | ToolDefinitions.swift:32–156 |
| Dispatch to service | ComputerUseToolDispatcher.swift:51–113 |
| Implement handler | ComputerUseService.swift (new method) |
| Update instructions | MCPServer.swift:10 |
| Tests (optional) | OpenComputerUseKitTests.swift:1000+ |

