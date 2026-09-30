# Track B threat model: fast non-screenshot channels (PR B)

Scope: the five relay-local tools (`run_script`, `get_scripting_dictionary`, `open_url`, `run_shortcut`,
`list_shortcuts`) and the agent-side `find_elements`. Design is fixed (outcome-lock decisions 7-10, 14-16). This file
names the assets, actors, and the control that answers each threat, and maps each control to the test that proves it.
Phase 08 reviews the implementation against this table.

## What the code stores, protects, or exposes

| Asset | Where | Why it matters |
|---|---|---|
| Automation TCC grants of the host app (Terminal, iTerm, VS Code, Claude.app, Codex.app) | TCC, keyed (host app x target app) | An osascript child of the relay sends Apple Events under the host's responsible-app grant, never OCU.app's. Grants are inherited from earlier Terminal->Mail approvals and shared by every process under that host. |
| OCU.app's Accessibility + Screen Recording grants | The app agent (`MacOSAppAgentProxy.swift:363-449`) | Must stay unreachable from script execution. Confused-deputy precedent: memory `app-agent-ipc-confused-deputy`. |
| The relay's authenticated agent socket fd | Relay, created without CLOEXEC (`MacOSAppAgentProxy.swift:553`) | A script child that inherits it can speak to the agent as the relay. |
| Script text, URLs, shortcut inputs | Audit log + stderr | Carries user data (email subjects, bodies). Host MCP logs are not 0600. |
| Relay responsiveness | `proxyMCP` is a strict serial loop (`MacOSAppAgentProxy.swift:121-137`) | A hung script blocks every later call from that host. |

## Actors and vectors

| # | Actor / vector | Threat | Control | Proven by (phase: test) |
|---|---|---|---|---|
| T1 | Operator did not opt in | Script tools appear or run anyway | Router is a byte-for-byte passthrough unless `OPEN_COMPUTER_USE_ENABLE_SCRIPTING` is truthy in the relay's OWN launch env; the "Avoid falling back to AppleScript" line stays | 04: `testFlagUnsetRouterIsBytePassthrough`, `testFlagUnsetInitializeKeepsAppleScriptLine` |
| T2 | Same-uid peer on the agent socket | Runs scripts through the agent (confused deputy) | Kit dispatcher has no case for any local tool; tools are listed only by the relay router, never `ToolDefinitions`; the flag is stripped by `MacSessionLockPolicy.sanitizePeerEnvironment` on both sides | 04: `testAgentDispatcherRefusesEveryLocalToolWhenUnlocked`, `testSanitizerDropsScriptingFlag`, `testListedNeverContainsLocalTools` |
| T3 | `open-computer-use call run_script` (CLI) | Runs through `runOpenComputerUseCall` in the agent (`MacOSAppAgentProxy.swift:489-490`) | Same missing dispatcher case; no CLI change (amendment 3) | 04: `testCallRunScriptFailsClosedThroughCLIRunner` |
| T4 | Script child | Inherits the relay's agent socket or other fds | `posix_spawn` with `POSIX_SPAWN_CLOEXEC_DEFAULT`, fresh pipes on fds 0-2 only; plus `FD_CLOEXEC` on the relay socket | 01: `testChildSeesOnlyStandardDescriptors`; 06: grep gate |
| T5 | Script child | Reads relay env secrets (host tokens, decision-model URLs) | Env scrubbed to PATH (fixed), HOME, LANG | 01: `testChildEnvironmentIsScrubbed` |
| T6 | Hung or looping script | Wedges the relay | Timeout (default 20s, max 60s, first contact >=30s), SIGTERM then SIGKILL to the child's process group, one absolute deadline over reap and drain, 64 KB caps | 01: `testTimeoutKillsChild`, `testOutputBeyondCapDoesNotDeadlock` |
| T7 | Prompt-injected agent (e.g. text inside an email) | Shell execution via script verbs | Best-effort deny list over an NFKC, Unicode-whitespace-collapsed view and a `(* *)`-stripped view (`do shell script`, `run/load/store script`, `do script`, chevron/ASCII raw events incl. spaced chevrons, `use framework`, `use script(ing additions)`, JXA `doShellScript`, `runScript`, `ObjC.`, `Library(`, `$.NS`, `doScript`). Friction, NOT a boundary; docs say so. | 01: `testFilterRejectsEveryDeniedForm` (table incl. NBSP, fullwidth, comment and spaced-chevron rows), `testCommentMarkerInsideStringCannotHideDeniedPhrase`, `testFilterAllowsPlainMailSearch`; 10: `osacompile` probe |
| T8 | Prompt-injected agent | Destructive Apple Events (send, delete, System Events keystrokes) with no review | Decision 16: main loop narrows the blanket allow so run_script/open_url/run_shortcut go through the auto-mode classifier; guide repeats "ask before sending or deleting"; docs state Codex and Claude.app hosts have no classifier | 10: settings step + step 7 (observed review); 07: `testScriptFirstGuideKeepsAskBeforeDestructive` |
| T9 | Audit tampering | Symlink swap or world-readable log | Dir 0700, file opened `O_WRONLY|O_APPEND|O_CREAT|O_NOFOLLOW|O_CLOEXEC` 0600, fstat owner/mode/regular check, one `write` per entry, `flock` around rotation; audit failure refuses the call | 02: `testLogFileIsOwnerOnly`, `testSymlinkedLogFileIsRefused`, `testWidePermissionLogIsRefused`, `testConcurrentWritersNeverInterleave`; 04: `testAuditFailureRefusesScript` |
| T10 | Host MCP log (stderr) | Leaks script text, or forged lines through control characters in `app` | stderr carries metadata only (tool, app, sha256, exit, duration); control characters escaped | 02: `testStandardErrorCarriesMetadataOnly`, `testMetadataLineEscapesControlCharacters` |
| T11 | Hostile app's sdef | Pulls local files into agent context via XInclude or external entities | `XMLDocument` with `.nodeLoadExternalEntitiesNever`, never `.documentXInclude`; XInclude resolved by hand, `realpath` inside the bundle or `/System/Library/ScriptingDefinitions` only; non-file hrefs refused; depth <= 2; size cap | 03: `testIncludeOutsideAllowedRootsIsSkipped`, `testTraversalAndSymlinkIncludesAreSkipped`, `testExternalEntityIsNotLoaded` |
| T12 | `open_url` | Launches Terminal/iTerm/Script Editor/Shortcuts, automation or IDE handlers, network mounts, Help Viewer, `file:`, `ssh:`, man pages | Blocked schemes (incl. `smb afp nfs cifs ftp ftps sftp vnc help`) + blocked handler bundle ids (incl. Automator, NetAuthAgent, VS Code, Alfred, and unverified automation apps) + handler must be a `.app` + unresolved handler rejected; the checked handler is the one that opens the URL | 03: `testUrlPolicyTable`, `testOpenerReceivesTheCheckedHandler` |
| T13 | `run_shortcut` | Option injection into `/usr/bin/shortcuts`; user shortcut containing "Run Shell Script" | Names starting with `-` rejected; input via 0600 temp file in a 0700 temp dir, removed after; flag-gated, logged, documented | 03: `testShortcutNameCannotInjectOptions`, `testShortcutInputFileIsPrivateAndRemoved` |
| T14 | Stale `find_elements` hit | Resolves to a different element after refresh | Process-global monotonic allocator from base 1_000_000 plus a per-process seed, never reused within one agent process, always above the highest existing key; merge only on matching `targetWindowID` AND `windowBounds` in accessibility mode | 05: `testAllocatorNeverReusesIndices`, `testMergeRequiresMatchingWindow`, `testFreshSnapshotDropsHitIndices` |
| T15 | Locked Mac | Script runs while locked | Router calls `MacSessionGuard.requireUnlocked(for:)` with the relay's own policy before any local tool | 04: `testLockedGuardBlocksLocalTools` |
| T16 | Refusal test passing for the wrong reason | Agent refusal masked by the lock error (`ComputerUseToolDispatcher.swift:61` runs before `:128-129`) | Refusal tests use an UNLOCKED fake guard and assert `unsupportedTool`, never the lock text | 04: same tests as T2 |
| T17 | Prompt-injected agent probing the filter | Rejected attempts leave no forensic trace (decision 8: every script text is logged) | `.request` entry (full text) written before the lock guard, argument validation and the filter; `.result` records `rejected:<reason>`; audit failure still refuses | 04: `testFilterRejectionIsLoggedAndNeverSpawns`, `testAuditFailureRefusesScript`, `testOpenUrlAndShortcutAreAuditedAndRefusedWhenLogUnsafe` |
| T18 | Injected text in an AX title/description (web page, HTML email) | Forges a `find_elements` row that maps a harmless label to a destructive index | Every AX-sourced string escaped (`sanitizeText` + CR, U+2028/2029, `"`), capped at 500 characters | 05: `testRowEscapesInjectedNewlines` |
| T19 | `open_url` handler swap | The handler checked differs from the handler launched (TOCTOU) | `opener` receives the checked handler URL and opens with `NSWorkspace.open(_:withApplicationAt:configuration:)` | 03: `testOpenerReceivesTheCheckedHandler` |
| T20 | Hostile app's sdef | Wedges the serial relay or exhausts memory (include bombs, hostile XPath, FIFO) | <= 16 includes per document, 8 MB expanded-bytes cap, xpointer limited to the three shapes Apple ships, files opened `O_NOFOLLOW|O_NONBLOCK` and `fstat`-checked as regular and <= 4 MB | 03: `testIncludeCountIsBounded`, `testUnsupportedXPointerIsSkipped`, `testSupportedXPointerShapes`, `testFifoDefinitionIsRefusedWithoutBlocking` |
| T21 | `get_scripting_dictionary` (read-only, auto-allowed) | Launches the target or sends it an Apple Event from the relay | Static `.sdef` reads only (extension-less keys get `.sdef`); no in-process `OSACopyScriptingDefinitionFromURL` | 03: `testExtensionlessDefinitionKeyResolves`, `testAppWithoutAnySdefThrowsNoScriptingDefinition`, grep gate; 10: step 8 |
| T22 | Two relays rotating the audit log | A writer holding the old inode rotates again and destroys the previous generation | After `flock`, compare `fstat(fd)` with `lstat(path)` on dev/ino and reopen on mismatch | 02: `testConcurrentRotationKeepsPreviousGeneration` |
| T23 | Script descendant (`sleep 30 &`) holding the output pipes | Wedges the relay after the leader exits | Single reaper; post-exit `kill(-pid, SIGKILL)`; drain bounded by `drainGracePeriod` after the leader exits; child cwd `/` | 01: `testLingeringDescendantDoesNotWedgeRunner`, `testBackgroundedDescendantWithShortTimeoutReturnsPromptly`, `testChildWorkingDirectoryIsRoot` |
| T24 | Relay killed mid-script (host Ctrl-C, SIGTERM, SIGHUP) | osascript child in its own process group is orphaned and runs to completion | Accepted documented residual (user decision 2026-09-29: no signal forwarding); the log shows a request with no result | 07: `scripting.md` text (phase 07 Verify 8) |
| T25 | `find_elements` hit outside the window (row scrolled out of view) | `click` posts a pid-targeted click at an off-window point: a wrong click or a silent no-op | `localFrame` is nil unless the frame's midpoint lies inside the window, so `click` fails with `no clickable frame` before any event | 05: `testOffWindowHitHasNoClickableFrame` |

## Residual risks (documented, not fixed)

- Shell-capable hosts (Claude Code, Codex) bypass the filter with Bash `osascript`. On an MCP-only host, enabling the
  flag effectively grants a shell. `references/scripting.md` must say both.
- SIGKILL frees the relay but not the target app: Mail keeps executing an in-flight Apple Event. Guidance: keep
  queries small (one mailbox, first N).
- System Events UI scripting launders the host's Accessibility grant and bypasses the visible cursor.
- Desktop hosts whose responsible app lacks `NSAppleEventsUsageDescription` may get a silent -1743 with no prompt
  (counsel belief, unverified; live check in phase 10).
- Filter bypass classes stay open by design: iTerm `write text`, Finder opening a `.command`, JXA bracket access,
  System Events keystrokes into Terminal.
- `open location` or Finder inside `run_script` bypasses the `open_url` policy, so that policy is friction only.
- `target_app` in the audit log and the first-contact timeout floor are keyed on the agent-declared `app` argument, not
  the app the script actually tells; both are advisory.
- A script can show `display dialog ... default answer "" with hidden answer` and return what the user typed to the
  agent (credential phishing). Documented in `scripting.md`.
- If the relay is killed mid-script, the osascript child is orphaned (T24). Accepted by the user (2026-09-29).
- Hit indices from before an agent restart: the per-process seed makes a collision unlikely, not impossible.
- Apps with only legacy `aete` or dynamic terminology get no dictionary summary (`run_script` still works). Static-only
  sdef accepted by the user (2026-09-29).
- The audit log keeps 10 MB plus one rotated file (`scripts.log.1`) and holds script text, which may include email
  content. Retention confirmed by the user (2026-09-29).
- Pre-existing, outside PR B: `sanitizePeerEnvironment` is a denylist and the agent `setenv`s peer keys process-wide,
  so DEBUG-only keys such as `OPEN_COMPUTER_USE_LOCK_FAIL_OPEN` can be forged per call. Handed to the main loop.
