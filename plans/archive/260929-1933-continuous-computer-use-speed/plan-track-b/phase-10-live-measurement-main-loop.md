# Phase 10: live measurement and live security checks (main loop only)

Depends on: phase 09 (rebased build, green suite). Owner: **main loop**, never a workflow agent (parallel-tracks rule 3:
both bundles share one agent socket, memory `app-agent-socket-eviction-between-bundles`). Run while Track A is NOT
being measured. Effort 2.5h, plus 0.5h for the early probe.

## Early probe (before the rebase, right after phase 05 is green)

Purpose: measure the `find_elements` / `get_app_state` ratio once on the pre-rebase build instead of first seeing it
after about 35h of work. Owner: main loop; the **user** runs the harness in Terminal.app. Run while Track A is not
being measured.

1. Deploy the phase 05 build (branch head after the phase 05 commit) into Dev.app per pre-requisite 2 below.
2. Mail open on the inbox, same window state as phase 00. Run `/usr/bin/python3 ocu_live.py
   "<Dev.app>/Contents/MacOS/OpenComputerUse" probe` (flag unset; `find_elements` runs in the agent and the relay
   forwards it, so phase 06 is not needed).
3. Target: `ratio` <= 0.35 and `find_elements matches: 1`. The target is tighter than acceptance 9's 0.50 because Track
   A's batched reads (decision 13) shrink the `get_app_state` denominator after the rebase.
4. If the ratio misses: record `nodes_visited` and both medians, switch the walker to breadth-first (phase 05 step 3,
   the one pre-approved lever; add `testWalkIsBreadthFirst`), redeploy, and probe again. Never raise `max_nodes` or move
   the target. A second miss goes to the Failure Protocol with both probes' numbers.
5. Stop the namespaced agent as in step 11, and record the numbers in
   `reports/track-b/early-probe-<yymmdd-hhmm>.md`.

## Pre-requisites (main loop)

1. Decision 16: narrow `permissions.allow` in `~/.claude/settings.json` from `mcp__open-computer-use` to named tools:
   `list_apps`, `get_app_state`, `find_elements`, `click`, `perform_secondary_action`, `scroll`, `drag`, `type_text`,
   `press_key`, `set_value`, `perform_actions`, `decide_next_action`, `get_scripting_dictionary`, `list_shortcuts`
   (each as `mcp__open-computer-use__<name>`). `run_script`, `open_url`, `run_shortcut` stay unlisted so the auto-mode
   classifier reviews them. Keep a pre-edit copy for rollback.
2. Deploy the rebased build into Dev.app per memory `dev-app-deploy-and-tcc-regrant-cycle` (rm-first copy, kill stale
   `__open-computer-use-app-agent`, sign the bundle with the Developer ID so the grant survives). This also validates the
   "no entitlement needed" claim: the relay is hardened-runtime signed and osascript is a platform binary.
3. Mail open on the inbox; the same Mac and window state as phase 00. Use the script text recorded in
   `reports/track-b/precook-mail-whose-timing.md` (default S2:
   `tell application "Mail" to get subject of (messages of inbox whose subject contains "combio")`).
4. Automation TCC: the harness runs from Terminal.app, so the grant is Terminal -> Mail (approved in phase 00). The
   Claude Code Bash sandbox blocks Apple Events; the **user** runs the harness in Terminal.app, or the main loop asks the
   user before running it outside the sandbox.
5. Agent isolation: the harness sets `OPEN_COMPUTER_USE_AGENT_SOCKET_NAMESPACE=track-b-live`
   (`K/AppAgentSocketNamespace.swift:4`; the relay derives the socket path from it and passes that path to the agent it
   launches, `A/MacOSAppAgentProxy.swift:72`, `:97`), so the Dev.app relay starts its own agent and never terminates the
   main loop's live agent (memory `app-agent-socket-eviction-between-bundles`, `A/MacOSAppAgentProxy.swift:86-93`).
6. Host setup for steps 7 and 9 (user-approved). The session's `open-computer-use` server is the npm release, which has
   no `run_script`, and the decision-16 rules are named `mcp__open-computer-use__<tool>`, so the Dev.app build must be
   registered under the SAME server name or the review observation means nothing:
   a. The user records the current registration in Terminal.app (`claude mcp get open-computer-use`: scope, command,
      args, env keys). Env values stay out of the transcript.
   b. Replace it: `claude mcp remove open-computer-use -s <recorded scope>` then
      `claude mcp add open-computer-use -s <recorded scope> -e OPEN_COMPUTER_USE_ENABLE_SCRIPTING=1
      -e OPEN_COMPUTER_USE_AGENT_SOCKET_NAMESPACE=track-b-live -- "<Dev.app>/Contents/MacOS/OpenComputerUse" mcp`.
      The namespace keeps other sessions' npm agent alive; the harness uses the same namespace and the same bundle, so
      the two share one agent without eviction.
   c. Restart the Claude Code session so the tool list and the narrowed allow list reload; confirm `run_script` is
      listed.
   d. After step 9, restore: remove the Dev.app registration and re-add the recorded npm registration with its
      original scope, command, args and env; restart the session and confirm `run_script` is no longer listed.

## Harness (save to the session scratchpad, not the repo)

```python
#!/usr/bin/python3
# usage: /usr/bin/python3 ocu_live.py "<Dev.app>/Contents/MacOS/OpenComputerUse" equivalence
#        /usr/bin/python3 ocu_live.py "<Dev.app>/Contents/MacOS/OpenComputerUse" probe
#        /usr/bin/python3 ocu_live.py "<Dev.app>/Contents/MacOS/OpenComputerUse" measure "<script text>"
import json, os, re, statistics, subprocess, sys, time
binary, mode = sys.argv[1], sys.argv[2]
DROP = ("OPEN_COMPUTER_USE_DECISION_MODEL_URL", "OPEN_COMPUTER_USE_DECISION_MODEL_BACKEND",
        "OPEN_COMPUTER_USE_ENABLE_SCRIPTING", "OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY")
def env_with(**extra):
    env = {k: v for k, v in os.environ.items() if k not in DROP}
    env["OPEN_COMPUTER_USE_AGENT_SOCKET_NAMESPACE"] = "track-b-live"  # never evict the main loop's agent
    env.update(extra); return env
class Server:
    def __init__(self, env):
        self.p = subprocess.Popen([binary, "mcp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  env=env, text=True, bufsize=1); self.n = 0
    def send(self, msg): self.p.stdin.write(json.dumps(msg) + "\n"); self.p.stdin.flush()
    def rpc(self, method, params=None):
        self.n += 1; msg = {"jsonrpc": "2.0", "id": self.n, "method": method}
        if params is not None: msg["params"] = params
        t = time.perf_counter(); self.send(msg); line = self.p.stdout.readline()
        return time.perf_counter() - t, line
    def tool(self, name, args):
        t, line = self.rpc("tools/call", {"name": name, "arguments": args}); return t, json.loads(line)
    def start(self):
        _, line = self.rpc("initialize", {"protocolVersion": "2025-03-26", "capabilities": {},
                                          "clientInfo": {"name": "live", "version": "0"}})
        self.send({"jsonrpc": "2.0", "method": "notifications/initialized"}); return line
    def close(self): self.p.stdin.close(); self.p.wait(timeout=10)
def ratio(s):  # find_elements vs get_app_state on the same Mail window
    fe_args = {"app": "Mail", "role": "AXButton", "label": "Get Mail", "match": "contains", "max_results": 1}
    fe, gs = [], []
    for _ in range(5):
        t, r = s.tool("find_elements", fe_args); fe.append(t); last = r
        t, _ = s.tool("get_app_state", {"app": "Mail"}); gs.append(t)
    m = re.search(r"find_elements: (\d+) match.*?nodes_visited=(\d+)", last["result"]["content"][0]["text"])
    print("find_elements matches:", m and m.group(1), "nodes_visited:", m and m.group(2))
    mf, mg = statistics.median(fe), statistics.median(gs)
    print("find median", round(mf, 3), "get_app_state median", round(mg, 3), "ratio", round(mf / mg, 3))
if mode == "equivalence":  # flag unset: relay and direct must answer byte-identically
    runs = []
    for extra in ({}, {"OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY": "1"}):
        s = Server(env_with(**extra)); lines = [s.start(), s.rpc("tools/list")[1]]
        lines.append(s.rpc("tools/call", {"name": "run_script",
                                          "arguments": {"app": "Mail", "source": "return 1"}})[1])
        lines.append(s.rpc("no/such_method")[1]); s.close(); runs.append(lines)
    for label, a, b in zip(("initialize", "tools/list", "run_script", "unknown"), *runs):
        print(label, "IDENTICAL" if a == b else "DIFFERENT")
    print("tools:", len(json.loads(runs[0][1])["result"]["tools"]),
          "applescript_line:", "Avoid falling back to AppleScript" in runs[0][0])
    sys.exit(0 if runs[0] == runs[1] else 1)
if mode == "probe":  # early probe on the pre-rebase build, flag unset
    s = Server(env_with()); s.start(); ratio(s); s.close(); sys.exit(0)
script = sys.argv[3]
s = Server(env_with(OPEN_COMPUTER_USE_ENABLE_SCRIPTING="1"))   # relay path, flag set
s.start()
print("tools:", len(json.loads(s.rpc("tools/list")[1])["result"]["tools"]))
rs = [s.tool("run_script", {"app": "Mail", "source": script})[0] for _ in range(6)]
print("run_script s:", [round(x, 3) for x in rs], "median warm:", round(statistics.median(rs[1:]), 3))
ratio(s)
t, r = s.tool("open_url", {"url": "https://example.com"})  # relay: default opener waits on the main thread
print("open_url s:", round(t, 3), "isError:", r["result"].get("isError", False),
      "text:", r["result"]["content"][0]["text"][:60])
t, r = s.tool("list_shortcuts", {})
print("list_shortcuts s:", round(t, 3), "isError:", r["result"].get("isError", False),
      "lines:", len(r["result"]["content"][0]["text"].splitlines()))
s.close()
```

## Steps and pass conditions

1. **Mail search via run_script** (acceptance 7a): `measure` mode. Pass: `median warm` <= 1.0 (seconds). Record all six
   values.
2. **find_elements vs get_app_state** (acceptance 7b; outcome-lock target "one button on Mail"): same run. First confirm
   `find_elements matches:` is `1` for the `Get Mail` button; if 0, pick another toolbar button's role/label from one
   `get_app_state` output, update `fe_args`, and record the substitution. `max_results: 1` makes the walk stop at the
   first hit, which is the early-stop behaviour the design relies on. Pass: `ratio` <= 0.50. Record `nodes_visited`.
2a. **open_url and list_shortcuts, live** (same run; the only live exercise of both): the relay runs its loop on the
   main thread (`A/MacOSAppAgentProxy.swift:121-137`) and the default opener waits on a semaphore for the
   `NSWorkspace.open` completion handler. If AppKit delivered that handler on the main queue, every relay `open_url`
   would be a 10s false failure that no unit test can see. Pass: `open_url` `isError: False`, text starts with
   `Opened https://example.com`, elapsed < 2s; `list_shortcuts` `isError: False` and returns within its timeout. A
   10s `open_url` is a phase 03 fix (complete the open off the main thread), not a timeout change. The browser window
   this opens is expected; the user closes it.
3. **Smoke suite** (phase 06 assertions, direct mode only): `scripts/run-tool-smoke-tests.sh` against the Dev.app build.
   Pass: exit 0, including the flag-on scripting smoke on both direct paths (visual cursor on and off).
4. **Flag unset, relay vs direct** (acceptance 2, live; the only live check of `proxyMCP` / `relayMCPLine`):
   `equivalence` mode. Pass: exit 0, all four lines `IDENTICAL`, `tools:` prints 11, `applescript_line: True`.
5. **Audit log**: `stat -f '%Lp %u' ~/Library/Application\ Support/OpenComputerUse/logs/scripts.log` prints `600` and the
   user's uid; the last lines are JSON with `kind: run_script`. Do not print the file contents into the transcript
   (they contain email subjects); count lines only, e.g. `grep -c '"phase":"request"'`.
6. **Filter vs the real compiler** (threat T7): the user runs in Terminal.app, for each candidate,
   `osacompile -o /dev/null -e "<candidate>" && echo COMPILES || echo FAILS` (compiling runs nothing): `do shell script
   "id"` with NBSP between the words; `do (* x *) shell script "id"`; `« event sysoexec » "id"`; `do shell ¬` plus
   trailing spaces, a newline and `script "id"`. Pass: every candidate that COMPILES is a row of
   `testFilterRejectsEveryDeniedForm` (phase 01). A compiling spelling missing from the table is a phase 01 fix (new row
   plus normalisation rule), not a redesign.
7. **Script review** (threat T8, decision 16): after pre-requisite 6 a-c, in the restarted Claude Code session in auto
   mode with the narrowed allow list, call
   `run_script` with `return 1`. Pass: the call goes through the auto-mode classifier or a permission prompt (no allow
   rule matches it); record what was shown. `get_scripting_dictionary` and `find_elements` run without review.
8. **Dictionary lookup never launches an app** (threat T21): with Calculator not running, call
   `get_scripting_dictionary` for `Calculator`, then `pgrep -x Calculator`. Pass: an `isError` result or a summary, and
   `pgrep` prints nothing. Then `get_scripting_dictionary {"app":"Messages","term":"send"}` returns a summary (the
   extension-less `OSAScriptingDefinition` case).
9. **Host checks** (plan unresolved questions 1-2): from the restarted Claude Code session (pre-requisite 6) and, if
   available, Claude.app / Codex.app,
   call `run_script` with `return 1` then a Mail one-liner; record which app name the Automation prompt shows and
   whether a silent -1743 occurs. Run `run_shortcut` on a harmless test shortcut with a 1s timeout that sleeps 10s and
   record whether the shortcut kept running. Then restore the host registration (pre-requisite 6d).
10. **Handler bundle ids**: for each `[UNVERIFIED]` id in `UrlOpenPolicy.blockedHandlerBundleIdentifiers` whose app is
    installed, `/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "<app>/Contents/Info.plist"` matches. A mismatch
    is a phase 03 fix.
11. **Cleanup** (process-management rule): stop only the namespaced agent this phase started. Its socket file is
    `open-computer-use-agent-<h>.sock` with `h=$(printf %s track-b-live | shasum -a 256 | cut -c1-16)`; find its pid
    with `lsof -t` on that socket file and send SIGTERM to that pid only. Never `pkill` the agent by name.
12. Write results to `reports/track-b/live-measurement-<yymmdd-hhmm>.md`: numbers, medians, ratio, nodes_visited, the
    open_url and list_shortcuts lines, the equivalence lines, compile-probe results, the review observation, host observations, pass/fail per criterion.

## Failure handling specific to this phase

- 7a fails but phase 00 showed Mail alone > 0.8s: the gap is Mail-bound; report both numbers and ask the user whether to
  accept or pin a narrower script. Do not change code for it.
- 7b fails: record `nodes_visited`; escalate via the Failure Protocol with both medians. Do not raise `max_nodes` or move
  the target to make the ratio pass.

## Rollback

Restore `~/.claude/settings.json` from its pre-edit copy if the narrowed allow list breaks the user's flow; redeploy the
previous Dev.app binary per the same memory. Restore the recorded npm `open-computer-use` registration (pre-requisite
6d) even if a step fails midway, then restart the session.

## Contract Rules

1. Implements to the SIGNATURE exactly. A signature that cannot work is a STOP, not a redesign —
   report it through the Failure Protocol.
2. Edits only within TARGET. Discovering that the change genuinely requires a FORBIDDEN file is a
   STOP with that finding, never a quiet widening.
3. Writes the acceptance assertions first where the plan says tests-first, confirms they FAIL, then
   implements until they pass.
4. Never weakens an assertion, never marks a test skipped, and never stubs an implementation to
   make one pass. A passing suite obtained this way is the specific failure this whole contract is
   built to prevent — cheap tiers reward-hack checkable specs more than strong ones do, so the
   escalation path exists precisely for the moment the spec looks unsatisfiable.
5. On any failed Verify, follows the `## Failure Protocol` already in the phase file. That is the
   backchannel; using it is correct behaviour, not an admission of failure. The escalation names
   the failure's class: a missed edge case, a wrong or incomplete fix, a misread requirement
   (including a wrong reading of an ambiguous one), or a wrong domain rule. The first two are
   fixed by more verification. The last two are not fixed by more effort or by a retry: they need
   the outcome re-locked or the rule looked up, so name the class in the escalation instead of
   retrying.

## Failure Protocol
If any Verify step does not meet its stated pass condition, STOP this phase.
Do not improvise a fix, retry blindly, or reason around the failure.
Spawn the `kongming` subagent for next-step counsel and pass:
- the phase and task id,
- what you attempted (the steps you ran),
- the exact command and its full output,
- the pass condition it failed to meet.
Apply kongming's guidance, then re-run the Verify step.
If `kongming` cannot be spawned in this environment, STOP and report the same
failure evidence to the user. Never continue by self-reasoning.

## Main-loop amendment 2026-09-29 22:53 (outcome-lock decision 17, user-approved)
Measured: a full-inbox Mail `whose` search takes 20–66s, and the time is Mail's own. Replace the "Mail search via run_script ≤1s" target with a NARROW run_script on Mail (the selected message, or the newest N inbox messages), ≤1s median of 5 warm runs, run from Terminal.app and never cmux. Guidance and docs must say:
- Full-mailbox search goes through Mail's search field via find_elements plus perform_actions.
- Large `whose` queries stall Mail for 20–60s, which also blocks AX reads.
- cmux SIGTERMs app-targeting osascript children, so run_script fails when the host runs under cmux.
