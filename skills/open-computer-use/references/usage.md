# Open Computer Use Usage

Read this reference when the task requires direct Computer Use tool calls, MCP configuration, or platform-specific behavior.

## MCP Server

For MCP clients that support stdio servers:

```toml
[mcp_servers.open_computer_use]
command = "open-computer-use"
args = ["mcp"]
```

Supported npm packages also expose `ocu` as a short alias, so `ocu mcp` is equivalent when available.

Equivalent JSON shape:

```json
{
  "mcpServers": {
    "open-computer-use": {
      "command": "open-computer-use",
      "args": ["mcp"]
    }
  }
}
```

The MCP server exposes:

```text
list_apps
get_app_state
click
perform_secondary_action
scroll
drag
type_text
press_key
set_value
find_elements   (macOS only)
perform_actions (macOS only)
```

With `OPEN_COMPUTER_USE_ENABLE_SCRIPTING=1` in the MCP server's launch environment, five more tools are listed
(`run_script`, `get_scripting_dictionary`, `open_url`, `run_shortcut`, `list_shortcuts`); see
[scripting.md](scripting.md).

## Direct CLI Tool Calls

Use `call` for one-off checks:

```sh
open-computer-use call list_apps
ocu call list_apps
open-computer-use call get_app_state --args '{"app":"TextEdit"}'
open-computer-use call set_value --args '{"app":"TextEdit","element_index":"1","value":"Draft"}'
```

Use `--calls` for short action sequences that need to reuse the same process state:

```sh
open-computer-use call --calls '[
  {"tool":"get_app_state","args":{"app":"TextEdit"}},
  {"tool":"click","args":{"app":"TextEdit","element_index":"1"}},
  {"tool":"type_text","args":{"app":"TextEdit","text":"Hello"}}
]'
```

Use `--calls-file` when the sequence is too large for a readable shell command:

```sh
open-computer-use call --calls-file examples/textedit-overlay-seq.json --sleep 0.5
```

## Finding One Element

`find_elements` (macOS) reads one window's accessibility tree and returns only the rows that match, without a
screenshot. Arguments: `app` (required); at least one of `role` (with or without the `AX` prefix), `label` (compared
with each element's title and description) or `identifier`; optional `match` (`contains` by default, or `exact`; both
ignore case), `max_results` (1 to 20, default 5) and `max_nodes` (default 1200). Every provided criterion must match.

The returned `element_index` values work with `click`, `set_value`, `scroll` and `perform_secondary_action` until the
next state refresh (any `get_app_state` or action result). A hit outside the window is listed without a frame and
cannot be clicked.

```sh
open-computer-use call find_elements --args '{"app":"Mail","role":"AXTextField","label":"Search"}'
```

The scripting tools are not reachable from the CLI: `open-computer-use call run_script` (and the other four local
tools) is not supported, because scripts run only in the MCP server process. See [scripting.md](scripting.md).

## Text Limits

Snapshot text is truncated to 500 characters by default and ends with `...` when truncation happens. This keeps normal UI state compact for agent planning and element-targeted actions.

Use a larger text limit when the task depends on longer semantic text, such as chat histories, email bodies, document text, or long form content. Use `max` only when complete text is required:

```sh
open-computer-use call get_app_state --args '{"app":"TextEdit","text_limit":1000}'
open-computer-use call get_app_state --args '{"app":"TextEdit","text_limit":"max"}'
open-computer-use snapshot --text-limit 1000 TextEdit
open-computer-use snapshot --text-limit max TextEdit
```

The same `text_limit` tool argument and `--text-limit` snapshot flag apply on macOS, Linux, and Windows. `text_limit` accepts a positive integer or the string `"max"`.

Action tools return refreshed app state with the default 500 character text limit. If longer text is still needed after an action, run `get_app_state` again with `text_limit: 1000` or `text_limit: "max"`.

On macOS, action results are text-only by default; add `include_screenshot: true` to any action (or to `perform_actions`) to attach the window screenshot. A screenshot is attached automatically when the window exposes no accessibility elements (menu-bar items do not count). The Linux and Windows runtimes still attach the screenshot to every action result and reject `include_screenshot` as an unknown argument, so do not send it there.

Under Stage Manager, a macOS window that is off stage (shown in the left strip) has no screenshot: `get_app_state` and action results return the full accessibility tree plus a note saying so, `element_index` actions still work, and x/y `click` / `drag` fail with an error. The server never switches stages or activates the app to fix this; bring the window on stage yourself if you need a screenshot or coordinates.

## Larger Tree Budgets

Accessibility tree rendering defaults to 1200 nodes and 64 levels on macOS, Linux, and Windows. This keeps normal snapshots bounded while preserving most interactive UI.

Use a larger tree budget when a visible long page, list, table, or web app appears incomplete even after scrolling:

```sh
open-computer-use call get_app_state --args '{"app":"Google Chrome","max_tree_nodes":3000,"max_tree_depth":96}'
open-computer-use snapshot --max-tree-nodes 3000 --max-tree-depth 96 "Google Chrome"
```

`max_tree_nodes` and `max_tree_depth` must be positive integers. They only affect explicit `get_app_state` and `snapshot` calls; action tools still return refreshed state with the default tree budget.

## Choosing Targets

- Prefer app names or bundle identifiers returned by `list_apps`.
- Run `get_app_state` at the start of a turn before using `element_index`; within a turn, use indices from the latest `get_app_state` or action result. Do not guess indexes across sessions or after large UI changes.
- Re-run `get_app_state` after navigation, modal changes, page reloads, or failed actions.
- Use coordinate actions only when the rendered tree does not expose the target as an element.
- Mail search: click the toolbar search field by `element_index`, then `type_text` and `press_key Return`; this works while Mail stays in the background. A keyboard shortcut such as `cmd+option+f` does not move focus in a background app, and `set_value` fills the field but does not run the search. `press_key Escape` clears the search.
- `type_text` never brings the app to the front. It needs a focused text field: check that the focus line of the latest state names the field. When no text field holds focus, `type_text` fails instead of typing into whatever else has focus. Click the field by `element_index` first: clicking a text field (text field, text area, combo box, search or secure field) also writes its accessibility focus, so the field takes keyboard focus without the app coming to the front. Or use `set_value`; `set_value` with `""` clears a field.

## Choosing a Click Method

`click_method` is optional. Omitting it uses `auto`, which preserves the platform's existing semantic-first behavior. Explicit methods never fall back to a different implementation:

- `accessibility`: only invoke the element's accessibility action and require `element_index`.
- `app_post`: bypass accessibility and post a mouse event directly to the target app/window without moving the system pointer. Supported on macOS and Windows.
- `sky_click`: use the macOS private SkyLight background-window path with target-only synthetic focus and a Chromium primer click. It supports left single/double click on a current, on-screen window in the same Space and does not move the system pointer, deactivate the foreground app, change its key/first-responder state, or raise the target window. Its action-result snapshot refresh is read-only. Supported on macOS only.
- `global`: bypass accessibility and use the desktop's global pointer path. Supported on macOS and Linux, and requires `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1` because it may move the real pointer or change foreground focus.

Use `app_post` for an exact blank-area or overlay click that must not be redirected to an accessibility descendant:

```sh
open-computer-use call click --args '{"app":"Google Chrome","x":875,"y":375,"click_method":"app_post"}'
```

Use `sky_click` when Chromium ignores `app_post` and the current target window is covered by another window:

```sh
open-computer-use call get_app_state --args '{"app":"Google Chrome"}'
open-computer-use call click --args '{"app":"Google Chrome","x":875,"y":375,"click_method":"sky_click"}'
```

Run `get_app_state` again after the target window moves, closes, changes Space, becomes hidden, or is minimized. `sky_click` is an explicit private-SPI mode: unavailable symbols, a stale window id, unsupported button/count, or failed delivery return an error without falling back to another click implementation.

Use `global` only after explicitly enabling the process-level safety gate:

```sh
OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1 open-computer-use call click --args '{"app":"Google Chrome","x":875,"y":375,"click_method":"global"}'
```

Keep the environment override scoped as narrowly as possible. While it remains enabled, the existing `auto` route may also choose the global pointer path after accessibility cannot handle a click.

Windows returns an unsupported error for `sky_click` and `global`; Linux returns an unsupported error for `app_post` and `sky_click`. An unsupported or failed explicit method does not fall back to `auto`.

## Drag Delivery

`drag` has no method parameter. On macOS the path it takes is decided by the same process-level gate that authorizes `click_method: "global"`:

- Gate unset (default): mouse move / down / dragged / up events are posted directly to the target process with `CGEvent.postToPid`. The system pointer does not move and foreground focus is unchanged. Because the events never pass through the window server, this path cannot start a window-server drag session: window moves, drag-selecting text, and Finder drag-and-drop return without error but have no visible effect.
- `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1` set for the server process: the drag uses the global pointer path, which drives window-server drag sessions but may move the real pointer and change foreground focus.

Every non-fixture `drag` result includes a text item that begins `Drag delivered via app_post` or `Drag delivered via global pointer path`, so a default drag that did nothing is legible instead of looking like success. For an MCP server the variable belongs in the server entry's `env`, not in the calling shell, and the server must be restarted afterwards.

When the gate is not enabled, treat window-server drags as unavailable and reach the same outcome another way: copy or move files with a shell command instead of a Finder drag, use `set_value` or keyboard selection instead of drag-selecting text, and use the app's own window controls instead of dragging a title bar.

## Batching Actions (macOS)

`perform_actions` runs a short, fully specified sequence on one app in a single call. Each step is a `{tool, args}` object, the same shape as the CLI `--calls` entries, with `args` holding the single tool's arguments minus `app`. Allowed step tools are `click`, `type_text`, `press_key`, `set_value`, `scroll`, and `perform_secondary_action`; a batch holds 1 to 10 steps.

- Steps run in order and stop at the first failure. The result has one line per step, then one final app state.
- Every `element_index` refers to the state you last received, so a step cannot target an element that an earlier step in the same batch reveals.
- A batch with any `element_index` step is refused before any step runs when this session holds no state for the app; call `get_app_state` first. Coordinate-only and key-only batches still run.
- Live focus and window geometry are read per step, and nearby hit-testing is off inside a batch.
- The batch holds the per-call environment lock for its whole duration.
- Keep externally visible steps such as Send in their own call, after you confirm them.

Mail search as a batch: click the toolbar search field by `element_index`, type, then press Return. Clicking the field gives it keyboard focus while Mail stays in the background; a shortcut such as `cmd+option+f` would not, so `type_text` would fail. Every CLI `call` is a new process with no cached state, so run `get_app_state` in the same `--calls` array as `perform_actions`. Read the search field's index from a `get_app_state` result first (`"12"` below stands for it); it stays valid while Mail's window does not change:

```sh
open-computer-use call --calls '[
  {"tool":"get_app_state","args":{"app":"Mail"}},
  {"tool":"perform_actions","args":{
    "app":"Mail",
    "actions":[
      {"tool":"click","args":{"element_index":"12"}},
      {"tool":"type_text","args":{"text":"invoice"}},
      {"tool":"press_key","args":{"key":"Return"}}
    ]
  }}
]'
```

Over MCP the session keeps the state, so call `get_app_state` for Mail, then `perform_actions` with the same `actions` array, using the search field's index from that state.

## Platform Notes

### macOS

`perform_actions` is macOS-only; the Windows and Linux runtimes do not have it.

The macOS runtime uses Accessibility, ScreenCaptureKit, app-posted input events, and an explicit private-SkyLight `sky_click` route. It normally avoids moving the user's real pointer. The visual cursor overlay is part of the Open Computer Use experience and can be disabled by the surrounding runtime only when needed. Private SkyLight symbols and raw event fields are not API-stable; re-validate `sky_click` after macOS upgrades.

### Windows

The Windows runtime uses UI Automation and Win32 message fallbacks. It must run in a logged-in desktop session. A detached SSH or service context may start the CLI but fail to see top-level windows.

### Linux

The Linux runtime uses AT-SPI2 through the desktop session bus. It must run in a logged-in graphical session with usable accessibility services. Wayland screenshot and coordinate input support is compositor-dependent and best-effort.

## Safety

Pause and ask the user before actions that affect external systems or sensitive local state, including sending messages, submitting forms, deleting files, approving prompts, uploading files, or interacting with password managers.
