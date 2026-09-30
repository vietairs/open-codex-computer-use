---
title: "Track B: fast non-screenshot channels (PR B)"
description: "Relay-local run_script / sdef / open_url / Shortcuts behind an opt-in flag, plus an agent-side lean find_elements walker, with script-first guidance."
status: pending
priority: P1
effort: 38.25h
branch: feat/fast-macos-channels
tags: [macos, mcp, security, applescript, accessibility, tdd]
blockedBy: []
blocks: []
created: 2026-09-29
---

# Track B plan: fast non-screenshot channels (PR B)

Design is fixed: P2 plus all 8 advisor amendments (outcome-lock decisions 7-10, 14-16). This plan executes it on base
`afb60fa` in `/Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/fast-macos-channels`, then rebases onto
main after PR A merges. Risk: **high** (new code-execution surface). Handover-ready for a downstream executor under
`--tdd --advice`: every phase carries Signature / Boundaries / Acceptance per task, a `## Contract Rules` block and a
`## Failure Protocol` that stops and escalates to `kongming`. Revised 2026-09-29 after three red-team passes (security,
correctness, integration); see the disposition table at the end. **Approved by the user on 2026-09-29 with the plan-gate
counsel's six amendments**, folded in below (see "Plan-gate counsel amendments" and "User decisions").

- Threat model and test map (T1-T25): [threat-model.md](threat-model.md)
- Inputs: `../outcome-lock.md`, `../parallel-tracks.md`, `../reports/track-b/brainstorm-fast-channels.md`,
  `../reports/track-b/counsel-brainstorm-fast-channels.md`, `../reports/track-b/predict-fast-channels.md`,
  `../reports/track-b/redteam-{security,correctness,integration}.md`, `../reports/track-b/counsel-plan-fast-channels.md`

## Data flow

```
host stdin line --> LocalChannelRouter.route (relay, or direct server process)
   flag off ............................. forward(line) unchanged --> agent socket / StdioMCPServer.handle
   flag on, tools/call <local tool> ...... LocalChannelToolHandlers.call (never forwarded; local errors -> JSON-RPC error)
        run_script / open_url / run_shortcut:
          read payload -> ScriptAuditLog(request, full text; failure refuses) -> guard.requireUnlocked -> args
          -> ScriptPolicyFilter (NFKC + Unicode whitespace + comment-stripped views) -> ConfinedChildProcessRunner
             (/usr/bin/osascript | /usr/bin/shortcuts, fds 0-2, cwd /, scrubbed env, one deadline over reap + drain,
              group SIGKILL) or NSWorkspace.open(url, withApplicationAt: checked handler) (UrlOpenPolicy)
          -> ScriptAuditLog(result: ok | error | timeout | rejected:<reason>) -> JSON-RPC result
        get_scripting_dictionary / list_shortcuts: guard -> ScriptingDictionaryLookup (static .sdef only, bounded
          XInclude) / shortcuts list
   flag on, initialize / tools/list ...... forward, then patch: swap AppleScript line for script-first guide / append 5
                                           tools; error or shape-mismatched responses pass through untouched
agent: tools/call find_elements --> ComputerUseToolDispatcher --> ComputerUseService.findElements (fixture app refused)
        -> ElementSearchWalker (one AXUIElementCopyMultipleAttributeValues per node, early stop)
        -> ElementSearchIndexAllocator (>= 1_000_000 + per-process seed, monotonic)
        -> merge into cached snapshot iff same targetWindowID AND windowBounds (accessibility mode), else hits-only
           snapshot carrying AXFocusedUIElement -> rows with escaped AX text
```

## Phases

| # | Phase | Owner | Depends on | Parallel group | Effort |
|---|---|---|---|---|---|
| 00 | [Pre-cook: time a warm Mail `whose` search](phase-00-pre-cook-mail-whose-timing.md) | main loop | none | before cook | 0.25h |
| 01 | [Script policy filter + confined child runner + osascript runner](phase-01-script-filter-and-confined-runner.md) | tester, implementer | 00 | G1 | 5h |
| 02 | [Script audit log](phase-02-script-audit-log.md) | tester, implementer | 00 | G1 | 3h |
| 05 | [find_elements lean walker + cache merge](phase-05-find-elements-lean-walker.md) (**first in G1**) | tester, implementer | 00 | G1 | 7.25h |
| 05p | [Early live ratio probe](phase-10-live-measurement-main-loop.md#early-probe-before-the-rebase-right-after-phase-05-is-green) (pre-rebase build, target ~0.35) | main loop (user runs harness) | 05 | after 05, before G2 | 0.5h |
| 03 | [sdef lookup + URL/Shortcuts launcher](phase-03-sdef-lookup-and-launcher.md) | tester, implementer | 01 | G2 | 5h |
| 04 | [Local channel router + handlers + sanitizer strip](phase-04-local-channel-router-and-sanitizer.md) | tester, implementer | 01, 02, 03 | G3 | 5h |
| 06 | [Relay and direct-mode wiring + smoke suite](phase-06-relay-and-direct-wiring.md) | tester, implementer | 04, 05 | G4 | 1.75h |
| 07 | [Guidance and docs](phase-07-guidance-and-docs.md) | tester, implementer | 04, 05 | G4 | 3h |
| 08 | [Security review + red-team](phase-08-security-review-and-red-team.md) | reviewer (not an implementer) | 06, 07 | - | 2.5h |
| 09 | [Rebase onto main after PR A](phase-09-rebase-onto-pr-a.md) | implementer + reviewer | 08, PR A merged | - | 2.5h |
| 10 | [Live measurement and live security checks](phase-10-live-measurement-main-loop.md) | main loop only | 09, decision-16 settings edit, host re-registration | - | 2.5h |

Parallel groups: phases inside one group touch disjoint files (table below). **Execution mode:** a red test file that
references a type not yet written breaks compilation of the whole `OpenComputerUseKitTests` target, and a runtime-red
test (phase 07's `testBaseInstructionsNameFindElements`) fails every full `swift test` run, so two phases cannot sit in
ANY red state (compile-red or runtime-red) in the same worktree at once. Either run a group's phases one red-green
cycle at a time in the single worktree (default; in G4, finish phase 06 green before phase 07 writes its red test, or
the reverse), or the main loop gives each parallel phase its own sibling worktree branched from
`feat/fast-macos-channels` and merges them back (conflict-free by construction). **Order:** phase 00, then phase 05
first in G1, then the early probe (05p), then phases 01 and 02, then G2 through G4, phase 08, the rebase (09) and
phase 10. The ratio is therefore first measured after about 8h of work, not after about 35h.

## File ownership (base afb60fa; K = `packages/OpenComputerUseKit/Sources/OpenComputerUseKit`, T = `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests`)

| Phase | Files (create or edit) | Also edited by Track A? |
|---|---|---|
| 01 | new K/`ScriptPolicyFilter.swift`, K/`ConfinedChildProcessRunner.swift`, K/`OsascriptChildRunner.swift`; new T/`ScriptPolicyFilterTests.swift`, T/`ConfinedChildProcessRunnerTests.swift` | no |
| 02 | new K/`ScriptAuditLog.swift`; new T/`ScriptAuditLogTests.swift` | no |
| 03 | new K/`ScriptingDictionaryLookup.swift`, K/`ShortcutAndUrlLauncher.swift`; new T/`ScriptingDictionaryLookupTests.swift`, T/`ShortcutAndUrlLauncherTests.swift` | no |
| 04 | new K/`LocalChannelRouter.swift`, K/`LocalChannelToolHandlers.swift`, K/`LocalChannelGuidance.swift`; edit K/`MacSessionGuard.swift` (`MacSessionLockPolicy.sanitizePeerEnvironment`, :64-68); new T/`LocalChannelRouterTests.swift` | no |
| 05 | new K/`ElementSearchWalker.swift`, K/`ElementSearchAccessibilitySource.swift`, K/`ElementSearchSnapshotMerge.swift`; append-only K/`ComputerUseService.swift` (EOF extension), K/`ToolDefinitions.swift` (`all` array end, before `]` at :156), K/`ComputerUseToolDispatcher.swift` (`callTool` switch, before :128); count sites T/`OpenComputerUseKitTests.swift` :256, :2964-2966, T/`DecisionAdvisorTests.swift` :436-437, :448, :455-457; new T/`ElementSearchTests.swift` | **yes**: ComputerUseService, ToolDefinitions, Dispatcher, both count-test files |
| 06 | `apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift` (:121-137, :553), `.../OpenComputerUseMain.swift` (:49), `.../MCPAppRuntime.swift` (:96), `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift` (:199-200, `smokeServerEnvironment` :347-352, one new function) | smoke suite count line: yes (not on the parallel-tracks shared list; main loop to add) |
| 07 | K/`MCPServer.swift` (:10, :16, append after :17); `skills/open-computer-use/SKILL.md`, `skills/open-computer-use/references/usage.md`, new `skills/open-computer-use/references/scripting.md`; `docs/ARCHITECTURE.md` (:3, :12, :42, :65, :68, :69 + one paragraph), `docs/SECURITY.md` (append), `README.md` (Trust boundary paragraph :50 only), new `docs/exec-plans/active/20260929-fast-macos-channels.md`, new `docs/histories/2026-09/<timestamp>-fast-macos-channels.md`; new T/`LocalChannelGuidanceTests.swift` | **yes**: MCPServer.swift :10, SKILL.md, usage.md, ARCHITECTURE.md (README.md is read-only for Track A) |
| 08 | none in the worktree; report to `reports/track-b/` | no |
| 09 | conflict resolution in every "yes" row above; count sites move to 11; K/`ComputerUseService.swift` gains `storeSnapshot` (single `snapshotsByApp` writer); K/`LocalChannelGuidance.swift` + T/`LocalChannelGuidanceTests.swift` name `perform_actions` | yes (by definition) |
| 10 | none in the worktree; `~/.claude/settings.json` by the main loop only; the `open-computer-use` MCP registration (`claude mcp remove/add`) by the user in Terminal.app, restored afterwards | no |

Shared-file notes: besides the files marked "yes" above, `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
(tool count at :199-200, `smokeServerEnvironment` :347-352) is edited by both tracks and resolves in phase 09 (final
11 flag unset, 16 flag set); it is not yet on the parallel-tracks shared-file list, which the main loop owns.

No file appears in two phases of the same parallel group. `AccessibilitySnapshot.swift` and `OpenComputerUseCLI.swift`
are NOT edited (the walker reads the window only, so `shouldSkipChild` is not needed; amendment 3 drops the CLI change;
`renderedLocalFrame` is private there, so phase 05 keeps a pinned private copy). No entitlements or Info.plist change.
`list_shortcuts` is the only tool beyond decision 7's four channels; it is read-only, flag-gated and supports
`run_shortcut` discovery.

## Tool counts expected

| Assertion | afb60fa (this branch) | after rebase on PR A |
|---|---|---|
| `ToolDefinitions.all.count` | 10 (+ find_elements) | 11 (+ perform_actions, which stays last) |
| `listed` with loopback advisor | 11 | 12 |
| `listed` with non-loopback URL | 10 | 11 |
| router `tools/list` with scripting flag | agent list + 5 | agent list + 5 |
| smoke suite `tools.count` (flag unset) | 10 | 11 |

All counts assume `OPEN_COMPUTER_USE_DECISION_MODEL_URL` and `OPEN_COMPUTER_USE_DECISION_MODEL_BACKEND` are unset; the
smoke suite (`smokeServerEnvironment`, phase 06) and the phase 10 harness (`DROP`) strip both, plus the scripting flag.

## Acceptance criteria (PR B done means all of these)

1. `cd <worktree> && swift build && swift test` exits 0, before and after the rebase.
2. Flag unset: router output is byte-identical to the forwarded response for every method, `initialize` still contains
   the exact AppleScript line, and none of the 5 local tools is listed (unit tests, phase 04; live relay-vs-direct
   equivalence and smoke, phase 10 steps 3-4).
3. Flag set: the shell-verb filter rejects every denied form in its table, including Unicode-whitespace, fullwidth,
   comment and spaced-chevron spellings (unit test, phase 01; compiler probe, phase 10 step 6).
4. Script execution never crosses the app-agent socket: agent dispatcher and `call run_script` fail closed with an
   unlocked guard; `MacSessionLockPolicy.sanitizePeerEnvironment` drops the flag; router never forwards a local tool;
   child sees only fds 0-2 (phases 01, 04).
5. Every `run_script`, `open_url` and `run_shortcut` call that carries a payload writes a `request` entry before any
   rejection, including filter and lock rejections, and a failing audit refuses the call (phase 04).
6. sdef XInclude outside the bundle or `/System/Library/ScriptingDefinitions` is skipped; no external entity loads;
   include count, expanded size and xpointer shape are bounded; no in-process OSA call (phase 03).
7. Audit log file is 0600, opened with O_NOFOLLOW, a pre-placed symlink is refused, concurrent rotation keeps the
   previous generation, stderr carries no script text and no raw control characters (phase 02).
8. `find_elements` rows cannot be forged by injected AX text; hits-only snapshots carry focus; merges require matching
   window id and bounds (phase 05).
9. Live, from the main loop on the rebased build: Mail search via `run_script` median of 5 warm runs <= 1.0s;
   `find_elements` for one Mail toolbar button with `max_results: 1` median <= 50% of `get_app_state` median on the
   same Mail window (phase 10; early pre-rebase probe targets ~0.35); relay `open_url https://example.com` returns
   `Opened ...` in under 2s and `list_shortcuts` returns without error (phase 10 step 2a).
10. Security review (phase 08) closes with zero open Critical/High findings across T1-T25.

## Rollback

Each phase is its own commit on `feat/fast-macos-channels`; revert that commit. Phases 01-03 and 05 add new files, so
reverting them cannot break existing behaviour. Phase 04's only edit to existing code is one filter clause in
`MacSessionGuard.swift`. Phase 06 is the only phase that changes the live relay loop; reverting it restores
`proxyMCP` byte-for-byte. Phase 09 is protected by the `backup/fast-macos-channels-pre-rebase` branch; its
`storeSnapshot` extraction is the only change inside Track A's `refreshSnapshot` and reverts with the rebase. If PR B
must be pulled after merge, revert the merge commit: with the flag unset the surface is already inert, so a revert is
only needed for `find_elements`.

## Not done here (owned elsewhere)

- `~/.claude/settings.json` narrowing (decision 16): main loop, before phase 10.
- `pipeline*.md`, `outcome-lock.md`, `parallel-tracks.md` updates, PR creation, ship gate: main loop. One open request
  to the main loop: add `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift` to the
  parallel-tracks shared-file list (see "Shared-file notes").
- Plan-stage counsel: done (`../reports/track-b/counsel-plan-fast-channels.md`); its six amendments are folded in.

## Follow-ups (out of PR B scope)

- Pre-existing peer-environment denylist: `MacSessionLockPolicy.sanitizePeerEnvironment` is a denylist and the agent
  `setenv`s peer keys process-wide, so DEBUG-only keys (`OPEN_COMPUTER_USE_LOCK_FAIL_OPEN`,
  `ALLOW_GLOBAL_POINTER_FALLBACKS`) can be forged per call (`K/MacSessionGuard.swift:64-68`,
  `A/MacOSAppAgentProxy.swift:416`, `:507-538`). Likely fix direction: an allowlist of peer keys. Owned by the main
  loop as a separate change; PR B only adds the scripting flag to the existing strip list.

## User decisions (2026-09-29, fixed)

1. `storeSnapshot` owner: Track B extracts the single `snapshotsByApp` writer at the rebase (phase 09 step 5); Track A
   does not land it.
2. Guide wording: the plan's reading of decisions 9 and 12 is confirmed, and the guide adds that the turn-start
   `get_app_state` applies to UI work, so a turn that only uses `run_script` skips it, and names `find_elements` for
   "after a script changed the UI" (phase 04 step 1, phase 07 test and SKILL.md).
3. Relay death orphans the osascript child (T24): accepted documented residual; no signal forwarding.
4. `get_scripting_dictionary` reads static `.sdef` only: accepted; `aete`-only apps get `noScriptingDefinition`.
5. Script log retention: 10 MB cap plus one rotated file (`scripts.log.1`).
6. Phase 10 host setup: the Dev.app build temporarily replaces the npm `open-computer-use` registration (same server
   name, scripting flag and socket namespace set); the user runs the harness and the re-registration in Terminal.app,
   and the npm registration is restored afterwards.

## Plan-gate counsel amendments (all accepted)

| # | Amendment | Where folded in |
|---|---|---|
| 1 | Off-window `find_elements` hits | Phase 05 step 6 `elementSearchClickableLocalFrame` (nil `localFrame` when the midpoint is outside the window, so `click` fails with `no clickable frame`), `testOffWindowHitHasNoClickableFrame`; threat T25 |
| 2 | Live `open_url` and `list_shortcuts` | Phase 10 harness `measure` mode + step 2a (main-thread semaphore wait in the relay) |
| 3 | Host setup for live review and host checks | Phase 10 pre-requisite 6 (same server name, flag + namespace, session restart, restore), steps 7, 9, Rollback |
| 4 | Strip `OPEN_COMPUTER_USE_DECISION_MODEL_BACKEND` | Phase 06 step 0 (`smokeServerEnvironment`), phase 10 harness `DROP` |
| 5 | Measure the ratio early | Phase 05 first in G1; phase 10 "Early probe" (`probe` mode, target ~0.35); lever if missed = breadth-first walk (phase 05 step 3), never `max_nodes` |
| 6 | Timing tests on CI | Phase 01 timing-bounds rule and widened upper bounds; phase 03 `< 10s`; phase 04 `testFirstContactFloorAppliesOnce` uses `delay 30`, 2.5-10s and a relative second-call check |

## Unresolved questions

1. Which app name appears in the Automation prompt for Claude.app / Codex.app hosts, and do they prompt at all
   (possible silent -1743)? Live check, phase 10 step 9.
2. Does killing `/usr/bin/shortcuts run` stop the shortcut, and does "Allow Running Scripts" gate "Run Shell Script"?
   Live check, phase 10 step 9; docs wording depends on it.
3. Does AppKit deliver the `NSWorkspace.open(_:withApplicationAt:configuration:completionHandler:)` completion off the
   main queue? Unverified; phase 10 step 2a settles it live.
4. Where does Mail's "Get Mail" button fall in walk order relative to the message-list split group? It sets
   `nodes_visited`; the early probe answers it.
5. PR A's final API for window resolution without capture, batched AX reads and `renderedLocalFrame` visibility decides
   the phase 09 dedupe; if PR A exposes none, the Track B private copies stay.
6. `waitid(..., WNOWAIT)` on Darwin is [UNVERIFIED]; phase 01 specifies the fallback (reap directly, rely on the drain
   deadline) so the tests still hold.

## Red-team disposition

Sources: S = `reports/track-b/redteam-security.md`, C = `redteam-correctness.md`, I = `redteam-integration.md`.
Duplicates across reports share one row.

| Finding | Severity | Disposition | Where fixed / why |
|---|---|---|---|
| S-H1 = C-H1: filter-rejected scripts never logged; test pinned the gap | High | Accepted | Phase 04 step 4 (audit request before guard, validation and filter; `rejected:<reason>` results); `testFilterRejectionIsLoggedAndNeverSpawns`; threat T17; acceptance 5 |
| S-H2: `find_elements` rows forgeable by injected AX text | High | Accepted | Phase 05 step 9 (`escapeElementSearchText`: `sanitizeText` + CR, U+2028/2029, `"`, 500-char cap); `testRowEscapesInjectedNewlines`; T18 |
| C-H2: no test for open_url / run_shortcut audit-then-refuse | High | Accepted | Phase 04 `testOpenUrlAndShortcutAreAuditedAndRefusedWhenLogUnsafe` |
| C-H3 = I-M2: relay never exercised; only one direct path smoked; smoke env inherits the flag | High | Accepted | Phase 10 step 4 relay-vs-direct `equivalence` harness mode; phase 06 step 0 (strip flag in `smokeServerEnvironment`), step 3 (visual-cursor-off run for `OpenComputerUseMain.swift:49`); phase 06 coverage wording corrected |
| C-H4: frozen `effectiveTimeout` signature contradicts the injectable floor | High | Accepted | Phase 01 signature gains `firstContactFloor:`; table rows added; phase 04 step 4.6 passes it |
| I-H1: phase 09 put `find_elements` after `perform_actions`, breaking Track A's `last` test | High | Accepted | Phase 09 table: `find_elements` goes before `perform_actions`; Verify 2b |
| I-H2: `find_elements` is a second `snapshotsByApp` writer; phase 09 misstated it | High | Accepted | Phase 05 step 10 (`snapshotCacheKeys` helper, writer acknowledged); phase 09 table + step 5 (`storeSnapshot`), Verify 2a; `testSnapshotCacheKeysMatchRefreshRule`; owner decided: B extracts at the rebase (user decision 1) |
| S-M1: open_url denylist gaps + handler TOCTOU | Medium | Accepted | Phase 03 launcher steps 1-2, extended `blockedSchemes` / handler ids (verified ids on this Mac, rest tagged), `opener(url, handler)` via `NSWorkspace.open(_:withApplicationAt:)`; T12, T19; phase 10 step 10 |
| S-M2: sdef include bomb, hostile XPath, FIFO | Medium | Accepted | Phase 03 steps 2-3 (16 includes/doc, 8 MB expanded cap, xpointer allowlist of the 3 shipped shapes, `O_NOFOLLOW|O_NONBLOCK` + `fstat`), 4 tests, grep gate; T20 |
| S-M3 = C-M9: extension-less `OSAScriptingDefinition`; in-process OSA fallback may send Apple Events or launch | Medium | Accepted | Phase 03 step 1 (append `.sdef`, static Resources scan), step 5 (OSA fallback removed); tests; T21; phase 10 step 8. Coverage trade-off accepted (user decision 4) |
| S-M4 = C-L6: concurrent rotation destroys the previous generation | Medium | Accepted | Phase 02 step 1 (dev/ino re-check after `flock`); `testConcurrentRotationKeepsPreviousGeneration`; T22 |
| S-M5 = C-M4(b): drain unbounded by a lingering descendant; no chdir | Medium | Accepted | Phase 01 step 3 (one deadline, post-exit group kill, `poll` drain with grace, `addchdir_np("/")`); 3 tests; T23 |
| C-M4(a): two threads may reap the child | Medium | Accepted | Phase 01 step 3 (single reaper, `waitid` WNOWAIT; fallback specified) |
| C-M4(c): byte cap can split UTF-8 and nil the decode | Medium | Accepted | Phase 01 step 5 `decodeOutput` = `String(decoding:as:)`; `testDecodeOutputSurvivesSplitMultibyteCharacter` |
| S-M6: filter not anchored to the parser; T8 unproven | Medium | Accepted | Phase 01 steps 1-2 (NFKC, Unicode whitespace, spaced chevrons, comment-stripped view) + new table rows; phase 10 step 6 `osacompile` probe (moved to the main loop because the sandbox cannot load Standard Additions) and step 7 classifier observation; phase 07 docs name hosts without a classifier |
| C-M1: `renderedLocalFrame` is private; phase 05 relied on it | Medium | Accepted | Phase 05 private copy `elementSearchRenderedFrame`, pinned by a literal in `testRowFormat`; phase 09 dedupe list |
| C-M2 = I-M1: hits-only snapshot drops focus, `type_text` steals the foreground | Medium | Accepted | Phase 05 steps 5 and 8 (read `AXFocusedUIElement`, carry it); `testHitsOnlySnapshotCarriesFocus` |
| C-M3: merge checks window id but not bounds | Medium | Accepted | Phase 05 step 8 `canMergeElementSearchHits` (id AND bounds AND accessibility mode); moved-bounds test case |
| C-M5: relay death orphans the script child | Medium | Accepted as residual (not fixed) | Needs process-wide signal handlers, which Boundaries forbid, or giving up the group kill. Documented in phase 01 header, threat T24, `scripting.md` (phase 07); accepted by the user (decision 3) |
| C-M6: router test runs the real `/usr/bin/shortcuts` | Medium | Accepted | Phase 04 `testLocalToolsAreNeverForwarded` injects marker launcher and recording opener |
| C-M7: router error handling underspecified | Medium | Accepted | Phase 04 step 5 error-handling bullet; `testForwardedErrorResponsesPassThroughUntouched`, `testMalformedLocalCallBecomesToolError`, `testLocalCallWithoutIdProducesNoOutput` |
| C-M8: harness never exercises early stop | Medium | Accepted | Phase 10 harness `max_results: 1`, `nodes_visited` parsed and recorded |
| I-M3: guide omits the batch tool; tension with MCPServer :8 | Medium | Accepted | Phase 04 guide scoped to "after the turn-start get_app_state"; phase 09 step 6 names `perform_actions` + test; phase 07 `testScriptFirstGuideKeepsTurnStartStateForUIWork`; wording confirmed (user decision 2) |
| I-M4: phase 10 harness can evict the main loop's live agent | Medium | Accepted | Phase 10 prerequisite 5 + harness `OPEN_COMPUTER_USE_AGENT_SOCKET_NAMESPACE`; step 11 stops only the namespaced agent |
| I-M5: docs missed (ARCHITECTURE :12/:42/:69, README trust boundary, exec-plan entry) | Medium | Accepted | Phase 07 steps 7, 9, 10; Verify 6-7 |
| I-M6: identical hunks auto-merge to stale counts; smoke file not on shared list | Medium | Accepted | Phase 09 Verify 2 greps (`listed.count`, `Stays*` names, `guiTools.count`); smoke-file list change requested from main loop |
| S-L1: `metadataLine` prints `app=` unescaped | Low | Accepted | Phase 02 step 2 escaping + cap; `testMetadataLineEscapesControlCharacters` |
| S-L2 = C-L5: `target_app` / first-contact floor are advisory | Low | Accepted (docs) | Phase 02 step 5, phase 07 `scripting.md`, threat-model residuals |
| S-L3: allocator resets on agent restart | Low | Accepted | Phase 05 step 7 per-process seed + `init(initialNext:)`; "never reused" narrowed to one process |
| S-L4: `display dialog ... hidden answer` phishing | Low | Accepted (docs) | Phase 07 `scripting.md`, threat-model residuals |
| S-L5: peer-env denylist lets DEBUG keys be forged (pre-existing) | Low | Rejected for PR B | Outside PR B scope; listed under "Follow-ups" |
| C-L1 = I-L1: wrong owner type for `sanitizePeerEnvironment` | Low | Accepted | Phase 04 facts, step 8, Signature, test name; threat T2 |
| C-L2: guide test assertion was vacuous | Low | Accepted | Phase 04 `testInitializeSwapsAppleScriptLineForGuide` asserts the full guide text |
| C-L3: no unit test for case-variant tool names | Low | Accepted | Phase 04 `testCaseVariantToolNameIsForwarded` |
| C-L4: harness inherits `DECISION_MODEL_URL` | Low | Accepted | Phase 10 harness drops it (and the scripting / proxy keys) |
| C-L7: 1M base safe only below 1M-node trees | Low | Accepted (docs) | Phase 05 header residual note |
| C-L8: single-worktree red rule ignored runtime-red tests | Low | Accepted | plan.md Execution mode |
| C-L9: compact-view test counted as coverage | Low | Accepted | Phase 05 test note: pins behaviour, not coverage |
| I-L2: measurement target drifted from "one button" | Low | Accepted | Phase 10 harness targets `AXButton` "Get Mail"; acceptance 9 |
| I-L3: fixture app breaks on hits-only snapshots | Low | Accepted | Phase 05 step 10 refuses the fixture app; merge requires accessibility mode |
| I-L4: counsel amendment 5 "reuse Track A helper" silently skipped | Low | Accepted | Phase 02 step 6 records N/A (reader vs appender) for the PR body |
