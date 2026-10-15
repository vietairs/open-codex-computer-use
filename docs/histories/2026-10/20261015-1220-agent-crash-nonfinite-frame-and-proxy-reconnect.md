# Agent crash on non-finite frames, and MCP proxies surviving an agent loss

## Symptom

Every Claude and Codex session lost its Open Computer Use MCP connection at the same moment
("Connection closed"), four times between 10:52 and 10:59 on 2026-10-15.

## Cause

The single shared app agent trapped on `Int(Double)` with a NaN or infinite value while rendering
an accessibility frame (`CGRect.renderedLocalFrame`). Each MCP proxy held one socket to that agent
for its whole life and exited when the agent closed it, so one agent crash closed every session.
The element or app that produced the bad frame was not identified.

## Change

- `renderedInt` / `renderedFrameText`: non-trapping Int conversion (non-finite becomes 0, out-of-range
  clamps), applied wherever an accessibility or caller-supplied Double became an Int. Also fixed the
  2^63 `element_index` boundary, the drag delta conversion, and capped scroll page repeats at 100.
- `proxyMCP` survives agent loss: the in-flight call gets an error reply (never replayed; a write that
  provably never reached the agent is resent once), and the next call reconnects. An unterminated agent
  reply counts as a lost connection. The proxy and the agent's accepted sockets use `SO_NOSIGPIPE`.
- A relaunch triggered from the reconnect path starts with lock-screen control off.
- A menu Quit writes a marker next to the agent socket; reconnect and the local scripting tools refuse
  with a clear error until a new MCP host session clears it. A crash still relaunches the agent.

## Known follow-ups

- Several proxies reconnecting at once can start duplicate agents (no cross-process launch lock).
- Dev and release bundles sharing one socket can terminate each other's agent on every alternating call.
- The proxy's reconnect and resend flow has no end-to-end test; only its building blocks do.
- Merging does not deploy: a release and `npm i -g @vietairs/open-computer-use@latest` are needed.
