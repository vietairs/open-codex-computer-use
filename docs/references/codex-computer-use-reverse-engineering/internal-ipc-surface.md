# Internal IPC Surface

## Observed Facts

### 1. There is at least one separate ComputerUse IPC protocol between the service and the client

Across both the `SkyComputerUseService` and `SkyComputerUseClient` binaries, the same set of type names shows up consistently:

- `ComputerUseIPCClient`
- `ComputerUseIPCServer`
- `ComputerUseIPCRequest`
- `ComputerUseIPCEmptyResponse`
- `ComputerUseIPCApp`
- `ComputerUseIPCAppState`
- `ComputerUseIPCDiscoveredApp`

This indicates that, beyond:

- the client's external MCP protocol
- the service's host IPC with the Codex appserver

the official implementation also independently maintains a separate `ComputerUseIPC*` protocol layer, handling local calls between the client and the service.

### 2. The internal IPC request types already let us reconstruct a capability table from symbol names

Request types currently visible in both binaries include:

- `ComputerUseIPCListAppsRequest`
- `ComputerUseIPCAppStartRequest`
- `ComputerUseIPCAppModifyRequest`
- `ComputerUseIPCAppPerformActionRequest`
- `ComputerUseIPCAppGetSkyshotRequest`
- `ComputerUseIPCCodexTurnEndedRequest`
- `ComputerUseIPCAppUsageRequest`

Combined with field names and observed MCP tool behavior, the most solid mapping currently is:

- `ListAppsRequest`
  - corresponds to the external `list_apps`
- `AppGetSkyshotRequest`
  - corresponds to the external `get_app_state`
  - `Skyshot` looks like an internal representation of "screenshot + AX tree + structured state"
- `AppPerformActionRequest`
  - corresponds to `click` / `perform_secondary_action` / `set_value` / `scroll` / `drag` / `press_key` / `type_text`
- `AppModifyRequest`
  - includes at least `activate` / `deactivate`
- `CodexTurnEndedRequest`
  - corresponds to the `turn-ended` lifecycle callback

### 3. `get_app_state` is likely, internally, not "directly return app state" but rather "fetch a skyshot"

The strings currently show, together:

- `ComputerUseIPCAppState`
- `ComputerUseIPCSkyshot`
- `ComputerUseIPCSkyshotResult`
- `ComputerUseIPCAppGetSkyshotRequest`
- `SkyshotCapture`
- `RefetchableSkyshotAXTree`
- `SkyshotClassifier`

This suggests the official implementation internally works more like:

1. First capture a `Skyshot` of the target app
2. Then build the screenshot, window, and AX tree from that `Skyshot`
3. Finally have the client assemble the return value exposed to the MCP layer as `get_app_state`

The key point here:

- the external MCP API is called `get_app_state`
- but the internal core abstraction is closer to `skyshot`

This is an important signal for the open-source version:

- if the goal is to replicate official behavior, the core internal model probably shouldn't be named `AppState` directly
- a composite object of "capture result + AX tree + target app metadata" makes more sense

### 4. Action execution internally goes uniformly through `AppPerformActionRequest`

Currently visible fields and coding keys include:

- `ComputerUseIPCAction`
- `ComputerUseIPCLocationSpecifier`
- `CoordinateCodingKeys`
- `ElementIDCodingKeys`
- `ClickCodingKeys`
- `PerformSecondaryActionCodingKeys`
- `SetValueCodingKeys`
- `ScrollCodingKeys`
- `DragCodingKeys`
- `PressKeyCodingKeys`
- `TypeCodingKeys`

Along with the field names:

- `coordinate`
- `elementID`
- `action`
- `text`
- `mouseButton`
- `clickCount`

This suggests the internal action layer has likely been unified into:

- a single action enum
- a single location specifier
  - coordinate mode
  - element ID mode
- a number of concrete action payloads

In other words, the 7 external action-type tools are probably not a fully separate set of methods internally, and more likely variants on the same `performAction` channel.

### 5. App lifecycle is internally separated from tool actions

Also currently visible:

- `ComputerUseIPCAppStartRequest`
- `ComputerUseIPCAppModifyRequest`
- `Modification`
- `ActivateCodingKeys`
- `DeactivateCodingKeys`
- `active`
- `currentApp`
- `isRunning`

This suggests the official implementation splits things into two categories:

- app-level lifecycle
  - launch
  - activate
  - deactivate
- UI actions
  - click / type / scroll / drag / ...

This doesn't fully match the external MCP surface, since it currently doesn't publicly expose:

- `activate_app`
- `deactivate_app`
- `start_app`

but the service clearly retains this capability internally.

### 6. Sender authorization is an explicit part of the internal IPC

`SkyComputerUseService` strings show:

- `ComputerUseIPCSenderAuthorization`
- `ProcessIdentity`
- `CodeSignature`
- `Requirement`
- `SecurityError`
- `Sender process is not authenticated`

This indicates the internal IPC between client and service isn't "any local socket call goes through" — it explicitly verifies the sender's identity.

Combined with what's already been confirmed elsewhere:

- the client itself has parent launch constraints
- an external `python3` / `node` caller gets killed by the system

the more reasonable conclusion now is:

- sender authentication doesn't only happen at the macOS launch-constraint layer
- the service's own internal IPC layer also has a sender authorization / code-signature requirement check

### 7. System permission gating is also part of the internal IPC request

`SkyComputerUseService` strings also show:

- `ComputerUseIPCPermissionResult`
- `ComputerUseIPCRequestRequiringSystemPermissions`
- `ensureApplicationHasPermissions`
- `Failed to request access to permission: %@`
- `Failed to open System Settings for permission: %@`

This shows that internal IPC requests already have a distinct category:

- requests requiring system permissions

In other words, the official implementation isn't just checking "does it have Accessibility / Screen Recording permission" at the outer UI layer — permission requirements are folded into the internal request pipeline.

### 8. The service tracks active IPC clients, and kills itself when there are none

`SkyComputerUseService` strings directly contain:

- `No active Computer Use IPC client processes; terminating service`
- `Codex Computer Use idle timeout reached; terminating service`

This indicates the service's lifecycle isn't a long-lived daemon, but is governed by at least two conditions simultaneously:

- whether there are still active IPC clients
- whether the idle timeout has been reached

So the official service more closely resembles:

- launched on-demand
- kept alive while in use
- self-reclaimed after no connections or an idle timeout

### 9. Both the service and client weakly link `libswiftXPC`

`otool -L` shows:

- `libswiftXPC.dylib (weak)`

but so far there's no observation of:

- an explicit mach service name
- a `launchd` service registration name
- a directly enumerable public XPC endpoint

So currently we can only confirm:

- both binaries have the dependency conditions to use Swift XPC

We cannot confirm:

- whether the current `ComputerUseIPC*` layer is actually built on top of XPC

### 10. App usage behavior and approval state have separate objects

Also currently visible:

- `ComputerUseIPCAppUsageRequest`
- `AppApprovalStore`
- `sessionApprovedBundleIdentifiers`
- `approvedBundleIdentifiers`
- `bundleIdentifiersWithDeliveredInstructions`

This indicates the internals distinguish at least three kinds of state:

- app usage records / ranking
- session-level approval
- whether instructions have already been delivered to a given app

This is much finer-grained than "a single global computer-use permission toggle."

### 11. During a real tool call, still no observed persistent Unix socket between client and service

After actually invoking `get_app_state(Finder)` once, re-inspecting processes and handles:

- `SkyComputerUseService`
  - still stably holds only one Unix socket
  - the peer is `Codex.app`'s `codex-ipc/ipc-501.sock`
- multiple live `SkyComputerUseClient mcp` processes
  - visible handles are basically only:
    - a stdio pipe or TTY
    - `Analytics.db`
    - a small number of system control handles
  - no stable client-service Unix socket observed

Meanwhile the service also shows:

- `No active Computer Use IPC client processes; terminating service`

So the more reliable conclusion right now is:

- the service does track active IPC clients
- but this client-service transport is, at minimum, not a persistent Unix socket that's easy to see via `lsof -U`

This further supports one of a few possibilities:

- XPC / NSXPC
- a short-lived local channel opened per request and closed quickly
- some other transport wrapped by a system service that isn't directly visible as an ordinary socket handle

## Current Inferences

### 1. The official implementation is likely a "three-layer protocol stack," not a single MCP server

The layering that best fits the current evidence is:

1. Codex appserver IPC
   - the private JSON-RPC / thread-event integration between the service and the Codex host
2. ComputerUse IPC
   - the local trusted request protocol between the client and the service
3. MCP
   - the standard tool surface the client exposes externally to the Codex agent runtime

This explains why:

- externally it looks like just a single `SkyComputerUseClient mcp` process
- but in practice you also see parent constraints, sender auth, service idle timeout, and thread-ended cleanup

### 2. `get_app_state` is only the external API name; the internal core object is more like `Skyshot`

If the open-source version wants a clean structure, it should probably also split internally into:

- app targeting
- screenshot capture
- AX tree extraction
- app state serialization

rather than coupling all the logic into a single `get_app_state()` function from the start.

### 3. The public tools are more conservative than the internal capabilities

Capabilities currently visible internally but not exposed externally include at least:

- app start
- app activate / deactivate
- app usage tracking

This suggests the official 9 published tools are a more conservative productized cut, not the full extent of the service's capabilities.

## Current Open Questions

- Does the `ComputerUseIPC*` layer ultimately run over XPC, NSXPC, a private socket, or some other local transport?
- In what scenario is `AppStartRequest` actually used — is it only for establishing the first app session?
- Is `AppUsageRequest` pure analytics/ranking, or does it also factor into approval and security policy?
- What is the exact definition of `Skyshot` — does it include the screenshot, window metadata, AX tree, and URLs, among all other context?
- Is the sender-authorization requirement tied directly to the OpenAI Team ID, or is there a finer-grained bundle / code requirement constraint?
- If it isn't XPC, why does the client-service local transport remain almost invisible during a real call?
