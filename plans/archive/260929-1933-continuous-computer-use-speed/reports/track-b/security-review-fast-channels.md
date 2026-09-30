# Security review: fast non-screenshot channels (PR B)

Date: 2026-09-29. Reviewer: code-reviewer (implemented none of phases 01-07). Read-only.
Diff: `git -C .claude/worktrees/fast-macos-channels diff afb60fa..HEAD` (7 commits, 852105f..50b5f2f, 39 files,
+6436/-41). Paths below are relative to `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/` unless prefixed.

## Verdict

**PASS on findings: no open Critical or High.** 3 Medium, 7 Low. Every threat row T1-T25 is traced to code and a named test
(T24 to docs). The threat model has 25 rows, one more than the task brief's "T1-T24", so all 25 are covered.

**Step 4 (build + test) was NOT independently executed.** Inside the sandbox, `swift build` fails with
`sandbox-exec: sandbox_apply: Operation not permitted` because SwiftPM's nested sandbox cannot be applied. The retry
with `--disable-sandbox` was denied by the auto-mode classifier, and I did not work around the denial. The only
evidence is the implementer's record in `plan-track-b/impl-notes.md:195`: "full `swift build && swift test` 523 tests,
0 failures, 2 pre-existing skips" at the phase-07 commit. **The main loop must run
`cd $WT && swift build && swift test 2>&1 | tail -15` outside the sandbox and record the `Executed ... 0 failures`
line before the gate closes.**

## Threat rows

| # | Status | Control (file:line) | Test |
|---|---|---|---|
| T1 | verified | Passthrough when disabled, with no parsing: `LocalChannelRouter.swift:29-31`. Flag read once from launch env: `LocalChannelRouter.swift:18-24`, `LocalChannelToolHandlers.swift:8-13`. AppleScript line kept: `MCPServer.swift:16`, `LocalChannelGuidance.swift:6-8` | `testFlagUnsetRouterIsBytePassthrough`, `testFlagUnsetInitializeKeepsAppleScriptLine`, `testFlagValuesParse` |
| T2 | verified | No dispatcher case, so it falls to `unsupportedTool`: `ComputerUseToolDispatcher.swift:139`. Local defs live only in `LocalChannelToolDefinitions` (`LocalChannelToolHandlers.swift:27-119`), not in `ToolDefinitions`. Flag stripped: `MacSessionGuard.swift:65-71`. The agent re-applies the filter: `apps/.../MacOSAppAgentProxy.swift:404-405,450-452` | `testAgentDispatcherRefusesEveryLocalToolWhenUnlocked`, `testSanitizerDropsScriptingFlag`, `testListedNeverContainsLocalTools` |
| T3 | verified | Same missing case; the CLI is unchanged | `testCallRunScriptFailsClosedThroughCLIRunner` |
| T4 | verified | `POSIX_SPAWN_CLOEXEC_DEFAULT` plus dup2 of 0-2 only: `ConfinedChildProcessRunner.swift:266-272`. Relay socket gets `FD_CLOEXEC`: `apps/.../MacOSAppAgentProxy.swift:555-559` | `testChildSeesOnlyStandardDescriptors` |
| T5 | verified | Env limited to PATH (fixed), HOME (absolute) and LANG: `ConfinedChildProcessRunner.swift:63-70`. Used by osascript (`OsascriptChildRunner.swift:105`) and shortcuts (`ShortcutAndUrlLauncher.swift:186,213`) | `testChildEnvironmentIsScrubbed`, `testScrubbedEnvironmentFallsBackForRelativeHomeAndMissingLang` |
| T6 | verified | Timeout 20 s default, 60 s max, 30 s floor on first contact: `OsascriptChildRunner.swift:59-73`. TERM, then KILL to the process group: `ConfinedChildProcessRunner.swift:176-185`. One deadline governs reap and drain: `:187-206`. 64 KB output cap: `:56,335-339`. 64 KB source cap: `OsascriptChildRunner.swift:96-99` | `testTimeoutKillsChild`, `testTermIgnoringChildIsKilled`, `testOutputBeyondCapDoesNotDeadlock`, `testDelayScriptTimesOut` |
| T7 | verified (friction) | Deny list: `ScriptPolicyFilter.swift:21-39`. NFKC + whitespace collapse + chevron normalization: `:43-55`. Two views, raw and `(* *)`-stripped: `:57-65` | `testFilterRejectsEveryDeniedForm`, `testCommentMarkerInsideStringCannotHideDeniedPhrase`, `testFilterAllowsPlainMailSearch`, `testFilterRejectsDeniedPhraseInsideStringLiteral`. The phase-10 `osacompile` probe is still open (see R9) |
| T8 | verified (guidance) / residual | Ask-before-destructive line in the guide: `LocalChannelGuidance.swift:18`. Docs say only Claude Code has a classifier: `skills/.../references/scripting.md:58-61`. Destructive annotations: `LocalChannelToolHandlers.swift:30-32`. The settings change and the observed review are phase 10 | `testScriptFirstGuideKeepsAskBeforeDestructive` |
| T9 | verified | Dir created by `mkdir` at 0700 and `lstat`-checked for real dir, owner and no group/other bits: `ScriptAuditLog.swift:191-213`. File opened `O_WRONLY|O_APPEND|O_CREAT|O_NOFOLLOW|O_CLOEXEC` 0600, `fstat` checks regular file, owner and mode: `:220-237`. `flock`: `:240`. Single `write`: `:262-272`. A failed audit refuses the call: `LocalChannelToolHandlers.swift:421-435` | `testLogFileIsOwnerOnly`, `testSymlinkedLogFileIsRefused`, `testWidePermissionLogIsRefused`, `testSymlinkedDirectoryIsRefused`, `testConcurrentWritersNeverInterleave`, `testAuditFailureRefusesScript` |
| T10 | verified; minor gap L1 | Metadata-only stderr line: `ScriptAuditLog.swift:125-133`. Escapes C0, DEL, U+2028 and U+2029, with a 128-scalar cap: `:140-151`. No payload field in the line | `testStandardErrorCarriesMetadataOnly`, `testMetadataLineEscapesControlCharacters`, `testMetadataLineCapsAgentInfluencedValues`; `testRunScriptEndToEnd` asserts the token is absent from stderr |
| T11 | verified | Data-only parse with `.nodeLoadExternalEntitiesNever`, no URL, no `.documentXInclude`: `ScriptingDictionaryLookup.swift:194-200`. Grep for `documentXInclude`, `XMLDocument(contentsOf/url` and `OSACopyScriptingDefinition` over sources returns nothing. Includes resolved by hand; non-file schemes refused: `:371-381`. `realpath` plus trailing-`/` root check: `:215-221,311-318` | `testIncludeOutsideAllowedRootsIsSkipped`, `testTraversalAndSymlinkIncludesAreSkipped`, `testNonFileIncludeSchemeIsSkipped`, `testExternalEntityIsNotLoaded`, `testIncludeRootsAreBundleAndSystemDefinitions` |
| T12 | **gap (Medium, M1)** | Blocked schemes: `ShortcutAndUrlLauncher.swift:16-19`. Blocked handler ids: `:23-40`. Handler must resolve and be an `.app`: `:53-58`. The id list covers VS Code stable and Cursor only, although the threat row says "IDE handlers". A handler with a nil bundle id is allowed (`:59`, L3) | `testUrlPolicyTable`, `testBlockedSetsCoverTheVerifiedEntries`, `testOpenerIsCalledOnlyWhenAllowed` |
| T13 | verified | Leading `-` and NUL rejected: `ShortcutAndUrlLauncher.swift:159-161`. Input goes in a 0700 dir with a random UUID, via `O_EXCL|O_NOFOLLOW` 0600, and is removed in `defer`: `:163-179,230-251` | `testShortcutNameCannotInjectOptions`, `testShortcutRunArguments`, `testShortcutInputFileIsPrivateAndRemoved` |
| T14 | verified / residual (L5) | Process-global, locked, monotonic allocator: base 1,000,000 plus a per-process seed, always above the cached max: `ElementSearchSnapshotMerge.swift:14-41`. Merge requires `.accessibility` mode, the same `targetWindowID` AND the same `windowBounds`: `:51-62` | `testAllocatorNeverReusesIndices`, `testMergeRequiresMatchingWindow`, `testFreshSnapshotDropsHitIndices` |
| T15 | verified | Lock guard runs on every local tool, using the relay's own `MacSessionGuard()`: `LocalChannelToolHandlers.swift:199,294,331,387,406` | `testLockedGuardBlocksLocalTools` (3 `rejected:locked` audit outcomes) |
| T16 | verified | Refusal tests use `unlockedGuard`, assert `unsupportedTool("<name>")` and assert the lock text is absent | `testAgentDispatcherRefusesEveryLocalToolWhenUnlocked` |
| T17 | verified | Request entry is written before the lock, the argument checks and the filter: run_script `LocalChannelToolHandlers.swift:191` (lock `:199`, args `:205-224`, filter `:226-232` writes `rejected:filter:<pattern>`); open_url `:287` (lock `:294`); run_shortcut `:324` (lock `:331`). Only calls with a missing or non-string payload return before audit, and they have nothing to log | `testFilterRejectionIsLoggedAndNeverSpawns`, `testInvalidArgumentsAreLoggedAndNeverSpawn`, `testOpenUrlAndShortcutAreAuditedAndRefusedWhenLogUnsafe`, `testOpenUrlPolicyRejectionIsLoggedAsRejected`, `testRunScriptWithoutSourceIsAnErrorWithNothingToLog` |
| T18 | verified | `escapeElementSearchText` escapes backslash, then applies `sanitizeText` (`\n`, cap), then CR, VT, FF, NEL, U+2028, U+2029 and `"`: `ElementSearchSnapshotMerge.swift:124-139`. Applied to role, label, id, actions (`:147-169`) and the header (`ComputerUseService.swift:2143-2147`) | `testRowEscapesInjectedNewlines` (covers `\n`, CRLF, fake `[1000005]` rows) |
| T19 | verified | Handler resolved once and passed to `opener(url, handler)`, which calls `NSWorkspace.open(_:withApplicationAt:configuration:)`: `ShortcutAndUrlLauncher.swift:111-141` | `testOpenerReceivesTheCheckedHandler` |
| T20 | verified, gap (L4) | At most 16 includes per doc: `ScriptingDictionaryLookup.swift:246-253`. Depth limit 2: `:294-297`. 8 MB expanded cap: `:334-338`. XPointer limited to 3 shapes: `:225-234,353-357`. Files opened `O_NOFOLLOW|O_NONBLOCK`, `fstat` must show a regular file of at most 4 MB: `:151-172` | `testIncludeCountIsBounded`, `testIncludeDepthIsBounded`, `testUnsupportedXPointerIsSkipped`, `testSupportedXPointerShapes`, `testFifoDefinitionIsRefusedWithoutBlocking` |
| T21 | verified | Static `.sdef` read; an extension-less key gets `.sdef`: `ScriptingDictionaryLookup.swift:104-132`. App lookup uses `runningApplications`, `urlForApplication(withBundleIdentifier:)` and `fileExists` only, with no launch and no Apple Event: `:531-553`. The grep gate is empty | `testExtensionlessDefinitionKeyResolves`, `testAppWithoutAnySdefThrowsNoScriptingDefinition`, `testDefinitionOutsideBundleIsRefused` |
| T22 | verified | After `flock`, `lstat(path)` dev/ino is compared with the `fstat` result, reopening up to 3 times: `ScriptAuditLog.swift:247-254`. Only the holder of the live inode's lock renames: `:104-114` | `testConcurrentRotationKeepsPreviousGeneration`, `testRotationKeepsOnePreviousGeneration` |
| T23 | verified | Single reaper using `waitid(WNOWAIT)`, then waits for the go-ahead before `waitpid`: `ConfinedChildProcessRunner.swift:135-164`. After exit, `kill(-pid, SIGKILL)` runs while the zombie still pins the pgid: `:188-192`. Drain is bounded to `leaderObserved + drainGracePeriod`: `:323-326`. cwd is `/`: `:273-274`. `F_SETNOSIGPIPE` on the stdin pipe: `:107` | `testLingeringDescendantDoesNotWedgeRunner`, `testBackgroundedDescendantWithShortTimeoutReturnsPromptly`, `testChildWorkingDirectoryIsRoot` |
| T24 | residual (documented) | `skills/open-computer-use/references/scripting.md:95-96` ("orphaned and runs to completion; the log then shows a request with no result. Signals are not forwarded.") and `docs/SECURITY.md` (scripting section) | docs trace |
| T25 | verified | `localFrame` is nil unless the frame midpoint is inside the window: `ElementSearchAccessibilitySource.swift:273-278`. `click` then throws `no clickable frame` before any event: `ComputerUseService.swift:648-651` | `testOffWindowHitHasNoClickableFrame` |

Specific checks from Task 8.1 step 3: all hold, with the exceptions noted in L1-L4. The agent launch environment is
unchanged: the diff does not touch `connectOrLaunchAgent` (`apps/.../MacOSAppAgentProxy.swift:81-104`). Hits-only
snapshots carry the focused element (`ElementSearchSnapshotMerge.swift:104`, `testHitsOnlySnapshotCarriesFocus`).
`find_elements` goes through the dispatcher lock guard (`ComputerUseToolDispatcher.swift:61`) and is refused for
the fixture app (`ComputerUseService.swift:2083-2086`).

## Findings

### Critical
None.

### High
None.

### Medium

**M1. The `open_url` handler denylist misses IDE and terminal handlers the threat row claims to block** (T12, phase 03).
`blockedHandlerBundleIdentifiers` (`ShortcutAndUrlLauncher.swift:23-40`) has `com.microsoft.vscode` and Cursor, but not
`com.microsoft.vscodeinsiders`, `com.vscodium`, `com.exafunction.windsurf`, `dev.zed.zed`, `com.jetbrains.toolbox`,
`dev.warp.warp-stable` or Script Debugger (`com.latenightsw.scriptdebugger*`, a common `applescript:` handler).
VS Code-family `vscode-insiders://vscode.git/clone?url=...` clones and opens an attacker repo. Warp and Toolbox URLs
open terminals or projects. This is friction only, because `run_script` can use `open location`, which caps the severity.
The row still overstates the control.
Fix: add these ids. Also consider refusing any non-`http(s)`/`mailto` scheme whose handler lies outside `/Applications`
and `/System/Applications`, or whose bundle id is unknown. Extend `testBlockedSetsCoverTheVerifiedEntries`.

**M2. Build and test gate not independently verified** (phase 08, Task 8.1 step 4). This is an environment limit (see
Verdict), not a code defect. Disposition: the main loop runs the suite outside the sandbox and records the result
line here.

**M3. Standard Additions file I/O is unfiltered and not named in the docs as a bypass class** (T5/T7, phase 07 docs).
`read POSIX file ".../remote-backend.json"` returns secrets to the agent, and `open for access ... write` can drop a
`~/Library/LaunchAgents` plist, which is a shell at next login. Neither contains a denied phrase. The docs cover this
only through the phrase "equivalent to granting that host a shell". T5 ("env scrubbed") can read as if secrets are
protected, but secrets on disk remain reachable. Decision 8 (best-effort filter) stands, so this is a documentation fix
only. Fix: add one bullet to `references/scripting.md` "Security model": "Scripts can read and write any file the
user can (Standard Additions `read`/`write`), including credentials and LaunchAgents."

### Low

- **L1** (T10, phase 02). `sanitizedMetadataValue` (`ScriptAuditLog.swift:143-148`) does not escape C1 controls
  (U+0080-U+009F, including U+0085 NEL and U+009B CSI) or bidi overrides (U+202A-U+202E, U+2066-U+2069). `app` is
  agent-controlled, so NEL can split a line in some log collectors, and U+009B can act as CSI in terminals that honour
  8-bit C1. Fix: escape `0x80...0x9F` and the bidi range. The find_elements escaper already handles NEL.
- **L2** (phase 03). The Shortcuts run continues after a timeout: `/usr/bin/shortcuts` delegates to a background
  runner, so the group kill frees the relay but not the shortcut. Undocumented; the timeouts section talks only about
  scripts. Fix: one doc line.
- **L3** (T12, phase 03). A handler whose bundle id cannot be read is allowed (`ShortcutAndUrlLauncher.swift:59`).
  Fix: reject when `bundleIdentifierResolver` returns nil.
- **L4** (T20, phase 03). Each include target is fully read (up to 4 MB) before the 8 MB running-total check
  (`ScriptingDictionaryLookup.swift:320-338`). A hostile sdef with 272 reachable includes (16 + 16x16) of 4 MB each
  costs about 1 GB of reads on the serial relay once the cap is hit. Memory is transient; this is a seconds-scale stall.
  Fix: `fstat` first and skip when `loadedBytes + st_size > maximumExpandedBytes`. Also add a billion-laughs (internal
  entity) test: libxml2's amplification guard is assumed, not tested.
- **L5** (T14, phase 05). `get_app_state.max_tree_nodes` is uncapped (`ComputerUseToolDispatcher.swift:70`). A tree
  with more than about 1M rendered nodes would give full-tree indices that overlap hit indices, so a stale hit could name
  a new element. This is not reachable in practice, and the allocator comment documents it. Fix: cap `max_tree_nodes`
  below `ElementSearchIndexAllocator.base`.
- **L6** (T11, phase 03). There is a TOCTOU between `realpath` and `open(O_NOFOLLOW)` on include paths, because only
  the last component is no-follow. It needs a same-uid racer, and an included file must be well-formed XML with
  `suite`/`command`/`class` shape to reach the summary. Accept.
- **L7** (functional, phase 10). In relay mode `proxyMCP` runs on the main thread (`runProxy` is `@MainActor`), and
  `openWithCheckedHandler` blocks it on a semaphore for up to 10 s waiting on the `NSWorkspace.open` completion. If
  that completion needs the main queue, the call reports `open_url failed` while the URL still opens, and the audit
  outcome says `error`. Verify live in phase 10.

## Red-team (offline, on paper plus safe local probes)

| # | Probe | Result |
|---|---|---|
| R1 | JSON-RPC batch containing `run_script` | Not a dict, so forwarded untouched (`LocalChannelRouter.swift:32-35`). The agent then returns `unsupportedTool`. `testBatchArrayIsForwardedUntouched` |
| R2 | `params.name = "Run_Script"` | Exact `Set.contains` fails, so it is forwarded and refused by the agent. `testCaseVariantToolNameIsForwarded` |
| R3 | Local tool as a notification (no id) | Runs nothing and answers nothing (`LocalChannelRouter.swift:86`) |
| R4 | Filter bypass: JXA bracket access | Local probe `osascript -l JavaScript -e 'typeof $.system+" "+typeof $.NSTask+" "+typeof $["NSTask"]'` printed `undefined function function`. So `$["NSTask"]` reaches NSTask with no import and bypasses `$.ns`. `$.system` is not reachable. This is a documented class (decision 8); no fix demanded |
| R5 | Filter bypass: string-built JXA (`eval`, `this["Ob"+"jC"]`) and `Application("Shortcuts Events").runShortcut` | Bypass; the same documented class. Shortcuts Events also bypasses `run_shortcut`'s name check, but is still audited as run_script |
| R6 | Filter bypass: Standard Additions `read`/`write` file | Not filtered; see M3 |
| R7 | `open_url` `%66ile:///etc/hosts`, `FILE:`, leading whitespace | The scheme cannot contain `%`, so `URL.scheme` is nil and the URL is rejected. Uppercase is lowercased; whitespace is trimmed (`ShortcutAndUrlLauncher.swift:47-51,108`). `testUrlPolicyTable` |
| R8 | `open_url` with `smb:`, `vnc:`, `help:`, `x-man-page:`; automation handlers (Alfred, Raycast, KM Engine, BTT, Hammerspoon) | Blocked. IDE and terminal gaps: M1 |
| R9 | `do shell ¬ -- c` newline `script` (continuation followed by comment) | Normalizer keeps `¬ -- c`, so the phrase is not matched. Validity unknown: in the sandbox `osacompile` fails even on the baseline `do shell script "true"` (-2740, Standard Additions not loadable), so the probe is inconclusive. Hand to the phase-10 `osacompile` probe |
| R10 | sdef include through a symlinked directory | `realpath` resolves it, it lands outside the roots and is skipped. `testTraversalAndSymlinkIncludesAreSkipped` (race: L6) |
| R11 | sdef with 100 includes, hostile xpointer, FIFO `*.sdef` | Bounded, skipped and refused respectively; tests listed at T20. Read amplification: L4 |
| R12 | `find_elements` stale index after `get_app_state max_tree_nodes=2000000` | A fresh snapshot replaces the hits, so the stale index errors unless the tree has more than about 1M nodes (L5) |
| R13 | AX title containing a newline and a fake `[1000005]` row | Escaped; `testRowEscapesInjectedNewlines` |
| R14 | Relay killed mid-script | The request line is written, via `write(2)`, before spawn; no result line follows. Documented residual T24 |
| R15 | Two relays rotating at once | dev/ino recheck after `flock`; `testConcurrentRotationKeepsPreviousGeneration` |
| R16 | `sleep 30 &` holding the pipes | Group SIGKILL after the leader exits, plus a bounded drain; `testLingeringDescendantDoesNotWedgeRunner` |
| R17 | Same-uid peer runs the signed CLI with the flag in its own env | Runs under the peer's own responsible app. This is no escalation over running `osascript` directly |

## Secrets and dependencies

- No dependency change: no `Package.swift`, `Package.resolved`, `package.json` or `go.mod` in the diff. New imports are
  system frameworks only (CryptoKit, Darwin, Dispatch, AppKit, ApplicationServices, CoreGraphics).
- Scanning the added lines for secret patterns found only test fixtures (`SECRET_TOKEN: "s"`, `TOPSECRET` in the XXE
  test). No keys or tokens.
- The four `as!` casts in `ElementSearchAccessibilitySource.swift` sit behind `CFGetTypeID` checks. `try!` appears in
  tests only. No lint suppressions.

## Gate disposition

| finding | severity | disposition |
|---|---|---|
| M1 IDE/terminal handler denylist gaps | Medium | fix in phase 03 (add ids + test), or main loop accepts: friction-only per decision 8 |
| M2 build/test not independently run | Medium | main loop runs `swift build && swift test` outside the sandbox and records the result |
| M3 file I/O bypass not named in docs | Medium | one-line doc fix in phase 07 |
| L1 C1/bidi not escaped on stderr | Low | fix in phase 02 (optional) |
| L2 shortcut continues after timeout | Low | doc line in phase 07 |
| L3 nil bundle id allowed | Low | fix in phase 03 (optional) |
| L4 include read before size cap; no billion-laughs test | Low | fix in phase 03 (optional) |
| L5 uncapped `max_tree_nodes` | Low | accept (documented residual) |
| L6 realpath/open TOCTOU | Low | accept |
| L7 `open_url` main-thread completion | Low | verify live in phase 10 |

## Unresolved questions

1. Does the main loop accept M1 as friction-only (decision 8), or add the ids now?
2. Is R9 (`¬` followed by a comment) valid AppleScript? It needs a phase-10 `osacompile` run outside the sandbox.
3. L7: does `NSWorkspace.open(... completionHandler:)` complete off-main when the caller blocks the main thread?
   Needs a live check.

## Post-rebase delta review (2026-09-30)

Scope: `feat/fast-macos-channels` rebased onto main 1b14cb8 (355725d..c6cde60), plus the post-rebase commits fd4dc25,
e44ee06, e9e3452 and 5d6fac8 (HEAD 5d6fac8, clean tree). I compared the rebased commits with
`backup/fast-macos-channels-pre-rebase` using `git range-diff`. The only hand-resolved hunks in Sources are
`ToolDefinitions.swift` and `ComputerUseToolDispatcher.swift`, where `find_elements` and `perform_actions` now sit
side by side. The rest of the range-diff is test and smoke count bumps (10 to 11, 11 to 12, 16), so it has no
security surface. I edited no product files.

Evidence I ran myself: with the sandbox off, a filtered `swift test` (ElementSearch, LocalChannelGuidance,
DecisionAdvisor, ServerInstructionsGuidance, LocalChannelToolHandlers, ConfinedChildProcessRunner, MacSessionGuard)
gives **Executed 87 tests, with 0 failures**. It includes `testInstructionsFitTheBudgetInEveryHostConfiguration`,
`testSearchSourceReadsEachNodeInOneRoundTrip` and `testMergeRequiresMatchingStageState`. I did not repeat the full
751-test run; `impl-notes.md` records it at 5d6fac8.

### Checks

1. **Threat rows still hold. Only line numbers moved.**
   - **T2.** `find_elements` is the only new dispatcher case. The local tools still fall through to
     `default: throw unsupportedTool` (`ComputerUseToolDispatcher.swift:152-153`). `ToolDefinitions.swift` contains
     no local tool name. `perform_actions` steps are gated by `ActionStep.allowedToolNames` (`:539`), so a batch cannot
     reach `run_script` or `find_elements`; fd4dc25 adds a test for this. The scripting flag is still stripped in
     `MacSessionGuard.sanitizePeerEnvironment`, and the agent re-applies the strip at `MacOSAppAgentProxy.swift:405,450-452`.
   - **T4.** The spawn still sets `POSIX_SPAWN_CLOEXEC_DEFAULT` and dup2's descriptors 0-2 only
     (`ConfinedChildProcessRunner.swift:266-272`). The relay socket still gets `FD_CLOEXEC`
     (`MacOSAppAgentProxy.swift:555-556`).
   - **T14.** The allocator is unchanged (`ElementSearchSnapshotMerge.swift:14-41`). The merge gate is stricter than
     before: it now also requires `cached.isOffStage == window.isOffStage` (`:63`). The merged snapshot keeps the
     cached `isOffStage` (`:93`), and a hits-only snapshot carries the search's own off-stage flag (`:114`), so every
     `rejectCoordinateInputWhenOffStage` site (`ComputerUseService.swift:956,1118,2434,2457,2485,2536`) still sees
     the true stage state.
   - **T18.** Rows are escaped at `ElementSearchSnapshotMerge.swift:163-175`, and the header's app and title at
     `ComputerUseService.swift:2676-2677`. `escapeElementSearchText` is unchanged.
2. **Single writer holds.** The only `snapshotsByApp[...] =` is at `ComputerUseService.swift:1536`, inside
   `storeSnapshot`. Both `refreshSnapshot` and `findElements` (`:2673`) go through it. The remaining uses (`:1240`,
   `:1464`, `:2632`) are reads, and there is no `removeValue`, `removeAll` or other mutation of the cache.
   `snapshotCacheKeys` produces the same key set the old inline loop used (query, name and bundle id, lowercased,
   empties dropped). The only rebased path that rebuilds an `AppSnapshot` is Track A's `liveGeometrySnapshot`
   (`:1360-1385`). It is a local, per-step copy that carries `isOffStage` and `windowContentIsEmpty` through and is
   never cached.
3. **Window resolution and merge (fd4dc25) mostly match the snapshot path.**
   - **Off-stage windows.** An off-stage window resolves through the same `liveOffStageWindow` to the same id, layer 0
     and AX frame as `WindowCapture.offStage` (`ElementSearchAccessibilitySource.swift:171-181` vs
     `AccessibilitySnapshot.swift:667-676`).
   - **On-stage windows.** These use the same `preferredWindowCaptureCandidate` with the AX root's
     `accessibilityWindowID` and a lazily read non-modal set. `elementSearchNonModalWindowIDs` reads `AXModal` through
     the prefetch, and that is equivalent to the snapshot path's `boolValue`.
   - **`windowContentIsEmpty`.** A merge copies the cached value. A hits-only snapshot sets false, which is never
     rendered: `shouldAttachScreenshot` at `ComputerUseService.swift:2586` reads fresh snapshots only.
   - **One AX call per node.** `elementSearchCopyBatchedValues` now delegates to `AXAttributePrefetch.fetch`, which
     makes one `copyMultipleAttributeValues` call. It also drops `kCFNull`, which the old copy did not. That is a
     harmless improvement.
   - **Not matched: the root window choice.** See R-L1.
4. **Option A (5d6fac8).**
   - **Instructions are the same for every host.** `computerUseServerInstructions(environment:)` now ignores the
     environment and returns the base text.
   - **The relay swap still works.** It is an exact `contains`/`replacingOccurrences` on
     `appleScriptAvoidanceInstructionLine` (`LocalChannelRouter.swift:127-130`). The base text interpolates that
     constant on its own line (`MCPServer.swift:16`), so the match cannot drift. The swapped-in text is ASCII-only, so
     `String.count` equals the byte count.
   - **The budget test covers all four host configurations.** It drives the real `LocalChannelRouter` and
     `StdioMCPServer` and asserts ≤1900 characters in each, with the cascade guide absent and the script guide present
     exactly when scripting is on. It passed.
   - **The cascade guide is complete.** It is the original five-line text, byte-identical to the pre-e9e3452 version,
     so no advisor rule is lost. It is embedded in `decideNextAction.description` (`ToolDefinitions.swift:226-231`),
     which is listed only when the endpoint resolves (`:241-248`), and a test caps the description at 2048 characters.
     `resultNote` still restates the core rule on every result. `decision-model.md` mirrors all five lines.
   - **The trimmed base text lost no rule.** e9e3452 cut the base text (Track A's). Only rationale and an intro
     sentence were dropped. "Every element_index refers to the state you last received" still lives in
     `perform_actions`' description (`ToolDefinitions.swift:190`).
5. **The private copies have not drifted.**
   - **Window list.** `elementSearchWindowCandidate`'s enumeration (`ElementSearchAccessibilitySource.swift:212-233`)
     is field-for-field the same as `WindowCapture.resolve` (`AccessibilitySnapshot.swift:686-712`): owner pid,
     number, layer, bounds, name, area, front-to-back offset and on-screen flag, with the same `[]` /
     `kCGNullWindowID` query.
   - **Frame text.** `elementSearchRenderedFrame` (`ElementSearchSnapshotMerge.swift:150-152`) prints the same format
     as `CGRect.renderedLocalFrame` (`AccessibilitySnapshot.swift:2579-2583`).
   - **Remaining risk.** The copies can drift in future edits (R-L2).

### Findings

**Critical: none. High: none. Medium: none.**

- **R-L1 (Low, correctness only).** The root window choice does not match the snapshot path.
  - **Where.** `resolveElementSearchWindow` takes the raw `kAXFocusedWindow`, else the first `AXWindow`
    (`ElementSearchAccessibilitySource.swift:146-162`). `SnapshotBuilder` uses `preferredFocusedWindow`
    (`AccessibilitySnapshot.swift:566-589`). That function prefers the system-wide focused window when the app is
    frontmost, and it rejects a focused window that is minimized or not an `AXWindow` (`usableWindowElement`).
  - **Failure.** Suppose the app's focused window is minimized, or the frontmost app's system-wide focused window
    differs from the app-level one. The search then walks a different window from the one `get_app_state` did.
  - **Why it is only Low.** The merge gate (window id + bounds + stage) prevents a mis-merge. The result is a hits-only
    snapshot that replaces the cached full one, so the agent's earlier `get_app_state` indices then fail with "not in
    the state you last received" and it has to call `get_app_state` again. It fails safe, with no wrong-target
    action, but fd4dc25's message overclaims "the same rules".
  - **Fix.** Make `preferredFocusedWindow` / `usableWindowElement` internal and call them. At minimum, apply the
    role + not-minimized check to the focused window.
- **R-L2 (Low, maintainability).** The window-list enumeration (about 25 lines) and the frame formatter are
  duplicated from Track A's private code.
  - **Why it is only Low.** They match today (check 5).
  - **Risk.** A future change to A's candidate filter, for example a new `kCGWindow*` field or a different query
    option, would silently change which window a snapshot picks but not which window `find_elements` picks.
    Merges would then stop happening. That fails safe because of the merge gate.
  - **Fix (follow-up PR).** Extract `windowCaptureCandidates(pid:)` as an internal free function in
    `AccessibilitySnapshot.swift`, and make `renderedLocalFrame` internal.
- **Info.** A hits-only `find_elements` snapshot now satisfies `perform_actions`' "state received" gate
  (`ComputerUseService.swift:1240`). The rebase created this interaction.
  - **Why it is acceptable.** The indices were returned to the agent, off-stage x/y stays refused, the batch re-reads
    geometry live per step, and fd4dc25 tests it.
  - **Action.** None.

### Verdict

**PASS: no open Critical or High.** Post-rebase counts: 0 Critical, 0 High, 0 Medium, 2 Low, 1 Info. T2, T4, T14 and
T18 still hold, and T14 is tightened by the stage-state rule. There is one cache writer. Option A keeps every
advisor rule and stays within 1900 characters in all four host configurations. The earlier M1-M3 and L1-L7
dispositions are unaffected by this delta.
