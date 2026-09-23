# Runtime And Host Dependencies

## Observed facts

### 1. `SkyComputerUseClient mcp` cannot be connected to directly by just any external client

Running directly on this machine:

```text
SkyComputerUseClient mcp
```

If run as a one-shot shell command, it can exit quickly; but under a PTY with `stdin` held open, the process can stay alive and wait for input.

This shows that:

- The `mcp` subcommand genuinely exists.
- Observing "a one-shot shell execution ends quickly" alone doesn't prove host validation failed — part of that behavior is just `stdin`/EOF handling.

### 2. Failure modes when connecting directly via Inspector

When launched with the MCP Inspector over `stdio`, two kinds of failures showed up:

- When the arguments were wrong:
  - `spawn -y ENOENT`
  - This is an Inspector configuration error, not a problem with the server itself.
- After fixing the command:
  - Inspector successfully set up the stdio client/server transport
  - The other side then disconnected quickly, and Inspector reported `write EPIPE`

`EPIPE` here indicates the child process has already exited, and Inspector's write of the initialization message to its stdin hit a broken pipe.

### 3. Launching via an external pipe/stdin triggers a codesigning kill

Launching on this machine via the following methods, respectively:

- `node`'s `child_process.spawn(..., stdio: ['pipe', 'pipe', 'pipe'])`
- `python3`'s `subprocess.Popen(..., stdin=PIPE, stdout=PIPE, stderr=PIPE)`
- The Python MCP SDK's `stdio_client(...)`

All reliably reproduce:

- The child process quickly receives `SIGKILL`
- The parent process sees `Broken pipe` or `EPIPE`
- On the Python MCP SDK path, `stdio_client` first successfully enters `spawn`, but `ClientSession.initialize()` throws `anyio.BrokenResourceError` during the write

By contrast:

- Running `SkyComputerUseClient mcp` directly under a PTY, the process can stay resident waiting for input

This shows the current bundle distinguishes at least between:

- Interactive terminal launches
- Automated launches by an external process via pipe/stdin

### 4. Every Inspector / Node / Python SDK attempt leaves behind a crash report

`~/Library/Logs/DiagnosticReports/` shows multiple `SkyComputerUseClient-2026-04-17-1142xx.ips` files, and these crash reports share the following characteristics:

- `parentProc`: `node` or `python3`
- `exception`: `SIGKILL (Code Signature Invalid)`
- `termination.namespace`: `CODESIGNING`
- `indicator`: `Launch Constraint Violation`

Currently this only confirms:

- Some client processes launched by an external automation caller via pipe/stdin are killed by the system due to a launch constraint violation.
- The minimal Python MCP SDK reproduction did not get around this constraint either — it shares the same root cause as Node / Inspector.

Currently unconfirmed:

- Whether this is the only reason "an external caller can't connect directly."

The reason this can't be confirmed is that the client stays alive fine under a PTY, while the crash reports are mainly tied to the pipe/stdin automated-launch path.

### 5. Every stably-alive client process hangs off an OpenAI-signed Codex process

The `SkyComputerUseClient mcp` processes that stay alive long-term on this machine currently have two kinds of parent processes:

- `/Applications/Codex.app/Contents/Resources/codex app-server --analytics-default-enabled`
- The Homebrew-installed `codex` binary:
  - `/opt/homebrew/lib/node_modules/@openai/codex/.../codex`

Both kinds of parent processes share:

- The same TeamIdentifier: `2DC432GLL2`

By contrast:

- When `python3` is the parent process, the client gets killed by the system due to a `Launch Constraint Violation`.

This further supports the current assessment:

- The parent launch constraint is very likely not a generic "any shell/any local caller" restriction, but rather requires the parent process to satisfy OpenAI's own signing boundary.

### 6. The client clearly contains host/auth-related strings

The `SkyComputerUseClient` strings directly show:

- `Sender process is not authenticated`
- `Could not find Service app`
- `sessionApprovedBundleIdentifiers`
- `approvedBundleIdentifiers`
- `ComputerUseIPCClient`
- `ComputerUseIPCRequest`
- `ComputerUseIPCAppState`
- `ComputerUseIPCAppPerformActionRequest`

These strings show the client explicitly accounts for at least:

- Sender identity authentication
- Locating the service app
- Session-based app approval state
- A local IPC request model

### 7. The service explicitly connects to the Codex appserver's Unix socket

When the official `computer-use` tool is actually invoked and brings up the service, we can directly observe:

- `SkyComputerUseService` opens an anonymous Unix socket FD
- The peer is held by the `Codex.app` process at:
  - `/var/folders/.../T/codex-ipc/ipc-501.sock`

Local `lsof` has confirmed:

- `SkyComputerUseService`'s Unix socket peer points to `Codex.app`
- `Codex.app` itself holds and listens on `codex-ipc/ipc-501.sock`

This is one of the most direct pieces of local IPC evidence currently available.

### 8. The service binary already explicitly contains Codex appserver IPC semantics

The `SkyComputerUseService` strings directly include:

- `CodexAppServerThreadEventObserver`
- `CodexAppServerJSONRPCConnection`
- `CodexAppServerAuthCache`
- `CodexAppServerAuthProvider`
- `Connected to Codex appserver IPC socket at %s`
- `Failed to connect to Codex appserver IPC socket:`
- `Codex appserver IPC connection closed before a complete frame was read`
- `Codex thread ended or stopped conversationID=%s`

This shows the service and the Codex host don't have a loose relationship — there is a clearly defined appserver IPC / JSON-RPC integration layer between them.

### 9. The service also shows traces of self-installing a plugin / notify hook

The `SkyComputerUseService` strings also show:

- `Failed to update Codex Computer Use notify hook: %@`
- `Failed to install Codex Computer Use plugin: %@`
- `Skipping Codex Computer Use self-install for plugin-managed app.`
- `Couldn't find running Codex app, falling back to using Codex CLI in PATH via /usr/bin/env`
- `Found codex CLI executable in running Codex application at %{public}s`

This shows the service takes on at least:

- Installing / updating a plugin into the Codex host
- Updating the `turn-ended` notify hook
- Discovery and fallback between the `Codex.app` and `codex` CLI hosts

### 10. The official MCP stdio framing is JSON lines

From the `@modelcontextprotocol/sdk` bundled with the local Inspector, we can confirm the current Node SDK's stdio transport uses one JSON-RPC message per line:

```js
export function serializeMessage(message) {
  return JSON.stringify(message) + '\\n';
}
```

In other words, the current official Node SDK's stdio MCP does not use `Content-Length` framing — it's newline-delimited JSON.

This conclusion was further pinned down by a one-off Python reproduction experiment. The experiment's path was:

1. Use the Python `mcp` SDK's `stdio_client` to launch `SkyComputerUseClient mcp`
2. `stdio_client` first successfully enters `spawn`
3. `ClientSession.initialize()` throws a `BrokenResourceError` during the write
4. The system generates a new `SkyComputerUseClient-*.ips`, still terminated for `Launch Constraint Violation`

The repository was later cleaned up and this one-off Python / `uv` probe was removed, since the repo does not maintain a Python runtime chain; what's kept here is the experimental conclusion, not a currently executable entry point.

### 11. The service / client share an application group

Both declare the same application group in their entitlements:

- `2DC432GLL2.com.openai.sky.CUAService`

The corresponding group container on this machine currently visibly contains:

- `~/Library/Group Containers/2DC432GLL2.com.openai.sky.CUAService/Library/Application Support/Software/Analytics.db`

### 12. Shared analytics shows launch events

The following events have already been observed in `Analytics.db`:

- `$set`
- `cua_service_launched`
- `computer_use_mcp_server_launched`
- `cua_service_idle_timeout_reached`

This shows:

- The service and client share at least one analytics/persistence layer.
- The service has an idle-timeout concept — it isn't meant to run permanently in the foreground.
- This most recent Python SDK reproduction attempt did not leave a new `computer_use_mcp_server_launched` event, suggesting it may have been killed by the system before the client could report its own launch.

### 13. `turn-ended` very likely goes through an independent IPC request

The `SkyComputerUseClient` strings show:

- `ComputerUseIPCCodexTurnEndedRequest`
- `ComputerUseCodexTurnEndedCommand`
- `CodexTurnEndedNotification`

Combined with `~/.codex/config.toml`'s:

```toml
notify = ["/Users/.../SkyComputerUseClient", "turn-ended"]
```

We can now confirm:

- `turn-ended` is not a meaningless placeholder command.
- The client defines at least a separate IPC request model for "a Codex turn has ended."

### 14. The client itself carries a parent launch constraint

`codesign -d --verbose=5 SkyComputerUseClient.app` directly shows:

- `Launch Constraints:`
  - `Has Parent Launch Constraints`

The bundle also contains:

- `Contents/Resources/SkyComputerUseClient_Parent.coderequirement`

This file is currently a plist that declares at least:

- `team-identifier = 2DC432GLL2`

This shows the restriction on external callers isn't purely an application-layer policy — it's part of the bundle's signing / launch constraint.

### 15. Running `turn-ended` directly from an external shell also triggers a launch-constraint kill

Running directly from a shell on this machine:

- `SkyComputerUseClient turn-ended '<valid-json>'`
- `SkyComputerUseClient turn-ended '{bad-json}'`

Both return:

```text
status=137
```

And the latest crash report shows:

- `exception`: `SIGKILL (Code Signature Invalid)`
- `termination.namespace`: `CODESIGNING`
- `indicator`: `Launch Constraint Violation`

This shows:

- It's not just the `mcp` subcommand that's restricted
- The `turn-ended` lifecycle subcommand also goes through the same trusted-caller restriction when invoked from an external shell

So `turn-ended` currently cannot be treated as "an independently callable debugging entry point."

### 16. No publicly exposed socket / launchd service has been observed yet

Current inspection results:

- No `SkyComputerUseService` listening on a TCP port has been found.
- No stably visible Unix socket exposed to external clients has been found.
- `launchctl print gui/<uid>/com.openai.sky.CUAService` finds no public service of that name.

This suggests that if the client and service communicate locally, it's more likely via:

- Private XPC / app group / bundle-discovery mechanisms
- Or some other in-host communication not directly exposed to arbitrary external processes

### 17. `1.0.755` added service-side sender authorization for the raw app-server helper

On 2026-04-21, when re-checking the official bundled `computer-use` `1.0.755`, a new divergent behavior showed up on the same machine:

- `scripts/computer-use-cli`'s `app-server` mode can still see the official `computer-use`'s 9 tools via `mcpServerStatus/list`.
- But launching a temporary `codex app-server` from an external shell, and then calling `mcpServer/tool/call list_apps`, returns:

```text
Apple event error -10000: Sender process is not authenticated
```

The system log splits this failure into two stages:

- `SkyComputerUseClient` sends an `SkCu/SndR` request to `SkyComputerUseService` via Apple Events.
- TCC returns `ACCESS GRANTED` for this Apple Events request.
- The service side then goes through several rounds of signature / trust verification activity, and outputs error logs under the `Computer Use` category.
- The failure path never shows `Tracking Computer Use IPC client process ...`.

Compared with a normal Codex agent/tool call to the official `computer-use` in the same round:

- `list_apps` returns successfully.
- The service first starts the `Codex AppServer Thread Events` observer and connects to the `codex-ipc` socket.
- The service then logs `Tracking Computer Use IPC client process ...`.

So the more accurate assessment now is:

- The `codex app-server` binary, signed by OpenAI, can satisfy `SkyComputerUseClient`'s parent launch constraint.
- Satisfying the parent launch constraint does not mean a tool call has passed the official Computer Use's sender authorization.
- The official service also requires the request to come from a Codex/ComputerUse IPC client it can authenticate and track; a raw app-server thread created temporarily by an external helper can no longer reliably reuse that private channel.

## Current inferences

### 1. The client is very likely not an independent product boundary, but a host-bound bridging layer

The judgment that best fits the evidence right now is:

- `SkyComputerUseClient` is responsible for wrapping local computer-use capability into MCP
- But it truly depends on `Codex Computer Use.app` or a trusted host context
- So it doesn't behave like a generic, publicly reusable MCP server that any external caller can freely use

### 2. Direct external connection failures involve at least two layers of risk

The risks observed so far fall into at least two categories:

- macOS launch constraints directly intercept external automated launches
  - Evidence: `CODESIGNING / Launch Constraint Violation`
  - Evidence: `Has Parent Launch Constraints`
- Service-side sender authorization rejects tool calls initiated by a raw helper
  - Evidence: Apple Events/TCC already returns `ACCESS GRANTED`, yet the call still returns `Sender process is not authenticated`
  - Evidence: the success path logs an active Computer Use IPC client; the failure path does not
- The host integration layer internally still depends on Codex appserver / auth / plugin lifecycle
  - Evidence: `CodexAppServerJSONRPCConnection`
  - Evidence: `CodexAppServerAuthProvider`
  - Evidence: `Connected to Codex appserver IPC socket at %s`
- Host authentication / service-lookup failures
  - Evidence: `Sender process is not authenticated`, `Could not find Service app`

These two categories of problems cannot currently be merged into a single root cause.

### 3. The official implementation has "session-level app approval"

Strings like `sessionApprovedBundleIdentifiers` show that the official implementation doesn't just gain full control over every app once it has system-level Accessibility/Screen Recording permission — it also maintains a finer-grained, session-level approval state.

For the open-source version, this is an important product boundary:

- Whether a given app is allowed to be controlled by computer-use
- Whether that permission is one-time, session-level, or permanent

This should be an explicit design decision, not something scattered throughout the code.

## Currently open questions

- Besides the appserver socket, does the service and client also use XPC, app-group file coordination, or some other IPC mechanism?
- Besides the team identifier, does `SkyComputerUseClient_Parent.coderequirement`'s parent launch constraint have any finer-grained source of restriction?
- Beyond session cleanup, does the `turn-ended` subcommand also participate in approval-state syncing, idle-timeout refresh, or background app reclamation?
- Where is `approvedBundleIdentifiers` persisted — is it only kept in-process?
- Does the official side have any plan to expose a supported local debugging entry point, letting external tools probe the bundled `computer-use` without reusing the private sender authorization?
- What are the specific JSON-RPC methods and the authentication process running over `codex-ipc/ipc-501.sock`?

## Suggestions for the next round of analysis

- For further reproduction experiments, prefer writing a fresh minimal stdio client on the spot, rather than relying on Inspector or leaving a one-off probe checked into the repo long-term.
- Keep investigating traces of XPC, mach services, bundle lookup, and app-group reads/writes for the service / client.
- Do another round of strings / runtime analysis specifically targeting the `turn-ended` subcommand.
- Do a finer-grained timeline comparison of analytics / preferences / group container data, to observe which approval and lifecycle events get written during one real Codex session.
