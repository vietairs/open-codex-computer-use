# Prediction: Track B fast channels (P2 + 8 amendments), per file

Date 2026-09-29. Base afb60fa, read in `.claude/worktrees/fast-macos-channels`. The code-review-graph index is empty for this worktree, and building it would write inside the worktree, so every claim below comes from grep and reading the source. Decisions 7-10 and 14-16 are fixed and are not reopened here.

## Verdict: CAUTION
No STOP trigger was found. The design holds, but five findings change the plan: the app target has no test target, three `private` symbols block the "new extension file" seam, the `find_elements` index range can collide with full-tree indices, a lock-guard ordering can make the key refusal test pass for the wrong reason, and there are more count sites than the two already named.

## Structural facts that shape the plan
- `Package.swift` has test targets only for `OpenComputerUseKit` and `StandaloneCursorSupport`. Code in `apps/OpenComputerUse` (the proxy, main and `MCPAppRuntime`) cannot be reached by `swift test`. Every testable behaviour must therefore live in the Kit, and the app files should only wire it in with a line or two.
- `StdioMCPServer.handle` returns nil for notifications. The relay drops `NSNull` responses (`MacOSAppAgentProxy.swift:131-135`). So the router must allow "no response" as well as "one line in, one line out".
- The guard runs before the switch (`ComputerUseToolDispatcher.swift:61`), and the unknown-tool error comes later, at `:128-129`. On a locked Mac, a "run_script is unsupported in the agent" test would pass because of the lock error.
- The graph index is empty, so the caller lists here come from grep. `sanitizePeerEnvironment` has exactly two callers: the proxy at `:157` and the agent at `:454`. `computerUseServerInstructions(environment:)` has one caller, `MCPServer.swift:97`.

## Per-file prediction
**New Kit: `LocalChannelRouter.swift`** (use PascalCase file names, as the repo does)
- Breaks: the byte-for-byte passthrough when the flag is off. If the router always parses and re-encodes responses, JSONSerialization changes key order and escaping. When the flag is unset, it must forward raw lines without parsing them.
- Also breaks: JSON-RPC batch arrays and notifications. Arrays must pass through untouched, and a nil response must write nothing.
- Callers: the relay (`proxyMCP`), direct `server.run()` (`OpenComputerUseMain.swift:49`) and `MCPAppRuntime.processStandardIO` (`MCPAppRuntime.swift:95`).
- Tests: flag off gives identical `initialize` and `tools/list` bytes. Flag on appends 5 tools and swaps the AppleScript line. The `forward` closure calls `XCTFail` if it ever receives run_script, open_url or run_shortcut.

**New Kit: `OsascriptChildRunner.swift`**
- Breaks: fd inheritance. The relay's agent socket is opened without CLOEXEC (`MacOSAppAgentProxy.swift:553`).
- Hotspots:
  - Deadlock when the child fills a pipe while the runner waits for exit. stdout and stderr must be drained at the same time as the child runs.
  - SIGKILL frees the relay but does not stop an Apple Event already inside Mail.
- Tests run in CI on `macos-26` (`ci.yml:61-65`). They must use only scripts that send no Apple Events, such as `return 1` and `delay 30` for the timeout, or the TCC prompt hangs CI.
- The fd test needs an injectable executable path, for example `/bin/ls /dev/fd`, plus a deliberately inheritable fd opened in the parent.

**New Kit: `ScriptPolicyFilter.swift`**
- Nothing existing breaks. The risk is over-matching: a legitimate Mail script whose text contains "do script" is rejected.
- The normaliser must join `¬` continuation lines (including CRLF) before matching.
- Tests need a table of cases: each verb, each alias, each JXA form, the continuation form, and a clean Mail search that must pass.

**New Kit: `ScriptAuditLog.swift`**
- Depends on Track A's owner-only file helper. At base the only O_NOFOLLOW code is a read in `DecisionRemoteBackend.swift:129`, so no write helper exists yet. Either build after the rebase, or write a private helper and dedupe it later.
- Hotspot: several hosts run several relays, and all of them append to one file. Single-write O_APPEND is fine, but rotation by rename races between relays, so it needs `flock` or a per-pid file.
- Tests: mode 0600, a pre-placed symlink is refused, stderr carries only the sha256 and never the script text.

**New Kit: `ScriptingDictionaryLookup.swift`**
- Mail's `xi:include` points to `/System/Library/ScriptingDefinitions/CocoaStandard.sdef` (per the brainstorm). Foundation's `XMLDocument` does not resolve XInclude itself, so includes must be resolved by hand after `realpath`, checking the path prefix.
- Tests with fixture sdefs:
  - Including `/etc/hosts` is refused.
  - A `../` traversal and a symlink out of the bundle are refused.
  - An external entity is not loaded (`nodeLoadExternalEntitiesNever`).
  - A `term` filter keeps the output under a size cap.

**New Kit: `ShortcutAndUrlLauncher.swift`**
- The handler check needs an injectable resolver in place of `NSWorkspace.urlForApplication(toOpen:)`, so tests never open anything.
- Deny by bundle ID: `com.apple.Terminal`, `com.googlecode.iterm2`, `com.apple.ScriptEditor2`, `com.apple.shortcuts`. Also deny the schemes `file`, `shortcuts`, `x-man-page`, `ssh` and `telnet`.
- Killing the `shortcuts run` CLI may not stop the shortcut itself; that needs a live check.

**New Kit: `AccessibilityElementSearch.swift`** (the lean walker)
- `shouldSkipChild` is `private` (`AccessibilitySnapshot.swift:1223`). To reuse it, a one-word visibility change is needed in Track A's file. `childTraversalAttributes` (`:1199`) is already internal.
- Tests: label matching against title or description, early stop, the `max_nodes` bound, and `truncated`/`nodes_visited`. Fixture-driven where possible.

**`ComputerUseService.swift`** (medium clash)
- `snapshotsByApp` (`:460`), `currentSnapshot` (`:959`) and `lookupElement` (`:995`) are all `private`. An extension in a new file cannot reach them, so parallel-tracks rule 6 ("append only") still needs a visibility edit at `:460`.
- The merge must rebuild the `let` struct `AppSnapshot` and rewrite every key that `refreshSnapshot` writes (`:982-991`).
- Every action calls `refreshSnapshot` and replaces the merged snapshot, so hits at 10000 and above go stale after one action. This is correct, but it must be documented.
- **Collision:** `max_tree_nodes` is an unbounded positive integer (`ComputerUseToolDispatcher.swift:70`). A full tree with 10,000 or more nodes reuses indices from 10000 upward, so a hit could resolve to a different element. Fix: cap `max_tree_nodes` below the base, or allocate from `max(existing key) + 1`, still never resetting.
- The CLI path builds a new service per `call` (`ComputerUseToolDispatcher.swift:325`), so hits only survive inside one `--calls` sequence.

**`AccessibilitySnapshot.swift`**: only the `shouldSkipChild` visibility change above. The compact view skips elements with no `treeLineOffsets` entry (`:160`), so merged hits cannot trap there. However, the "N of M" header counts them (`:178`). A test must pin whichever behaviour is chosen.

**`ToolDefinitions.swift` and `ComputerUseToolDispatcher.swift`**: append find_elements. The dispatcher's guard covers it for free. `computerUseServerInstructions` compares the listed count with the `all` count (`MCPServer.swift:26`), so find_elements must go into `all`, not `listed`, or the cascade guide leaks.

**`MCPServer.swift`**
- Extract `:16` into a named constant, add a test that the base text contains it, and name find_elements in the tool list at `:10`.
- Track A edits the same string literal at `:8/:10/:14`, so a rebase conflict is certain. It is resolved by hand, per rule 8.

**`MacSessionGuard.swift`**: `sanitizePeerEnvironment` (`:64-68`) must drop the scripting flag. Both callers pick this up at once. Add a test next to the existing ones at `OpenComputerUseKitTests.swift:2996-3025`.

**`MacOSAppAgentProxy.swift`, `OpenComputerUseMain.swift`, `MCPAppRuntime.swift`** (app target, untested)
- Keep each change to one call into the router. Set FD_CLOEXEC right after `socket()` at `:553`.
- The relay reads the flag from its own `ProcessInfo`, never from the agent. `connectOrLaunchAgent` passes only the lock key (`:103-105`), and it should stay that way.

**Count sites that break** (the lock names only two):
- `OpenComputerUseKitTests.swift:256` (all).
- `DecisionAdvisorTests.swift:437` (all), `:448` (listed with the advisor), `:457` (listed without it).
- `OpenComputerUseKitTests.swift:2966`: a literal `guiTools` list that should gain find_elements.
- `OpenComputerUseSmokeSuite/main.swift:199` (`tools.count == 9`): not run by `swift test`, but it breaks smoke runs.
- `DecisionAdvisorTests:436` has "StaysNine" in the test name, which then needs renaming.
- After the rebase: `all` = 11, listed with the advisor = 12, with the scripting flag = `all` + 5 router tools.
- Docs: `docs/ARCHITECTURE.md:68,145` ("9 Computer Use tools"), `SKILL.md`, `usage.md`, and the new `references/scripting.md`. The Go runtimes are out of scope.

## Personas: agreements and conflicts
- **Agreed:** every security claim must be a Kit unit test, because the app target cannot be tested. The flag must never cross the socket. find_elements indices must fail closed.
- **Conflict: visibility edits vs. append-only.**
  - Architect: widen three symbols to `internal`.
  - Devil's Advocate: this breaks the letter of rule 6.
  - Resolution: accept one-word visibility edits, list them in the plan, and apply them after the rebase.
- **Conflict: filter strictness.**
  - Security: add more verbs.
  - UX: false positives on `do script` text.
  - Resolution: keep the locked verbs plus their aliases, and document the false-positive cases.
- **Performance:** the ≤50% target is at risk only if the target button sits late in DFS order with `max_nodes`=1200. Record `nodes_visited` with every timing.

## Acceptance criteria: what each one needs to be measurable
| Criterion | Measurable as |
|---|---|
| Mail search via run_script ≤1s | Fix the script text first, for example the first 20 inbox messages whose subject contains "combio". Measure server side, from the relay receiving `tools/call` to its response. Report the median of 5 warm runs. Time the same text in Terminal first (counsel check 3). |
| find_elements ≤50% of get_app_state | Use the same Mail window and state, and one named target button. Server-side medians of 5, alternating the two tools. Log `nodes_visited`. Baseline on afb60fa. |
| Flag unset: tool not listed | Router unit test: `tools/list` and `initialize` bytes equal the forwarded bytes. The AppleScript line is still present. |
| Filter rejects a script | Table-driven `ScriptPolicyFilter` test, including continuation and JXA forms. |
| Never crosses the socket | (a) The agent's `StdioMCPServer` with an *unlocked fake guard* returns unsupported for run_script. (b) `runOpenComputerUseCall(.single("run_script"))` fails. (c) The sanitizer drops the flag. (d) The router's `forward` is never called for local tools. (e) The fd test sees only fds 0-2. |
| `swift test` green | The counts above are updated; osascript tests send no Apple Events; no test depends on TCC. |

## Recommendations
1. Put all logic in Kit types with injected seams (executable path, clock, URL-handler resolver, log directory) so every security criterion runs in CI.
2. Fix the index collision before writing code. Either cap `max_tree_nodes`, or allocate hits from above the highest existing key.
3. Make the refusal tests use an unlocked fake guard, so they fail if the dispatcher ever gains a run_script case.
4. List the three visibility edits and the six count sites in the plan as rebase items.
5. Drain the child's pipes at the same time as it runs, cap each at 64 KB, and test a script that prints more than 64 KB.

## Unresolved questions
1. Which Mail button and which exact script text define the two timing criteria?
2. Should `max_tree_nodes` be capped (a small API change), or should hit indices be allocated dynamically?
3. Does killing `shortcuts run` stop the shortcut, and does "Allow Running Scripts" gate "Run Shell Script"?
4. What retention and rotation policy should `scripts.log` have, given several relays and email content in the log?
5. Should the smoke suite gain a flag-on case, since that is the only place relay wiring could be exercised end to end?
