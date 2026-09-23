# Baseline Architecture

## Observed Facts

### 1. Component Split

The current official bundle contains at least two layers of executable components:

- `Codex Computer Use.app`
  - Executable: `SkyComputerUseService`
  - Bundle identifier: `com.openai.sky.CUAService`
- `Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app`
  - Executable: `SkyComputerUseClient`
  - Bundle identifier: `com.openai.sky.CUAService.cli`

This indicates the official implementation isn't a single binary, but a service app and a client app layered separately.

### 2. How Codex Currently Connects

The local plugin config shows that Codex doesn't call the service directly, but launches an MCP server in `stdio` mode via the built-in client:

```json
{
  "mcpServers": {
    "computer-use": {
      "command": "./Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient",
      "args": ["mcp"],
      "cwd": "."
    }
  }
}
```

Combined with local logs, the current integration method can be confirmed as:

- server name: `computer-use`
- origin: `stdio`
- transport: `stdio`

### 3. The Client's Command-Line Entry Points

`SkyComputerUseClient --help` shows it has at least two subcommands:

- `mcp`
  - Description: `Runs the Computer Use client as an MCP server`
- `turn-ended`
  - Description: `Handles a Codex turn-ended notification`

This shows the client isn't just an MCP wrapper layer — it also explicitly participates in session lifecycle events like "turn ended."

Locally, `~/.codex/config.toml` also shows:

```toml
notify = ["/Users/.../SkyComputerUseClient", "turn-ended"]
```

This indicates that Codex, locally, really does invoke `turn-ended` as a global notification entry point, not an unused debug command.

### 4. Service / Client Share a Security Boundary

The service and client share the same application group:

- `2DC432GLL2.com.openai.sky.CUAService`

Both entitlements also show:

- `com.apple.security.application-groups`
- `com.apple.security.automation.apple-events`

This indicates they belong to the same security boundary, and are expected to share persisted state, permission state, or IPC configuration.

### 5. Capability Surface Exposed by the Service Binary

`SkyComputerUseService` stably shows the following capability modules:

- Permissions and onboarding:
  - `CUAServicePermissionState`
  - `CUAServicePermissionsWindow`
  - `SystemSettingsAccessoryWindow`
- Accessibility / UI tree:
  - `AXNotificationObserver`
  - `SystemFocusedUIElementObserver`
  - `KeyWindowTracker`
  - `WindowOrderingObserver`
- Screenshots and window layer:
  - `ScreenCaptureKit`
  - `SCScreenshotManager`
  - `SCShareableContent`
  - `WindowBoundsObserver`
- Input and interaction:
  - `EventTap`
  - `clickEventTap`
  - `keyboardEventTap`
  - `drag`
  - `scroll`
- Visualization layer:
  - `ComputerUseCursor`
  - `FogCursorStyle`
  - `virtualCursor`
- MCP support:
  - `MCP/Server.swift`
  - `MCP/StdioTransport.swift`
  - `MCP/StatefulHTTPServerTransport.swift`
  - `MCP/StatelessHTTPServerTransport.swift`
  - `MCP/SSEClientTransport.swift`

### 6. Currently Publicly Visible Tools

Both strings and runtime behavior point to the same set of tools:

- `list_apps`
- `get_app_state`
- `click`
- `perform_secondary_action`
- `scroll`
- `drag`
- `type_text`
- `press_key`
- `set_value`

### 7. Currently Visible Tool Schemas in Session

The schemas below are based on the actual MCP tool definitions exposed in a current Codex session, supplemented with usage semantics derived from a runtime call's result.

#### `list_apps`

```json
{}
```

- No parameters.
- Returns the list of apps currently running or used within the last 14 days on this machine.
- The returned text includes the app name, bundle identifier, `running` status, `last-used`, and `uses`.

#### `get_app_state`

```json
{
  "app": "string"
}
```

- `app`: the app name or bundle identifier.
- Its role is to launch or reuse an app-use session, and return the current main window state.
- The runtime return includes at least:
  - the app identifier and pid
  - window hierarchy and the accessibility tree
  - an index number for each element
  - each element's role, value, description, `settable`, and other attributes
  - `Secondary Actions`
  - a screenshot of the current window

#### `click`

```json
{
  "app": "string",
  "element_index": "string?",
  "x": "number?",
  "y": "number?",
  "click_count": "integer? = 1",
  "mouse_button": "\"left\" | \"right\" | \"middle\" ? = \"left\""
}
```

- `app`: the target app.
- `element_index`: locate the click target by accessibility element.
- `x` / `y`: click a target by screenshot pixel coordinates.
- `click_count`: number of clicks, defaults to `1`, usable for double-click or triple-click.
- `mouse_button`: the mouse button, defaults to `left`.
- Semantically, `element_index` and `x` / `y` are two separate addressing schemes, and usually only one should be used at a time.

#### `perform_secondary_action`

```json
{
  "app": "string",
  "element_index": "string",
  "action": "string"
}
```

- `app`: the target app.
- `element_index`: the target accessibility element.
- `action`: the name of a secondary action currently exposed by the element.
- `action` isn't a fixed enum — it must come from the `Secondary Actions` in `get_app_state`'s output.

#### `scroll`

```json
{
  "app": "string",
  "direction": "string",
  "element_index": "string",
  "pages": "number? = 1"
}
```

- `app`: the target app.
- `direction`: constrained by the tool description to `up` / `down` / `left` / `right`.
- `element_index`: must be a scrollable element.
- `pages`: number of pages to scroll, defaults to `1`; the official `1.0.755` tool schema has changed this to `number`, supporting fractional page counts.
- This is an element-scoped scroll, not a global screen scroll.

#### `drag`

```json
{
  "app": "string",
  "from_x": "number",
  "from_y": "number",
  "to_x": "number",
  "to_y": "number"
}
```

- `app`: the target app.
- `from_x` / `from_y`: the drag start pixel coordinates.
- `to_x` / `to_y`: the drag end pixel coordinates.
- In the current public interface, drag only supports coordinates, not `element_index`.

#### `type_text`

```json
{
  "app": "string",
  "text": "string"
}
```

- `app`: the target app.
- `text`: the literal text to type.
- Better suited for plain text entry; it doesn't express keyboard-shortcut semantics.

#### `press_key`

```json
{
  "app": "string",
  "key": "string"
}
```

- `app`: the target app.
- `key`: a key or key combination, in `xdotool key` style.
- Examples from the tool description include:
  - `a`
  - `Return`
  - `Tab`
  - `super+c`
  - `Up`
  - `KP_0`
- The current `1.0.755` binary also has key table strings like `BackSpace`, `Page_Up`, `Prior`, `Next`, `F1...F12`, `KP_0...KP_9`, `KP_Enter`; the open-source parser has already converged on these common xdotool aliases.

#### `set_value`

```json
{
  "app": "string",
  "element_index": "string",
  "value": "string"
}
```

- `app`: the target app.
- `element_index`: the target settable element.
- `value`: the value to write directly; in the current schema this is uniformly a string.
- This is a more semantic input method than `type_text`, suited to controls like search fields and text fields that can be assigned a value directly.

## Current Inferences

### 1. The Official Implementation's Minimal Layering

The most reasonable layering judgment right now is:

- `SkyComputerUseService`
  - Permission management, status bar, window/cursor overlay, system integration, Accessibility, screenshots, approval and session state
  - Also handles host IPC with the Codex appserver, the notify hook, and plugin lifecycle integration
- `SkyComputerUseClient`
  - The MCP entry point, turn lifecycle bridging, and local communication with the service

### 2. Transport Capability and Current Enablement Status Are Not the Same Thing

Although HTTP, SSE, and network-related MCP transport symbols can be seen in the service / client binaries, the currently installed package is actually only enabled via `stdio`. The open-source version's design shouldn't assume the official implementation exposes an HTTP/SSE server externally.

One more note: the current Node MCP SDK's `stdio` framing is newline-delimited JSON, not `Content-Length`. This means if the open-source version wants to be compatible with mainstream Node clients first, the most direct approach is also to stabilize the JSON-line `stdio` path first.

One more layer: the official implementation isn't as simple as "start a local server over stdio." `SkyComputerUseService` also actively connects to a `codex-ipc` Unix socket maintained by the Codex host, and handles thread-end, auth, and plugin integration within it. This means that if the open-source version has no official host, it should explicitly drop this kind of private appserver dependency rather than half-copying a host-bound structure.

### 3. The Open-Source Version Doesn't Need to Replicate the Official Product Shell

Looking at capability, what truly must be reproduced is:

- app discovery
- window screenshots
- accessibility tree reading
- mouse/keyboard actions
- permission onboarding
- session state and approval model

### 4. The Current Tool Surface Is a Minimal Interface Layer Centered on the Accessibility Tree

The current set of public tools can be compressed into three layers:

- Discovery:
  - `list_apps`
- Read state:
  - `get_app_state`
- Take action:
  - `click`
  - `perform_secondary_action`
  - `scroll`
  - `drag`
  - `type_text`
  - `press_key`
  - `set_value`

This indicates the official implementation currently exposes a very small automation kernel, not a full desktop control API.

### 5. `element_index` Is a First-Class Citizen; Coordinates Are Only a Supplementary Locator

Most interaction tools work around the accessibility tree produced by `get_app_state`:

- `perform_secondary_action`
- `scroll`
- `set_value`
- `click`'s primary mode

Only a few actions are clearly pure geometric operations:

- `drag`
- `click`'s `x` / `y` mode

This means the official implementation prioritizes AX-semantic locating, rather than treating the screenshot as the primary navigation surface.

### 6. The Open-Source Compatibility Layer Should Best Keep an Aggregate `get_app_state`

The current public interface has no separate:

- `launch_app`
- `screenshot`
- `get_ax_tree`
- `wait`
- `hover`

Instead, "launch a session if needed + read the window tree + read the screenshot" are merged into `get_app_state`. If one of the open-source version's goals is compatibility with existing agent usage habits, keeping this aggregate entry point will be more stable.

Product-shell items like the status bar, virtual cursor, and PIP can come after the core automation path.

## Direct Implications for the Open-Source Version

- The MCP server can be designed as a standalone, public, stable entry point that any client can launch, without having to reuse the official's host-bound approach.
- The service/client boundary should be made explicit as early as possible, otherwise it's easy to get bitten later by the private host constraints seen during reverse engineering.
- Transport, permissions, the automation kernel, and the UI/overlay are best split into independent modules, avoiding directly copying the multi-layer coupling seen during reverse engineering straight into the open-source implementation.
- The open-source schema can directly align with these 9 tools as the first version of the compatibility layer, then internally split the implementation into app discovery, AX snapshot, screen capture, input dispatcher, and approval/session manager.
