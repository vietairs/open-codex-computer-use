# Scripting Channel (macOS, opt-in)

Read this before enabling the scripting tools. They are off by default, and turning them on changes what an agent can do
on this Mac.

## Enabling

Set `OPEN_COMPUTER_USE_ENABLE_SCRIPTING=1` in the launch environment of the MCP server (the `open-computer-use mcp`
process the host starts). Never pass it per call: the flag is read only from the relay's own environment, and it is
stripped from anything a peer sends to the app agent. Without it the relay forwards every message unchanged and the
server instructions keep the "avoid falling back to AppleScript" line.

## Tools

The tools are answered by the MCP relay process, not by the app agent. `open-computer-use call run_script` (and the
other four) is refused: scripts run only in the MCP server process.

| Tool | Arguments | Notes |
|---|---|---|
| `run_script` | `app`, `source`, optional `language` (`applescript` default, or `javascript`), optional `timeout_s` (1 to 60) | Runs the script with `osascript`. |
| `get_scripting_dictionary` | `app`, optional `term` | Reads the app's static `.sdef` file only and never launches the app. Apps with only legacy `aete` or dynamic terminology return no summary; `run_script` still works for them. |
| `open_url` | `url` | Opens a URL under a scheme and handler policy, in the background: the handler app is not activated. |
| `run_shortcut` | `name`, optional `input`, optional `timeout_s` | Runs a Shortcuts shortcut. |
| `list_shortcuts` | none | Lists shortcut names. |

## When to use which channel

- Prefer `find_elements` plus the action tools for UI work. The turn-start `get_app_state` still applies to UI work; a
  turn that only uses `run_script` skips it. After a script changed the UI, call `find_elements` to reach the next
  control instead of re-reading the whole tree.
- A full-mailbox search in Mail goes through Mail's own search field: locate it with `find_elements`, then drive it with
  the action tools. Do not run a mailbox-wide `whose` query from `run_script`.
- Large `whose` queries stall Mail for 20 to 60 seconds, and Mail is unresponsive to accessibility reads for that time.
  Keep script queries narrow: the selected message, or the newest N messages of one mailbox.
- cmux terminates app-targeting `osascript` children (exit 143), so `run_script` fails when the host runs under cmux.
  Run the host from Terminal.app instead.

## Permissions (TCC)

- Apple Events are sent by an `osascript` child of the MCP server, so the Automation grant is the one for the HOST app
  (Terminal, iTerm, VS Code, Claude.app, Codex.app) and the target app. It is never Open Computer Use.app's grant.
- The grant is per host app and target app. It is inherited from earlier approvals under the same host and shared by
  every process running under that host.
- A denied or missing grant shows up as error -1743. Fix it under System Settings > Privacy & Security > Automation
  by enabling the target app for the host app, or run the same script once from the host to raise the prompt. Desktop
  hosts whose bundle lacks an Apple-events usage description may fail with -1743 and no prompt at all (unverified).
- System Events UI scripting launders the host's Accessibility grant and bypasses the visible cursor.

## Security model

- **The filter is best-effort friction, not a security boundary.** `run_script` rejects `do shell script`, `run script`,
  `load script`, `store script`, `do script`, raw Apple Event forms, `use framework`, JXA `doShellScript`, `ObjC.` and
  similar, over a normalized view of the text. Known bypass classes stay open by design: iTerm `write text`, Finder
  opening a `.command` file, JXA bracket access, System Events keystrokes into Terminal.
- Scripts can read and write any file the user can (Standard Additions `read`/`write`), including credentials and
  LaunchAgents. The scrubbed environment does not protect secrets stored on disk.
- Shell-capable hosts (Claude Code, Codex) bypass the filter entirely with Bash `osascript`.
- **On an MCP-only host, enabling the flag is equivalent to granting that host a shell**, under the host's own
  Automation grants.
- **Recommended permission setup:** do not allow these tools blanket. Put them on a named-tool allow list so
  `run_script`, `open_url` and `run_shortcut` go through review. Only Claude Code's auto mode has a classifier that
  reviews such calls; Codex and Claude.app hosts run these tools with no review step.
- The guidance tells the agent to ask the user before sending, deleting or purchasing. That is guidance, not a control.
- A script can show `display dialog ... default answer "" with hidden answer` and return what the user types to the
  agent. Treat unexpected password prompts as hostile.
- The logged `target_app` is the agent-declared `app` argument and is advisory: a script can `tell` a different app.
  The first-contact timeout floor is keyed on the same argument and is advisory too.
- The `open_url` policy is friction only: a script can `open location` or drive Finder around it. Blocked schemes
  include `file`, `shortcuts`, `x-man-page`, `ssh`, `telnet`, `smb`, `afp`, `nfs`, `cifs`, `ftp`, `ftps`, `sftp`, `vnc`
  and `help`. Blocked handlers include Terminal, iTerm, Script Editor, Shortcuts, Automator, the network mount agent,
  VS Code and its forks, Zed, Warp, JetBrains Toolbox, Script Debugger and several launcher and automation apps. The URL
  must resolve to a handler that is a `.app` with a readable bundle identifier, and the checked handler is the one that
  opens it.
- A Shortcuts shortcut can contain a "Run Shell Script" action. `run_shortcut` runs whatever the named shortcut does;
  review shortcuts before letting an agent run them. Names beginning with `-` are refused, and input travels through a
  private temporary file that is removed afterward.
- The script child gets a scrubbed environment (fixed `PATH`, `HOME`, `LANG`), only descriptors 0 to 2, and root as its
  working directory. It cannot reach the relay's agent socket.

## Audit log

- Path: `~/Library/Application Support/OpenComputerUse/logs/scripts.log`. JSON lines, mode 0600 in a 0700 directory.
- It holds script text, URLs and shortcut inputs, which may include email content. Every script text is logged,
  including scripts the filter rejects and scripts refused while the Mac is locked. The request entry is written
  before any check, so a rejected attempt leaves a trace; the result entry records the outcome. Each payload is
  stored up to 64 KiB (the script size limit), with `payload_bytes` giving its full length and `payload_sha256`
  its hash over the full text.
- The log is capped at 10 MB plus one rotated file (`scripts.log.1`).
- If the log cannot be opened safely (symlink, wrong owner, wide permissions), the call is refused rather than run
  unlogged.
- stderr, which host MCP logs capture, carries metadata only (tool, app, hash, exit status, duration), with control
  characters escaped.

## Timeouts and orphaned work

- Default timeout 20 seconds, maximum 60. The first script sent to a target app gets at least 30 seconds, so the
  permission prompt has time to appear.
- On timeout the relay stops its `osascript` child (SIGTERM, then SIGKILL to its process group). **A killed script keeps
  running inside the target app:** Mail keeps executing an Apple Event that is already in flight. Keep queries small.
- A Shortcuts run keeps going after a timeout, because `/usr/bin/shortcuts` hands the shortcut off to a background runner.
- If the MCP host kills the relay mid-script (Ctrl-C, SIGTERM, SIGHUP), the `osascript` child is orphaned and runs to
  completion; the log then shows a request with no result. Signals are not forwarded.
- Scripts are refused while the Mac is locked, using the same lock policy as the other tools.
