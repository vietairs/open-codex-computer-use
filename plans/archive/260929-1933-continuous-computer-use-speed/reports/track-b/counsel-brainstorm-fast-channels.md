# Counsel: Track B brainstorm, fast non-screenshot channels (PR B)

Date 2026-09-29. One-shot advisory pass at the design gate. No interview was held. Decisions 7-10 are treated as fixed.

## Verdict
Approve P2 with the eight amendments below. Reject P1. P1 signs the Apple Events entitlement onto a binary that the relay and the agent share: the launch script execs `Contents/MacOS/OpenComputerUse mcp` (launch script :31), and the build signs `--deep` with runtime (build script :467-475). That widens the confused-deputy surface that decision 8 exists to shrink. Reject P3 as a design too. Its only unique benefit is a human prompt by default, and one permissions rule gives P2 the same thing without touching installers or npm packaging. The brainstorm's source reading is accurate. I spot-checked it, and five facts below change the design.

## Verified in source (changes the design)
- `proxyMCP` is a strict serial loop: one line in, one response out (MacOSAppAgentProxy.swift:121-137). The router therefore knows which request each response answers without tracking JSON-RPC ids. It also means a running script blocks every later call from that host, and the host cannot cancel it. The timeout is the only bound.
- Direct mode has two entry paths, `server.run()` and `MCPAppRuntime.run(server:)` (OpenComputerUseMain.swift:40-47). The proposal names only one of them.
- The relay's agent socket is created without CLOEXEC (MacOSAppAgentProxy.swift:553, `socket(AF_UNIX, SOCK_STREAM, 0)`). Peer auth runs only at accept time.
- `AppSnapshot.elements` is a `[Int: ElementRecord]` dictionary and the lookup is optional (AccessibilitySnapshot.swift:121, ComputerUseService.swift:995-998), so indices ≥10000 cannot trap. The struct is `let`, so a merge must build a new snapshot and rewrite every cache key (:984-991).
- Track A adds `perform_actions` to `ToolDefinitions.all`. After the rebase, the two count tests therefore go from 10 to 11, not from 9 to 10.
- Claude Code evaluates rules in the order deny, then ask, then allow. An ask rule prompts a human even when an allow rule matches, and even in auto mode (code.claude.com/docs/en/permissions).

## Approve P2 with these amendments
1. Use one router loop, `LocalChannelRouter.run(forward:)`. The relay passes a socket request as `forward`, and both direct paths pass `server.handle`. This keeps the router out of `StdioMCPServer` and out of the agent. Build the `initialize` patch from a named Kit constant, and add a test that the base text still contains the exact line being replaced.
2. Keep "Avoid falling back to AppleScript" while the flag is off, and replace it only when run_script is listed. If the line is removed unconditionally, shell-capable agents are steered to Bash `osascript`, which bypasses both the filter and the log.
3. Drop the `OpenComputerUseCLI.swift` change. `call run_script` already fails closed because the agent's dispatcher has no case for it. A test that asserts this refusal is enough.
4. Harden how the child process is spawned. Use posix_spawn with `CLOEXEC_DEFAULT`, or set FD_CLOEXEC on the agent socket, and give the child fresh pipes for fds 0, 1 and 2. Add a test that the child sees only fds 0-2. Otherwise a script child could inherit the relay's already-authenticated agent connection.
5. Send only metadata (sha256, app, exit code, duration) to stderr. Host MCP logs are not 0600 and would carry email content. Write the full text only to the 0600 file, opened with O_NOFOLLOW and written once per entry with O_APPEND, reusing Track A's owner-only file helper. Log open_url and run_shortcut calls as well.
6. When parsing an sdef, load no network resources and no external entities. Resolve XInclude only to files inside the app bundle or `/System/Library/ScriptingDefinitions`. Otherwise a hostile app's sdef could pull arbitrary local files into the agent's context.
7. Fix three details in find_elements indexing:
   - Take indices from a per-service counter that never resets, so a stale hit fails as "unknown element_index" instead of resolving to a newer element.
   - Merge into the cached snapshot only when its `targetWindowID` matches. Otherwise create a snapshot that holds only the hits plus window context, because `localFrame` needs `windowBounds`.
   - For each hit, read AXPosition, AXSize and the action names, and match the label against title or description.
8. For open_url, block known-dangerous URL handlers (Terminal, iTerm, Script Editor, Shortcuts) in addition to the blocked schemes (file, shortcuts, x-man-page, ssh, telnet). An allowlist would defeat decision 7.

## Avoid
- Do not try to make the filter complete. It can always be bypassed, for example with iTerm `write text`, System Events keystrokes into Terminal, Finder opening a `.command` file, `use script` libraries, or JXA bracket access. Ship the locked verbs plus their obvious aliases, test them, and document the classes of bypass.
- Do not claim that SIGKILL contains a hung script. It frees the relay, but Mail keeps executing the Apple Event, and a heavy `whose` query can stall get_app_state and find_elements on Mail. The guidance should tell agents to keep queries small, for example one mailbox or the first N results.
- Do not take P1's in-process engine as a fallback, even if Q1 goes against the child-process reading.

## Hidden risks
- Enabling the flag on an MCP-only host effectively gives that host a shell. `scripting.md` should say this plainly.
- AppleScript sends and deletes run without the visible cursor, so the script-first guide must repeat "ask before sending or deleting".
- My unverified belief is that desktop hosts whose responsible app lacks `NSAppleEventsUsageDescription` get a silent -1743 error with no prompt. If so, run_script works only from terminal hosts, and no fix fits inside decision 8.
- P2 edits MacOSAppAgentProxy.swift, OpenComputerUseMain.swift, MCPAppRuntime.swift and MacSessionGuard.swift. It also adds a cache hook right next to Track A's `refreshSnapshot` rewrite, so the clash risk there is medium, not low. The main loop should add these files to Track B's ownership in parallel-tracks.md and drop the entitlements/Info.plist line.

## Check before approving
1. Q1: in the default install, the process that hosts `StdioMCPServer` is the agent, so a literal reading of decision 8 contradicts its own socket clause. Confirm the reading that scripts run in a child of the relay.
2. Q2 has three options:
   - (a) Keep the blanket allow: scripts run with no review.
   - (b) Add `permissions.ask` for run_script, run_shortcut and open_url: a human prompts on every call.
   - (c) Narrow decision 2's allow to a list of named tools, so these three tools go to the auto-mode classifier (about 1.3s, no human).

   This is the user's call. I lean towards (c).
3. Before cook, time `osascript -e 'tell application "Mail" to count (messages of inbox whose subject contains "combio")'` in Terminal. If a warm run takes more than 1s, the Mail search target is limited by Mail itself and needs a pinned mailbox and script first.
4. Confirm with Track A that `perform_actions` resolves every step against the one cached snapshot, so merged hits survive a batch.

## Work checklist and success metrics
- [ ] Filter, child runner and audit log, plus tests. [ ] Router in the relay and both direct paths, plus the sanitizer strip. [ ] sdef lookup and launcher. [ ] find_elements walker and merge. [ ] Guidance. [ ] Red-team and security audit.
- Metrics: `swift test` passes with the count at 11. A fd test shows the child has only fds 0-2. With the flag unset, tools/list omits all scripting tools and `initialize` still contains the AppleScript line. The Mail search via run_script takes ≤1s. find_elements takes ≤50% of get_app_state (both measured from the main loop).

## Unresolved questions
1. Q1 and Q2 above are the user's calls.
2. Which app name appears in the Automation prompt for Claude.app and Codex.app, and do those apps prompt at all?
3. Does the Shortcuts "Allow Running Scripts" setting gate "Run Shell Script" for `shortcuts run`? This is my belief and has not been verified.
4. What retention period should the 0600 script log have, given that it holds email content?
