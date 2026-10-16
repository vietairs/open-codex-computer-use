# Task
Analyse why open-computer-use MCP keeps disconnecting in other Claude sessions today (2026-10-15) and fix it (--auto).

Route: R10 (cause proven) -> R2-style fix in worktree .claude/worktrees/agent-crash-nonfinite-frame (branch fix/agent-crash-nonfinite-frame).

## Root cause (proven)
Shared app-agent (one process, one unix socket, all sessions) crashes with EXC_BREAKPOINT/SIGTRAP:
"Double value cannot be converted to Int because it is either infinite or NaN" in
CGRect.renderedLocalFrame (AccessibilitySnapshot.swift:2590) via TreeRenderer.render -> getAppState/click.
Evidence: ~/Library/Logs/DiagnosticReports/OpenComputerUse-2026-10-15-{105254,105257,105355,105913}.ips (v0.3.10-vietairs.1);
agent restarted 10:59:14. Every MCP proxy holds ONE socket to the agent for its whole life
(MacOSAppAgentProxy.swift proxyMCP/relayMCPLine) and exits on "agent closed the connection" -> every session sees "Connection closed".

## Fix
A. Non-finite-safe Int rendering at every Int(<AX/user double>) site (the crash).
B. MCP proxy survives agent loss: JSON-RPC error for the in-flight request, lazy reconnect for the next (blast radius).
