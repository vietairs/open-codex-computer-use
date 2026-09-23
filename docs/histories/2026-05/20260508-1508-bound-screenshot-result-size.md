# Bound screenshot result size

## User Request

The user found that some `open-computer-use` tool calls turn into a JSON string under `text` in the Codex history, suspected that recent commits introduced extra wrapping, and provided a historical session id to help locate it.

## Changes This Round

- **[Root cause]**: Confirmed that the MCP server's raw `tools/call` response is a standard `content: [text, image]`, and the nesting only shows up in the event-log fallback path Codex uses to persist an oversized MCP result.
- **[Screenshot bound]**: macOS `ScreenCaptureKit` window screenshots are now adaptively downscaled to a maximum size and target byte count before being encoded as PNG, reducing the chance that complex pages trigger the host-side large-result fallback.
- **[Regression tests]**: Added screenshot compression boundary tests, covering that large images get downscaled and small images keep their original size.
- **[Docs]**: Updated the architecture docs to note that screenshots are still returned as an MCP image block, but with a size/byte-count cap applied, and that coordinate tools continue to map against the actually returned screenshot pixel size.

## Design Motivation

The problem wasn't an extra wrapping layer at the protocol level — it's that when the screenshot PNG is too large, Codex serializes the entire `CallToolResult` into a single text preview to protect rollout storage. Directly changing the MCP shape would break compatibility; the more robust fix is to bound the screenshot result size, so normal `get_app_state` / action-tool returns keep a flat `text + image` structure.

## Files Affected

- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/ARCHITECTURE.md`
