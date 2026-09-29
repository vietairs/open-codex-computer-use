# Fast non-screenshot channels for the macOS runtime

## Goal

Make continuous computer use on macOS cheaper per step by adding channels that avoid a screenshot and a full
accessibility-tree render: a lean `find_elements` search that runs in the app agent, and an opt-in scripting channel
(`run_script`, `get_scripting_dictionary`, `open_url`, `run_shortcut`, `list_shortcuts`) answered by the MCP relay.
The server still proposes and executes tool calls only; it never plans a goal.

## Scope

- In scope: `find_elements` with a process-global index allocator; a relay-local channel router gated by
  `OPEN_COMPUTER_USE_ENABLE_SCRIPTING`; a confined `osascript` runner, a script filter, an audit log, a static
  scripting-dictionary reader and a URL/Shortcuts launcher; instruction text, skill docs, architecture and security
  docs.
- Out of scope: any server-side planner or goal loop; changes to the Go runtimes; changing the lock policy or the
  app-agent peer authentication; a new CLI path for the scripting tools.

## Background

- Related docs: `docs/ARCHITECTURE.md`, `docs/SECURITY.md`, `skills/open-computer-use/references/scripting.md`.
- Related code paths: `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/` (`LocalChannelRouter`,
  `LocalChannelToolHandlers`, `LocalChannelGuidance`, `ConfinedChildProcessRunner`, `ScriptAuditLog`,
  `MCPServer.swift`), `apps/OpenComputerUse/` (relay wiring).
- Known constraints: scripts run as a child of the MCP server and use the host's Automation grant, never
  `Open Computer Use.app`'s; the local tools must be unreachable through the app-agent socket and the CLI.

## Risks

- Risk: on an MCP-only host, enabling the flag is equivalent to granting a shell, and the shell-verb filter can be
  bypassed. Mitigation: off by default, flag read only from the relay's own environment, every script text audited,
  documentation that says so plainly, and a recommended named-tool allow list.
- Risk: a killed or orphaned script keeps running inside the target app. Mitigation: small-query guidance, timeouts
  with process-group kill, and documentation of the residual behavior.
- Risk: a stale `find_elements` index resolves to another element. Mitigation: monotonic allocator, merge only on a
  matching window.
- Risk: instruction text edits conflict with other work on the same file. Mitigation: keep the edit to three lines and
  interpolate the AppleScript line from one shared constant.

## Milestones

1. Implement `find_elements` and the confined runner, filter and audit log with unit tests.
2. Add the dictionary reader, launcher and router, then wire the relay and the direct stdio loops.
3. Update instructions and docs, review the security posture, and measure on a live build.

## Verification

- Commands: `swift build`; `swift test`; `bash scripts/check-docs.sh`.
- Manual checks: with the flag on in a host that runs outside cmux, run a narrow `run_script` against Mail and confirm
  a request and result appear in the audit log.
- Observational checks: median latency of a narrow scripted read against a full `get_app_state`.

## Progress Log

- [x] Implement `find_elements`, confined runner, filter, audit log, dictionary reader and launcher.
- [x] Add the router and wire the relay and direct stdio loops.
- [x] Update instruction text and docs.
- [ ] Live measurement and security probes on a rebased build.

## Decision Log

- 2026-09-29: the scripting tools are answered by the relay, not the app agent, so a same-uid socket peer cannot reach
  them through the agent's grants; accepted cost is that they use the host's Automation grant.
- 2026-09-29: the script filter is documented as friction, not a boundary; no signal forwarding to script children.
- 2026-09-29: full-mailbox search in Mail goes through Mail's search field, because a large `whose` query stalls Mail
  for 20 to 60 seconds; scripts stay narrow.
