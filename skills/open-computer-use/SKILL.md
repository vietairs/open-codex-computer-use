---
name: open-computer-use
description: Platform-neutral guidance for using Open Computer Use, the open-source Computer Use MCP server and CLI for macOS, Linux, and Windows. Use when an agent needs to install, verify, troubleshoot, configure, or operate Open Computer Use through its native CLI, stdio MCP server, or direct Computer Use tool calls.
---

# Open Computer Use

## Overview

Open Computer Use exposes Computer Use as a local CLI and stdio MCP server. It is not Codex.app-specific; adapt the commands and MCP config to the agent runtime you are operating in.

The macOS runtime requires macOS 14.0 or later. Windows and Linux use their own platform runtimes and are not subject to this macOS minimum.

It supports the same core tool surface across macOS, Linux, and Windows:
`list_apps`, `get_app_state`, `click`, `perform_secondary_action`, `scroll`,
`drag`, `type_text`, `press_key`, and `set_value`.
On macOS, `perform_actions` also runs a short, fully specified action sequence in one call; the Linux and Windows runtimes do not have it.
On macOS the server also exposes `find_elements`, a lean accessibility search (see "Fast channels" below).
On macOS an optional, experimental `decide_next_action` advisory tool is also available when a local decision model
is configured; see [references/decision-model.md](references/decision-model.md).

## Core Workflow

1. On macOS, run `sw_vers -productVersion` before invoking the CLI and require macOS 14.0 or later. On older versions, explain that the runtime cannot launch; do not recommend `doctor` or permission changes as a fix for binary incompatibility.
2. Check the CLI is installed with `open-computer-use -h` or `ocu -h`. If installation or setup is missing, read [references/installation.md](references/installation.md).
3. On supported macOS versions, run `open-computer-use doctor` before the first real GUI task. If permissions are missing, ask the user to approve Accessibility and Screen Recording in the onboarding UI.
4. Inspect available apps before acting: `open-computer-use call list_apps`.
5. Capture current UI state with `open-computer-use call get_app_state --args '{"app":"TextEdit"}'`. The default state is usually enough for UI operation.
6. When the task needs longer semantic text, such as chat history, email bodies, document text, or long form content, call `get_app_state` with `text_limit: 1000` or `text_limit: "max"`.
7. When visible long pages or lists appear incomplete even after scrolling, call `get_app_state` with a larger `max_tree_nodes` or `max_tree_depth`.
8. Prefer element-targeted actions using `element_index` from the latest `get_app_state` or action result. On macOS, action results are text-only; pass `include_screenshot: true` when you need to see the window. Linux and Windows action results still carry the screenshot, and their schemas reject `include_screenshot`. A macOS window that is off stage in Stage Manager has no screenshot: use `element_index` actions only, since x/y input fails there.
9. On macOS, batch short sequences you can fully specify (focus a field, type, press Return) into one `perform_actions` call; keep externally visible steps such as Send in their own call.
10. For multi-step CLI work, use `open-computer-use call --calls '<json-array>'` so one process can reuse the latest element index mapping.
11. For agent runtimes that support local MCP servers, configure `open-computer-use mcp` or `ocu mcp` and call the exposed Computer Use tools directly. Read [references/usage.md](references/usage.md).
12. If communication, permission, or desktop-session access fails, read [references/troubleshooting.md](references/troubleshooting.md).

## Operating Rules

- Treat the target desktop as the user's real session. Do not inspect password managers, unrelated private content, or sensitive apps unless the user explicitly asked for that task.
- Ask before sending, deleting, purchasing, approving, uploading, or making other externally visible changes.
- Do not assume Codex.app plugin helpers are available. Use the installed `open-computer-use` / `ocu` CLI or an explicit MCP config.
- Always run `get_app_state` at the start of a turn before using `element_index`; within a turn, use indices from the latest `get_app_state` or action result. Do not guess indexes across sessions or after large UI changes.
- Prefer semantic actions and `set_value` for editable controls. Use coordinate `click`, `scroll`, and `drag` only when the element tree does not expose a safer target.
- On macOS, do not enable `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1` unless the user explicitly requested `click_method: "global"`, a `drag` that must drive a window-server drag session (window move, drag-select text, Finder drag-and-drop), or other diagnostic behavior that may move the real pointer. Without it `drag` reports `Drag delivered via app_post` and those operations have no effect; see `references/usage.md` for alternatives.
- On Windows and Linux, confirm the command is running inside the logged-in desktop session before assuming GUI automation is available.

## Fast channels (macOS)

- `find_elements` searches one app window by `role`, `label` or `identifier` without rendering the whole tree or a
  screenshot, and returns up to `max_results` rows. Its `element_index` values work with `click`, `set_value`,
  `scroll` and `perform_secondary_action` until the next state refresh (any `get_app_state` or action result). Use it
  to reach one specific control, and after a script changed the UI. Full-mailbox search in Mail goes through Mail's
  search field: locate it with `find_elements`, then drive it with the action tools or `perform_actions`.
- `find_elements` reads the window breadth-first: it visits every element at one depth before going a level deeper, and
  stops at `max_nodes` (default about 1200). Shallow window chrome such as a toolbar button, the sidebar or a search
  field sits a few levels down, so a role plus label lookup finds it after reading only a few nodes. Content deep in a
  large tree, such as a message row or a cell far down a list, can be cut off before the walk reaches it; the result
  then reports `truncated=true`, meaning the node budget ran out before the deeper levels were read. The walk reads the
  same nodes in the same order whatever `role` or `label` you pass, so a narrower query does not reach them. For deep
  content, raise `max_nodes` on that call (time grows roughly linearly with the nodes read) or read the window with
  `get_app_state`.
- Setting `OPEN_COMPUTER_USE_ENABLE_SCRIPTING=1` in the MCP server's launch environment (never per call) adds
  `run_script`, `get_scripting_dictionary`, `open_url`, `run_shortcut` and `list_shortcuts`. It is off by default. The
  turn-start `get_app_state` applies to UI work; a turn that only uses `run_script` skips it. Keep script queries small
  (one mailbox, the newest N messages): a large `whose` query stalls Mail for 20 to 60 seconds and blocks
  accessibility reads meanwhile. cmux terminates app-targeting `osascript` children, so `run_script` fails when the
  host runs under cmux.
- Read [references/scripting.md](references/scripting.md) before enabling: the shell-verb filter is not a security
  boundary, and on an MCP-only host enabling the flag is equivalent to granting a shell.

## Common CLI Actions

```sh
open-computer-use -h
ocu -h
open-computer-use doctor
open-computer-use call list_apps
ocu call list_apps
open-computer-use call get_app_state --args '{"app":"TextEdit"}'
open-computer-use call get_app_state --args '{"app":"TextEdit","text_limit":1000}'
open-computer-use call get_app_state --args '{"app":"TextEdit","text_limit":"max"}'
open-computer-use call get_app_state --args '{"app":"Google Chrome","max_tree_nodes":3000,"max_tree_depth":96}'
open-computer-use call click --args '{"app":"TextEdit","element_index":"0"}'
open-computer-use call type_text --args '{"app":"TextEdit","text":"Hello from Open Computer Use"}'
```

For a short sequence that reuses state in one process:

```sh
open-computer-use call --calls '[
  {"tool":"get_app_state","args":{"app":"TextEdit"}},
  {"tool":"press_key","args":{"app":"TextEdit","key":"Return"}}
]'
```

## MCP Usage

For runtimes that can launch local MCP servers over stdio, use:

```toml
[mcp_servers.open_computer_use]
command = "open-computer-use"
args = ["mcp"]
```

Read [references/usage.md](references/usage.md) for JSON config examples, direct tool-call patterns, and platform notes.

## References

- [references/installation.md](references/installation.md): one-time CLI install, agent MCP install commands, and macOS permissions.
- [references/usage.md](references/usage.md): MCP config, direct CLI calls, sequencing, and platform behavior.
- [references/troubleshooting.md](references/troubleshooting.md): permission, desktop-session, app discovery, and action failures.
- [references/decision-model.md](references/decision-model.md): the optional, experimental macOS `decide_next_action` advisory tool, its setup, cascade guide, and measured quality.
