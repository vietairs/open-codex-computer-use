# Packaging And Lifecycle Integration

## Observed Facts

### 1. The official computer-use plugin root is very thin, exposing only one MCP server

`~/.codex/plugins/cache/openai-bundled/computer-use/1.0.750/` currently visibly contains mainly just:

- `.codex-plugin/plugin.json`
- `.mcp.json`
- `Codex Computer Use.app`
- `assets/app-icon.png`

Not observed:

- `.app.json`
- `skills/`
- `hooks.json`

`.mcp.json` is quite straightforward:

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

This shows that, from the Codex plugin system's perspective, the official `computer-use` is currently mainly:

- A plugin package with UI metadata
- A local MCP server exposed through a nested client app

Not "a composite plugin with skills + app connector + hooks."

### 2. The plugin manifest exposes product UI information, not extra runtime capability

`.codex-plugin/plugin.json` confirms:

- Name: `computer-use`
- Version: `1.0.750`
- `mcpServers` points to `./.mcp.json`
- `interface.displayName` is `Computer Use`
- `interface.brandColor` is `#0F172A`
- `interface.defaultPrompt` has 3 built-in example prompts

Not observed:

- Extra app manifest routing
- Extra skills registration
- A separate hook file

This further shows that the core integration surface the official plugin exposes to the host remains `mcpServers`.

### 3. The main app is a menu-bar / background app with self-update capability

`Codex Computer Use.app/Contents/Info.plist` currently confirms:

- `CFBundleIdentifier = com.openai.sky.CUAService`
- `CFBundleExecutable = SkyComputerUseService`
- `LSUIElement = 1`
- `CFBundleVersion = 750`
- `LSMinimumSystemVersion = 15.0`

Also visible are Sparkle update fields:

- `SUFeedURL = https://oaisidekickupdates.blob.core.windows.net/mac/cua/alpha/appcast.xml`
- `SUPublicEDKey = 5Yw9jMXMH6O3mJZmpFuQT6ECfC3ZKBfVjWUVMNrElRo=`

This shows the official service app is not simply a temporary helper, but:

- Distributed as an independent macOS app
- Running in the background as a menu-bar / agent-style app
- Independently updatable via Sparkle

### 4. The bundle contains three resource bundles, corresponding to different responsibility layers

Currently visible under the main app's `Contents/Resources/`:

- `Package_ComputerUse.bundle`
- `Package_ComputerUseClient.bundle`
- `Package_SlimCore.bundle`

Combined with strings analysis, a fairly stable responsibility split emerges:

- `Package_ComputerUse.bundle`
  - Leans toward the service's core logic
  - Contains `CodexAppServerThreadEventObserver`
  - Contains `CodexAppServerAuthCache`
  - Contains `CodexAppServerJSONRPCConnection`
- `Package_ComputerUseClient.bundle`
  - Leans toward the MCP client / approval / tool layer
  - Contains `ComputerUseMCPServer`
  - Contains `AppApprovalStore`
  - Contains `ComputerUseIPCClient`
- `Package_SlimCore.bundle`
  - Leans toward infrastructure and permission UX
  - Contains `SystemSettingsAccessCoordinator`
  - Contains `SystemSettingsAccessoryWindow`
  - Contains `SystemPermission` / `TCCDialogSystemPermission`

This conclusion is still based on strings, not source-level confirmation, but it's already enough to support a fairly clear three-layer split:

- `ComputerUse`: host integration and core capability
- `ComputerUseClient`: MCP exposure and approval state
- `SlimCore`: general permissions, system-settings guidance, and some infrastructure

### 5. `SkyComputerUseClient`'s external CLI only exposes two subcommands

Running directly:

```text
SkyComputerUseClient --help
```

gets:

```text
USAGE: cua <subcommand>

SUBCOMMANDS:
  mcp
  turn-ended
```

Continuing to check:

```text
SkyComputerUseClient mcp --help
```

gives only:

```text
USAGE: cua mcp
```

while:

```text
SkyComputerUseClient turn-ended --help
```

shows:

```text
USAGE: cua turn-ended [--previous-notify <previous-notify>] <payload>
```

This shows the currently formally exposed CLI surface is very small:

- `mcp`
  - Starts the local MCP server
- `turn-ended`
  - Handles Codex turn lifecycle notifications

### 6. The client binary has a full MCP transport implementation embedded, but the CLI doesn't expose it

`SkyComputerUseClient` strings show:

- `mcp.transport.stdio`
- `mcp.transport.http.client`
- `mcp.transport.http.server.stateful`
- `mcp.transport.http.server.stateless`
- `mcp.transport.sse`
- `mcp.transport.in-memory`

along with corresponding logs:

- `HTTP transport connected`
- `Stateful HTTP server transport started`
- `Stateless HTTP server transport started`
- `Connecting to SSE endpoint`

But combined with the `--help` results, no CLI arguments have so far been observed that allow:

- Selecting the HTTP transport
- Selecting the SSE transport
- Opening an externally connectable HTTP server

So the safer conclusion right now is:

- These transports come from its embedded MCP SDK / shared library capability
- They are not connection methods currently officially supported externally

### 7. `turn-ended` is clearly wired into Codex's legacy notify lifecycle

The local `~/.codex/config.toml` currently contains:

```toml
notify = ["/Users/.../SkyComputerUseClient", "turn-ended"]
```

Also observed:

- `SkyComputerUseClient turn-ended --help`
  - Requires `<payload>`
  - Optional `--previous-notify`
- `SkyComputerUseService` strings
  - `onTurnEnded`
  - `Codex thread ended or stopped conversationID=%s`
  - `Failed to update Codex Computer Use notify hook: %@`
- `Codex` host strings
  - `hooks/src/legacy_notify.rs`
  - `legacy notify payload is only supported for after_agent`
  - `agent-turn-complete`
  - `thread-id`
  - `turn-id`
  - `cwd`
  - `client`
  - `input-messages`
  - `last-assistant-message`

Taken together, this evidence is fairly clear:

- `turn-ended` is not a general command meant for manual invocation by external users
- It is a lifecycle hook that the Codex host calls back during the `after_agent` / `agent-turn-complete` stage
- `<payload>` is very likely the after-agent payload from Codex's legacy notify system
- `--previous-notify` looks very much like a migration parameter for "preserving and chaining the original notify hook"

One more piece of corroborating evidence from the official `codex` open-source source:

- `core/src/config/mod.rs`
  - `notify` is just an argv array
- `hooks/src/legacy_notify.rs`
  - Codex only appends the JSON payload as the last argv argument
- `hooks/src/registry.rs`
  - `legacy_notify_argv` is registered directly as the `after_agent` hook

The open-source core does not have:

- `previous-notify`
- A "chained notifier"
- Any generic mechanism for "wrapping the old notify hook"

So the stronger inference right now is:

- `--previous-notify` is not part of Codex's core hook API
- It's more likely a compatibility argument that `SkyComputerUseClient turn-ended` introduces on its own
- Its purpose is likely: when the official computer-use takes over the `notify` config, it saves the original notifier via `--previous-notify`, so the client can optionally continue to call it when a turn ends

### 8. The `turn-ended` payload structure can now be confirmed directly from the official `codex` open-source source

The current implementation of `codex-rs/hooks/src/legacy_notify.rs` in the official `openai/codex` repo:

- The `notify` config fires after each agent turn completes
- Codex appends a JSON string as the "last argv argument" to the notifier
- This payload only applies to `after_agent`

The `UserNotification::AgentTurnComplete` fields in the source are currently:

```json
{
  "type": "agent-turn-complete",
  "thread-id": "<string>",
  "turn-id": "<string>",
  "cwd": "<string>",
  "client": "<string|null>",
  "input-messages": ["<string>", "..."],
  "last-assistant-message": "<string|null>"
}
```

The historical compatibility wire shape given in the source tests is also:

```json
{
  "type": "agent-turn-complete",
  "thread-id": "b5f6c1c2-1111-2222-3333-444455556666",
  "turn-id": "12345",
  "cwd": "/Users/example/project",
  "client": "codex-tui",
  "input-messages": [
    "Rename `foo` to `bar` and update the callsites."
  ],
  "last-assistant-message": "Rename complete and verified `cargo build` succeeds."
}
```

So the earlier "likely" can now be tightened into a clearer judgment:

- The `<payload>` in `turn-ended <payload>` is at least highly consistent with Codex's current `legacy_notify` after-agent JSON wire shape
- The value of `type` is exactly `agent-turn-complete`
- This command is not a generic free-form input, but a structured payload for a host lifecycle event

### 9. Directly running `turn-ended` from an external shell is also killed by a launch constraint

Running the following two commands directly on this machine:

- A valid JSON payload
- An invalid JSON payload

Both give:

```text
status=137
```

i.e. the subprocess received `SIGKILL`.

The corresponding latest crash report shows:

- `exception = SIGKILL (Code Signature Invalid)`
- `termination.namespace = CODESIGNING`
- `indicator = Launch Constraint Violation`

This shows that when `turn-ended` is called directly from an external shell, the process is already killed by the system via a launch constraint before it reaches any observable business-layer parse / validate step.

So it's currently not possible to distinguish, via external shell fuzzing:

- Whether this command parses the payload first
- Whether a parse failure produces a user-facing error

because the caller hasn't yet been let through by the official host's trust chain.

### 10. The shared container currently shows only analytics, with no sign of an approvals or auth primary store

The current app group container:

- `~/Library/Group Containers/2DC432GLL2.com.openai.sky.CUAService/`

visibly contains very little:

- `.com.apple.containermanagerd.metadata.plist`
- `Library/Application Support/Software/Analytics.db`

Not currently observed in this container:

- Approvals persistence files
- Auth token files
- Explicit service/client coordination state files

This suggests that, so far:

- Analytics does indeed go through app-group sharing
- Approvals, turn lifecycle, and host state are more likely passed in-process or via IPC

### 11. The client has parent launch constraints; no equivalent constraint was observed on the main app

`codesign -d -r- -vvvv SkyComputerUseClient.app` shows:

- `Launch Constraints: Has Parent Launch Constraints`
- `SkyComputerUseClient_Parent.coderequirement` is present in the resources
- The requirement currently reads `team-identifier = 2DC432GLL2`

Whereas the equivalent output for the main app `Codex Computer Use.app` currently shows no matching parent launch constraint line.

This matches the runtime behavior:

- Launching the client directly via an external `python3` / `node` pipe triggers a launch constraint kill
- A long-lived client is essentially launched by the OpenAI-signed Codex host

### 12. The provisioning profile doesn't fully match the actual container/entitlements shown

`embedded.provisionprofile` reads:

- Team: `OpenAI OpCo, LLC`
- TeamIdentifier: `2DC432GLL2`
- `ProvisionsAllDevices = 1`
- `keychain-access-groups = ["2DC432GLL2.*"]`

It also shows application groups:

- service profile:
  - `group.com.openai.sky.CUAService`
  - `2DC432GLL2.*`
- client profile:
  - `group.com.openai.sky.Service`
  - `group.com.openai.sky.CUAService`
  - `2DC432GLL2.*`

But in the `codesign --entitlements :-` output, the currently signed entitlements show:

- `2DC432GLL2.com.openai.sky.CUAService`

And cross-checking against the real group container again shows:

- `~/Library/Group Containers/2DC432GLL2.com.openai.sky.CUAService/`

So what can currently be confirmed is:

- OpenAI has indeed configured an application group / keychain group for this set of bundles
- The real visible container identifier is `2DC432GLL2.com.openai.sky.CUAService`

But it's not yet possible to assert the exact runtime matching relationship of every group name based solely on the provisioning profile's textual display.

## Current Inferences

### 1. The official release artifacts actually split into three layers

The layering that best fits the current evidence is:

- Plugin layer
  - `.codex-plugin/plugin.json`
  - Faces the Codex plugin marketplace and UI presentation
- Client layer
  - `SkyComputerUseClient mcp`
  - Faces the Codex MCP runtime
- Service layer
  - `Codex Computer Use.app`
  - Faces macOS permissions, desktop automation, and host lifecycle

For an open-source version without the official host, what's most worth replicating is:

- The client's external MCP contract
- The service's minimal local-automation capability

Not necessarily worth replicating:

- Sparkle updates
- Private plugin self-installation
- The legacy-notify chaining approach
- The private appserver socket

### 2. `turn-ended` is an interface the open-source version needs to explicitly redesign, not copy verbatim

In the official system, `turn-ended` is:

- Part of host lifecycle integration
- Tied to the `notify` config, chaining with the old hook, and per-turn cleanup

Without the official Codex host, an open-source version should change this layer into a more transparent approach, for example:

- An explicit `session/end` MCP method
- Service-side timeout and cleanup policy
- Or a purely client-side stateless implementation

rather than requiring users to configure yet another privately-semantic `notify` hook.

## Currently Open Questions

- What is the exact value format of `--previous-notify`? A raw command string, a serialized argv result, or some kind of config reference?
- Where is `AppApprovalStore` really persisted, and why is there no obvious file for it in the current app group container?
- Does `Package_SlimCore` carry more cross-product infrastructure beyond permission UX?
- The client binary carries HTTP/SSE transports, but why hasn't the official build exposed these entry points — is it a product choice or a host limitation?
