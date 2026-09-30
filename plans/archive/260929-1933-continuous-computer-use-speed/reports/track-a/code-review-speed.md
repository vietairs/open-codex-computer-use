# Code review: Track A (PR A, continuous computer-use speed)

VERDICT: PASS (0 Critical, 0 High open; 4 Medium, 8 Low)

Worktree `.claude/worktrees/continuous-computer-use-speed`, branch `feat/continuous-computer-use-speed`, diff `afb60fa..242fbf3` (7 commits, 26 files, +2880/-217). Read-only review. No build, test, app launch, or MCP call. swift test green per gate-g addendum (496 tests, 0 failures, x2).

## Scope
- Sources: ComputerUseService, AccessibilitySnapshot, AccessibilityAttributePrefetch (new), BatchActionRunner (new), ComputerUseToolDispatcher, ToolDefinitions, MCPServer, SoftwareCursorOverlay, DecisionJev{Client,Prompt,LetterDiskCache(new)}, DecisionRemoteBackend
- Tests: 7 new classes + count edits; smoke suite step 11
- Docs: ARCHITECTURE.md, SKILL.md, usage.md, histories entry
- Scout: hitTest callers, Go runtime schemas, app-agent lock path (MacOSAppAgentProxy:405-420), render record creation, doc tool-count sites

## Focus-area verdicts
1. Text-only results + hitTest fix: correct. `hitTestElement` callers (`clickCandidates` :1480 via x/y window point :878, nearby loop :1585 via `clickActionPoints`) both pass window points, so `windowPointToGlobalPoint` at :1724 removes the old double scaling; fail-closed throw cannot reach element_index clicks. `screenshotToGlobalPoint` used only by drag. Carried frame keyed by pid, compares windowID + size; resize/new window -> `screenshotFrameMismatchMessage` before any input is posted. One gap in batches (L1) and one heuristic gap (M1).
2. Cursor cap: correct. Only `animateMove` changed; `normalizedElapsed * closeEnoughTime` time-compresses the same spring, so the path still reaches `end`. CursorMotionModel.swift diff empty.
3. Settle: one constant 0.15 at ComputerUseService.swift:294, 7 uses, click-detection literals untouched. No value change. Adequacy inside batches still unverified live (UQ1).
4. AX batch read: correct. Options 0 -> per-slot error sentinels dropped (`AXValueGetType == .axError`) plus kCFNull; whole-call failure or count mismatch -> nil -> single-read fallback (same output, just slower). `covers()` makes prefetch authoritative for requested attrs, so a missing value = failed single read (same semantics). `resolveLocalFrame` `as! AXValue` is pre-existing; nil guards precede it. `isSettable` still live, computed once. Byte-identical render bracket (M4) still pending live.
5. perform_actions: stop-at-first-failure (`BatchActionRunner.run` :129-146), lock checked per step and before the final read, step lines kept on final-read failure/lock (:165-168, isError true), live focus (`typingTargetElement` -> `liveFocusedElement`), live window bounds + target frame (`liveGeometrySnapshot` :1239), pinned snapshot resolves indices only, upfront parse + click-method validation + unknown-index rejection before any step. Tool count 10, `perform_actions` appended last, MCPServer.swift:10 names it, line 16 byte-identical. No per-tool allowlist in the proxy/CLI, so it routes like the other tools.
6. jev disk cache: 0600 (O_CREAT|O_EXCL|O_NOFOLLOW + fchmod), dir 0700 on create and refused if symlink/foreign/group-or-other-writable, key = sha256(base_url|model) and the entry re-checks base_url, model, version, sample-prompt sha; `resolved_at` 7-day TTL + 5-min future skew; atomic temp+rename; every load problem is a silent miss (`try?` around `readOwnerOnlyRegularFile`); Entry has no api-key field. Invalidation removes the disk entry. Production dir only in `buildDecisionProvider`; tests use temp dirs.
7. Guidance: MCPServer instructions, SKILL.md, usage.md agree on start-of-turn get_app_state, no per-action get_app_state, text-only default, batching rule, "indices refer to last received state", Send in its own call. Cross-platform wording gap (M3).

Commit hygiene: clean. No plan IDs/phase numbers/finding codes in added code, comments, test names, or commit messages (grep on `+` lines and `git log` bodies). Conventional subjects, attribution trailers present.

## Critical
None.

## High
None.

## Medium

### M1. Empty-tree screenshot fallback practically never fires for real apps
- `AccessibilitySnapshot.swift:449` (capture) and `ComputerUseService.swift` `snapshotResult` (`treeIsEmpty: snapshot.elements.isEmpty`).
- `renderer.records` includes the window root and, via `renderer.render(menuBar)` (:440-444), every menu-bar item. A real app with a window almost always yields >0 records, so "attach a screenshot when the AX tree is empty" (outcome-lock decision 3) only triggers when the whole walk, menu bar included, produces nothing.
- Failure scenario: canvas/game/Electron window with AX content disabled. Action results come back as window root + menu items, no image. The agent does not know it needs `include_screenshot: true` and acts blind or loops on get_app_state.
- Faithful to phase-01 text (`records.isEmpty`), so this is a spec gap, not an implementer deviation. Mitigation already present: `include_screenshot` + guidance.
- Fix (needs user call, changes behaviour): treat the tree as empty when the window subtree (excluding the menu bar and the window root itself) has no records, e.g. track `windowSubtreeRecordCount` before `render(menuBar)`; unit-test with a window-only + menu-bar fixture shape.

### M2. Batch on a snapshot-cache miss acts on indices the agent never saw
- `ComputerUseService.swift:1154` `let pinned = try currentSnapshot(for: query)`.
- On a cache miss (fresh server process, agent restart, different app key such as bundle id vs name that was never cached), `currentSnapshot` builds a new snapshot. The unknown-index check then validates against that fresh numbering, and the message claims "the state you last received".
- Failure scenario: host reconnects after an app-agent restart and replays element_index values from its last turn. Up to 10 steps run blind against renumbered elements: click the wrong row, then type_text into whatever has focus. Single actions have the same pre-existing behaviour, but a batch amplifies it (N steps, no observation in between).
- Plan unresolved Q3; still open.
- Fix: in `performActions`, if `snapshotsByApp[query.lowercased()] == nil` and any step has an `elementIndex`, throw `invalidArguments("no state for <app> in this session; call get_app_state before perform_actions")`. Steps without indices (press_key/type_text) may still use a fresh snapshot.

### M3. Cross-platform skill text states macOS-only behaviour unconditionally
- `skills/open-computer-use/SKILL.md:30`: "Action results are text-only; pass `include_screenshot: true` ...".
- `skills/open-computer-use/references/usage.md:88`: "add `include_screenshot: true` to any action", in a section whose surrounding text covers macOS, Linux and Windows.
- The Go runtimes still attach images and their schemas declare `additionalProperties: false` (Linux main.go:1240, Windows main.go:811). An agent following the skill on Linux/Windows sends a schema-invalid argument, and a validating host may reject the call.
- Fix: prefix both with "On macOS," (as step 9 and the Batching section already do).

### M4. ARCHITECTURE.md still says 9 tools at three sites
- `docs/ARCHITECTURE.md:12` (smoke runner "calls to the 9 tools"; the smoke suite now asserts 10 and runs `perform_actions`).
- `:65` (dispatcher "for 9 Computer Use tools").
- `:68` (tools/list "converges on the official computer-use's wording ... for the 9 Computer Use tools"; `perform_actions` and `include_screenshot` are local extensions, not official surface).
- Advisor acceptance criterion "all count sites updated" holds for code/tests, but not for these doc lines. Also `docs/QUALITY_SCORE.md:14,18` ("set of 9 tools", "regressions for the 9 tools").
- Fix: update to 10 (macOS) and note that `perform_actions`/`include_screenshot` diverge from the official surface on purpose.

## Low

- L1. Batch x/y click after a mid-batch resize is mis-scaled instead of failing closed. `liveGeometrySnapshot` (ComputerUseService.swift:1275) keeps `pinned.screenshotPNGData` but swaps in live `windowBounds`, and `resolveScreenshotPixelSize` rule 1 (:310) prefers the snapshot image, so the fail-closed check is skipped. Only reachable when the pinned snapshot still carries an image (a batch straight after a full get_app_state) and an earlier step resizes the window. Fix: in the batch path, pass the pinned image's frame (pinned windowID/size) through the same comparison, or drop `screenshotPNGData` from the live snapshot so `lastReturned` governs.
- L2. The compact get_app_state snapshot captures an image it never returns, and rule 1 lets that unreturned image define the scale for later x/y clicks. This is pre-existing and user decision 5 keeps compact capture, but the carried-frame guarantee ("scale by the screenshot you received") is weaker than the docs claim. Fix later: prefer `lastReturned` when the cached snapshot came from the compact style.
- L3. `liveLocalFrame`/`liveAXValue`/`liveFocusedElement` (ComputerUseService.swift:1299-1348) reimplement private helpers in AccessibilitySnapshot.swift (`resolveLocalFrame`, `copyElement`). `liveFocusedElement` also reads only the app element, while the snapshot tries systemWide first when the app is frontmost, so batch focus can differ from single-action focus on frontmost apps. Fix: expose an internal `SnapshotBuilder.liveFocusedElement(pid:)` and `liveLocalFrame` and reuse them.
- L4. `readOwnerOnlyRegularFile` (DecisionRemoteBackend.swift:184) now serves two callers but its ENOENT text still says "no remote-backend config file". The jev cache swallows it (`try?`), so nothing leaks, but future callers get a misleading message. Fix: generic text, or let the caller supply a noun.
- L5. The jev `store` leaves `.tmp-<uuid>` files behind if the process dies between open and rename. They are harmless (0600, never loaded) but accumulate. Fix: sweep `.tmp-*` older than N minutes on `ensureOwnerOnlyDirectory`, or ignore.
- L6. A complete disk entry is trusted with zero `/tokenize` calls for up to 7 days. A tokenizer redeploy under the same model name is caught only by `staleLetterCacheMessages` invalidation or the TTL. This is accepted by decision 6; recording it for risk calibration.
- L7. `docs/SECURITY.md` does not mention the new persisted file under the `decision-model/` trust root (`jev-letters/`, 0600, token ids only, no key). Add one bullet next to the remote-backend.json paragraph (:65).
- L8. The histories entry "Files Modified" lists only the guidance-commit files, not the whole change. It also says per-lever deltas are "in the PR description" while M1-M6 are still pending. Fix: list all touched modules, and make sure the PR body actually carries the M-table.

## Edge cases found by scout
- Shared app agent: `decide_next_action` skips the environment lock (MacOSAppAgentProxy.swift:413) and calls `refreshSnapshot`, which writes the non-thread-safe `snapshotsByApp`. It can run concurrently with any locked call, including a long `perform_actions`. The race is pre-existing (it exists at afb60fa); the batch only lengthens the window. Not introduced here; worth a follow-up (serial queue or lock around the cache dictionaries, including the new `lastReturnedScreenshotFrames`).
- `lastReturnedScreenshotFrames` is shared across hosts on the shared agent. The window-size check limits the impact to a display-scale change between hosts' screenshots, which is negligible.
- In a batch, the x/y click path (`clickCandidates` -> `bestElement(containing:)`) still matches against pinned neighbour frames. This AX-presses the element the agent saw at that point, which is arguably the intent, and `hitTestElement` is live. Acceptable.
- A batch `type_text` with nil or non-text live focus falls into the Stage Manager activation fallback (activates the target app, then restores). A 0.15s settle after `press_key cmd+option+f` may not be enough for Mail to move focus, so text can land in the list or trigger activation. This is the M5 live guard's job; see UQ1.

## Recommended actions
1. M3 + M4 (docs, trivial) before opening the PR.
2. Decide M2 (fail closed on cache miss with element_index steps). Small, testable, reduces blind multi-step risk.
3. Decide M1 heuristic (user call; behaviour change).
4. L1 in the same pass as M2 if touching `performActions`.
5. Remaining Lows as follow-ups.

## Metrics
- Tests: 496, 0 failures x2 (main-loop run); new classes 7; smoke step added (L1 live run pending)
- Lint/type: not run (read-only brief); no `any`-widening or lint suppressions added; `as!` uses are guarded by CFGetTypeID or pre-existing
- Live acceptance M1-M6 / L1-L5: pending (main loop)

## Unresolved questions
1. Is the 0.15s inter-step settle enough for Mail's `cmd+option+f` -> `type_text` in a batch? This is decided only by the M5 live guard (no-Return probe). If it fails, the pre-authorized raise to ≤0.3s applies.
2. M1: should "tree empty" mean "no records under the window, excluding the menu bar"? This changes when screenshots attach, so it needs the user.
3. M2: fail closed for `element_index` batches on a cache miss (plan Q3)? Recommended yes.
4. Is a render byte-identical bracket on Finder/Mail/TextEdit (M4) required before the PR opens, or only before merge?
