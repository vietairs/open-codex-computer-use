# Evidence: where the time goes in a computer-use action loop

Date: 2026-09-29 19:40 AEST. Source: this session's Mail "combio" run (0.3.9-vietairs.1, auto permission mode), plus
direct MCP stdio timing of the installed server outside Claude Code.

## Outcome

One Mail step (think → call → result) costs about 9 seconds. Around 4s is the main agent thinking, about 1.3s is the
Claude Code per-call permission review, and 3–3.5s is the server itself. JEV (`decide_next_action`) is not in the loop
at all right now: its three calls took 10–15s each and timed out.

## Measurements

| Segment | Measured | How |
|---|---|---|
| Agent think between OCU calls | median 4.1s, mean 4.6s (n=18) | transcript: previous tool_result → next tool_use |
| OCU action call, in session (click / press_key / type_text / set_value) | median 4.3–5.0s | transcript: tool_use → tool_result |
| OCU `get_app_state` Mail, in session | 5.05–7.06s | transcript |
| OCU `get_app_state` Mail, direct MCP stdio | 1.41–1.62s | `scratchpad/mcp_time.py` |
| OCU `get_app_state` Finder, direct | 0.12–0.16s | same |
| Per-tool hooks (buddi ×2, usage-quota) | ~0.1s each | `scratchpad/time-tool-hooks.py` |
| Read tool (no permission review) | median 0.19s (n=11) | transcript, last 6 sessions |
| Bash ls/cat/grep (auto-mode review) | median 1.57s (n=81) | same |
| `decide_next_action` remote jev | 10.6–15.2s, all timed out | transcript |

## Why the server is slow per action (source)

- Every action runs `currentSnapshot` (cached per service instance, `ComputerUseService.swift:961`) then
  `refreshSnapshot` after acting, a full accessibility walk that costs about 1.5s on Mail.
- Fixed sleeps of 0.1–0.25s per action (`ComputerUseService.swift:642-1223`, `InputSimulation.swift:51-364`), plus the
  software-cursor travel animation (`SoftwareCursorOverlay.animateMove`).
- Action results use style `.actionResult`, which attaches the PNG screenshot (`ComputerUseService.swift:2068`).
  Several Mail click results were 290–356 KB, which enlarges every later agent turn.
- One MCP call does exactly one action (`ToolDefinitions.swift`), so N actions cost N agent turns plus N permission
  reviews plus N before/after snapshot pairs.

## Why the agent thinks between every action

- The MCP server instructions tell agents to "call `get_app_state` every turn" and to verify after each action.
- There is no way to hand the server a short, fully specified sequence such as "focus field, type, press Return".

## Constraint that shapes the fix

Memory `mcp-server-never-owns-a-goal` (locked 2026-09-22): the server may propose and execute but never own a goal or
run its own planning loop. A bounded `decide_and_act` lease was explicitly deferred as a separate decision.

## Unresolved questions

- Is the service (and its snapshot cache) persistent across calls in the app agent, or rebuilt per request? This
  decides whether the pre-action snapshot is a cache hit.
- How much of the ~3.5s in-session gap is permission review versus result transfer of large PNG payloads?
