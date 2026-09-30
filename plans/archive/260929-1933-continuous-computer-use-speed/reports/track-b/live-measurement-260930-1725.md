# Track B live measurement (phase 10), 2026-09-30

Branch `feat/fast-macos-channels`. Builds: the Dev.app debug bundle, signed with the Developer ID, at 9743c40 (part 1 and 2), then at 71b074d with the breadth-first walker (parts 3 and 4, in-session steps). Harness `ocu_live.py` ran from Terminal.app. Logs are in the session scratchpad: `phase10-terminal-run{,-2,-3,-3-dfs,-4}.log` and `phase10-smoke*.log`.

**Result:** every criterion passes except step 1, which the user accepted as Mail-bound, and step 8's Messages case, which was fixed in code after the run (see step 8).

| Step | Criterion | Result |
|---|---|---|
| 1 | run_script Mail search, median warm ≤ 1.0s | Accepted as Mail-bound. The channel adds no measurable overhead |
| 2 | find_elements / get_app_state ratio ≤ 0.50, one match | PASS after the breadth-first change: 0.023 |
| 2a | open_url and list_shortcuts, live | PASS |
| 3 | smoke suite exit 0 | PASS after one startup-timing flake |
| 4 | relay vs direct, flag unset | PASS when compared as parsed JSON |
| 5 | audit log mode and owner | PASS |
| 6 | filter vs the real compiler | PASS |
| 7 | run_script goes through review | PASS: a permission prompt was shown |
| 8 | dictionary lookup never launches an app; Messages+send gives a summary | Calculator PASS. Messages failed live and was fixed afterwards |
| 9 | host checks | No Automation prompt and no -1743. The shortcut timeout test was skipped by the user |
| 10 | handler bundle ids | PASS |
| 11 | cleanup | Done: the namespaced agent was stopped by pid |

## 1. run_script Mail search

The first run at 9743c40 measured six calls at 2.871, 2.638, 2.633, 2.635, 2.46 and 2.044s, a warm median of 2.633s. The agent-side durations were 2.0 to 2.85s, so the time is spent inside osascript and Mail.

Part 3 measured plain `osascript` with the same script alongside run_script, 5 runs each:

| Script | osascript median warm | run_script median warm |
|---|---|---|
| heavy (Mail search) | 1.696s | 1.648s |
| cheap one-liner | 0.057s | 0.057s |

The run_script channel costs about 0ms over plain osascript. The search misses 1.0s only because Mail alone takes about 1.7s. The user accepted this as Mail-bound with no code change. The part 2 osascript baseline was invalid (it compared perf_counter values across processes) and is not used.

## 2. find_elements vs get_app_state

"Get Mail" does not exist in macOS 26 Mail (0 matches, 237 nodes). The toolbar-label sweep in part 2 found "New Message" (AXButton) as a stable substitute, so the check uses New Message, AXButton, max_results 1.

| Walk | Commit | nodes_visited | find median | get_app_state median | ratio |
|---|---|---|---|---|---|
| depth-first | 9743c40 | 216 | 0.805s | 0.817s | 0.985 FAIL |
| breadth-first | 71b074d | 17 | 0.02s | 0.882s | 0.023 PASS |

The depth-first walk reached the toolbar last, at about 3.7ms per node. With breadth-first, the shallow toolbar comes before the deep message list.

Known trade-off: in trees over 1200 nodes, deep content can now be truncated. The phase 07 guidance tells agents to look for shallow controls with find_elements and to find deep content by role plus label or with get_app_state. max_nodes was not raised.

## 2a. open_url and list_shortcuts

- open_url took 0.05s with isError False: "Opened https://example.com with Google Chrome." There was no main-thread stall.
- list_shortcuts took 0.095s with isError False and returned 52 lines.

## 3. Smoke suite

The first Terminal run exited with 133 at "Fixture app should appear in list_apps output". The fixture had not appeared within the suite's fixed 1.5s launch wait. Three reruns all passed: all 11 tools, both scripting-channel smokes (visual cursor on and off), and the cursor-idle smoke. The failure was a startup-timing flake. An optional follow-up is to poll for the fixture instead of sleeping.

## 4. Relay vs direct, flag unset

The harness printed `DIFFERENT` for initialize, tools/list, run_script and unknown, then `tools: 11` and `applescript_line: True`. `equiv_diff.py` showed the raw bytes differ only in JSON key order, which varies per process. Compared as parsed JSON, all four are identical. The plan's byte-identical condition cannot be met, and parsed equality is the meaningful check.

## 5. Audit log

`scripts.log` has mode 600 and owner uid 501. It holds 54 lines, which is 27 request entries, and the last line is kind run_script. Only counts were read.

## 6. Filter vs the real compiler

These candidates FAIL to compile: NBSP between the words, an inline comment, continuation plus a newline, and a spaced raw event. The control compiles. Only the unspaced `«event sysoexec»` compiles, and it is a row of `testFilterRejectsEveryDeniedForm`.

## 7. Script review

The in-session run used the Dev.app registration and the narrowed allow list of 14 named tools. run_script `return 1` on Mail returned 1 in 52ms. The user saw a permission prompt, so no allow rule matched. get_scripting_dictionary and find_elements ran without review.

## 8. Dictionary lookup

- **Calculator (not running):** returned isError "no .sdef", and Calculator was not launched. PASS.
- **Messages + send:** FAIL live. `locateAppBundle` matched running apps by localizedName and took the first entry. That was `com.apple.messages.AssistantExtension`, an .appex with activation policy prohibited, which is enumerated before `com.apple.MobileSMS`. Querying by the bundle id com.apple.MobileSMS returned the summary with send.
- **Fix (d747be1):** accept only running `.app` bundles. Rank an exact bundle-id match first, then activation policy regular, then accessory, then prohibited; enumeration order breaks ties. Background-only apps such as System Events are never dropped. The ranking lives in a pure `bestRunningMatch` seam with 6 unit tests, and there are no new NSWorkspace calls. After the fix, the direct-mode spot check gave: Messages+send, a summary; Calculator, isError and not launched; System Events by bundle id, a summary and not launched. By name, System Events resolves only while it is running, because /System/Library/CoreServices is not a fallback directory. This is pre-existing behavior and is listed as a follow-up.

## 9. Host checks

- From the Claude Code session, run_script `return 1` and then a Mail one-liner took 61ms. There was no Automation prompt, because the host was already authorized, and no silent -1743.
- Claude.app and Codex.app were not tested.
- The run_shortcut timeout test was skipped. None of the user's shortcuts was safe to run, and the user chose to skip it.
- The host registration was restored by the user (6d, `phase10-restore-mcp.sh`). settings.json was restored from its backup.

## 10. Handler bundle ids

Screen Sharing, Tips (helpviewer) and Warp are installed, and their ids match case-insensitively. The 11 other ids are for apps that are not installed.

## 11. Cleanup

The namespaced track-b-live agents were stopped by pid with SIGTERM: pid 20157 (old binary) and pid 90531.

## Follow-ups

- Smoke suite: poll for the fixture instead of using a fixed sleep.
- AppDiscovery: check for extension names, the same failure class as step 8.
- R-L2 dedupe.
- get_scripting_dictionary: add /System/Library/CoreServices as a fallback so "System Events" resolves by name when it is not running.

## Unresolved questions

- Should the "shallow controls first; for deep content use role plus label or get_app_state" guidance go into SKILL.md or into the find_elements description?
