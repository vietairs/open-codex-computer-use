# `scripts/computer-use-cli`

This directory holds a standalone Go CLI that does two kinds of things:

- Probes the closed-source `computer-use` bundled with the official Codex desktop app
- Connects directly to a plain stdio MCP server, such as this repo's own `open-computer-use`

It is not one of the repo's main deliverables, but a debugging/reverse-engineering helper tool.

## Why it's needed

On this machine, the official bundled `computer-use` executable, `SkyComputerUseClient`, cannot be reliably launched directly by a plain, unsigned MCP client.

Confirmed symptoms:

- A standard stdio MCP client exits before the handshake
- The official Go MCP SDK's own sample also fails
- The crash report points to `Launch Constraint Violation` / `CODESIGNING`

Conclusion: this is not simply an MCP protocol compatibility issue, but a host code-signing/parent-process constraint, combined with the official service's own sender authorization. To probe the official bundled `computer-use`'s tool list, you can go through a signed Codex host via `codex app-server`'s `mcpServerStatus/list`; real tool calls should no longer depend on this raw helper.

## Location

```text
scripts/computer-use-cli/
```

The directory is itself a standalone Go module, with its own `go.mod`, unit tests, and README.

## Default AI usage

If the goal is "verify whether the official Codex-bundled `computer-use` can list tools," prefer running it like this:

```bash
cd scripts/computer-use-cli
go run . list-tools --transport app-server
```

If the goal is to verify a scriptable tool call, prefer pointing it at this repo's `open-computer-use` direct server.

The default `auto` mode selects automatically:

- The official bundled `computer-use` -> `app-server`, currently only suitable as a tool-list probing path
- An explicitly passed non-Sky server binary -> `direct`

By default, the local compatibility test first tries to resolve the non-translocated `1.0.750` legacy install root under `~/.codex/plugins/computer-use`, and checks its plugin manifest version. If that legacy root is absent, it falls back to `~/.codex/plugins/cache/.../1.0.750`, and finally to the latest installed version. To compare against a different version, pass it explicitly:

```bash
COMPUTER_USE_PLUGIN_VERSION=1.0.755 go run . resolve-server
go run . resolve-server --plugin-version latest
go run . list-tools --transport app-server --plugin-version host
```

`--plugin-root`/`--server-bin` take priority over version selection. Version selection only affects `resolve-server`, the target path for the direct launch, and the temporary `mcp_servers."computer-use"` override passed to `codex app-server`. When you need to use the Codex host's own MCP config entirely as-is, pass `--plugin-version host`. Codex CLI's `-c` override only splits keys on `.` and does not parse a quoted dotted key, so the implementation actually uses `mcp_servers.computer-use.*`.

## The two transports

### 1. `app-server`

For the official bundled `computer-use`.

```bash
cd scripts/computer-use-cli
go run . list-tools --transport app-server
```

This mode:

1. Starts `codex app-server`
2. Creates an ephemeral thread
3. Calls the target server via `mcpServer/tool/call`

As of official bundled `computer-use` `1.0.755`, this raw helper path can only be reliably used for tool-list probing; an actual `mcpServer/tool/call` may return:

```text
Apple event error -10000: Sender process is not authenticated
```

Re-checking the logs shows Apple Events/TCC has already accepted the request, and `SkyComputerUseService` then rejects the call at its own sender authorization/active IPC client tracking layer. So this is not a reliable, general-purpose entry point for "calling the official computer-use directly from outside." When you need a real call into the official tools, prefer the normal Codex agent/tool call chain; when you need a scriptable direct connection, use this repo's `open-computer-use` direct mode.

The local compatibility test defaults to temporarily overriding the app-server's `computer-use` MCP config to `1.0.750`. In the current workspace, the `1.0.750` under cache carries `com.apple.quarantine`, so LaunchServices will AppTranslocate the service, and `call list_apps` returns `Apple event error -1708: Unknown error`; the non-translocated legacy install root under `~/.codex/plugins/computer-use` can call `list_apps` normally.

If the local Codex executable is not in the default location, you can specify it explicitly:

```bash
CODEX_APP_SERVER_BIN=/Applications/Codex.app/Contents/Resources/codex \
go run . list-tools --transport app-server
```

### 2. `direct`

For a plain stdio MCP server, such as this repo's locally built `open-computer-use`.

```bash
cd scripts/computer-use-cli
go run . call list_apps \
  --transport direct \
  --server-bin ~/.codex/plugins/cache/open-computer-use-local/open-computer-use/0.1.7/scripts/launch-open-computer-use.sh
```

## When to stop retrying `direct`

If the target is the official `SkyComputerUseClient`, and you've already seen symptoms like the following, don't waste more time trying "a different generic MCP client":

- `EOF`
- `broken pipe`
- exits before initialization
- `Launch Constraint Violation` appears in the crash report

In these cases, switch back to `app-server` mode first.

## Local verification

```bash
cd scripts/computer-use-cli
go test ./...
```

If you just want a quick sanity check that the toolchain isn't broken, the minimal positive verification is usually:

```bash
cd scripts/computer-use-cli
go run . list-tools
go run . call list_apps --transport direct --server-bin /path/to/open-computer-use
```
