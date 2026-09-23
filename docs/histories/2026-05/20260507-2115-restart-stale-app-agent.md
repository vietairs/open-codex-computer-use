# Automatically replace a stale app-agent

## User Request

Keep improving `open-computer-use`'s consistency with the official tools, and reduce the need to manually restart the hidden app-agent after every build.

## Main Changes

- Added an `agentInfo` request to the app-agent socket, returning the current bundle, executable, and the agent process's start time.
- When the CLI proxy connects to an existing socket, it validates whether the agent comes from the current bundle and whether its start time is later than the current executable's modification time.
- If the existing agent is stale or doesn't support `agentInfo`, the proxy discards the old socket and spins up a new Dev app-agent.
- The new agent supports a `terminate` request, allowing it to exit gracefully on subsequent replacement.

## Design Intent

A local debug build replaces `dist/Open Computer Use (Dev).app` in place, but the old hidden app-agent may keep holding onto the old code, causing Codex to still get stale tool behavior after a restart. Using a lightweight handshake based on agent self-reported info and the executable's mtime lets the proxy automatically detect and replace a stale agent before connecting.

## Verification

- `swift test`
- `./scripts/build-open-computer-use-app.sh debug`
- `./scripts/run-tool-smoke-tests.sh`
- `./scripts/check-docs.sh`
- `git diff --check`
- The normal proxy path's `call list_apps` verified that a new agent is auto-spun-up, and `frontmost` is output

## Files Affected

- `apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift`
