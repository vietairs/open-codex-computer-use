# PR #23 review, round 1 (whole branch, head 853fde6)

Read-only. Scope: `origin/main...853fde6`, 25 commits, 50 files, +5819/-434. The review looked at cross-commit interactions, PR body claims, public contract changes, docs and skill accuracy, test quality, and the new 853fde6 commit. Findings already in the two earlier track-a reviews, and the known and accepted items in the brief, are not raised again.

## Summary
- The code is in good shape. 853fde6 closes M1 from the previous review correctly. `typeTextRoute` now refuses any focus that is not text entry before it writes a value or posts a key, and the tests call the production seam (`makeTypeTextFocus`) with real role inputs instead of an impossible hand-built focus.
- No Critical findings. The two Important findings are both docs or claim accuracy:
  - The skill's own `perform_actions` example teaches a Mail flow that the same file says does not work.
  - The PR body and a user-facing error message say "never raise", but a default-path click fallback can still AXRaise.
- Verification:
  - CI: 5/5 checks pass on 853fde6.
  - Local `swift test` at 853fde6 (scratch build path, outside the worktree): 590 tests, 2 skipped, 1 failure. The failure is `DecisionAdvisorTests.testStdioMCPServerPerCallEnvironmentWinsOverAPollutedProcessEnvironment` (DecisionAdvisorTests.swift:516). It is environmental: this agent shell has no CGSession dictionary, so the lock guard treats the session as locked. The branch does not touch that test, and CI passes it.

## Risk level
Medium-low. The runtime changes fail closed where they changed behaviour: type_text refusal, x/y frame mismatch, off-stage coordinate refusal, and refusing an `element_index` batch that has no received state. The remaining risk is agents following wrong guidance, not unsafe input.

## Findings

### Critical
None.

### Important

**I1. The `perform_actions` example in usage.md teaches a flow the same file says fails in the background.**
- Where: `skills/open-computer-use/references/usage.md:170-179`. The example is `press_key cmd+option+f` -> `type_text "invoice"` -> `press_key Return` on Mail.
- Contradicted by:
  - usage.md:111: "A keyboard shortcut such as `cmd+option+f` does not move focus in a background app".
  - `docs/histories/2026-09/20260930-0030-background-click-focuses-text-field.md:28`: a pid-posted `cmd+option+f` does not move the first responder.
- Failure scenario:
  1. An agent copies the canonical batching example while Mail is in the background, which is the default now.
  2. Step 1 posts the shortcut. Focus stays on the message list.
  3. Step 2 `type_text` is refused ("no focused text field in Mail"), and step 3 never runs.
  - The failure is safe (fail-closed), but the documented happy path fails every time.
  - It also teaches agents the shortcut pattern that commit 2eccb18 found to be wrong.
- A second problem: the example is a standalone `open-computer-use call`. Each call is a fresh process with no cached state. So the obvious fix, a `click element_index` step, would be refused by `missingReceivedStateMessage` (BatchActionRunner.swift:117-124; ComputerUseService.swift `performActions` guard) unless the example runs under `--calls` after `get_app_state`, or through MCP.
- Fix: rewrite the example as `get_app_state` then `perform_actions [click element_index=<search field>, type_text, press_key Return]` inside one `--calls` array, or show it as an MCP call. State that the index comes from the preceding state.

**I2. "Clicks never activate, raise or unminimize" is not true of the default click path, and a user-facing error repeats the claim.**
- Claim sites:
  - PR body, "Background operation": "Launching, window recovery, `type_text` and clicks never activate, raise or unminimize the target."
  - `noBackgroundWindowMessage` (Errors.swift:7-10): "Open Computer Use does not activate, raise, or unminimize apps". This text is returned to agents and users.
- Code:
  - `click` with the default `auto` method passes `allowActivationFallback: true` (ComputerUseService.swift:827, :844) into `performAXClickSequence`.
  - When the target record has the AXWindow role and no preferred or descendant press handles it, `activateClickTarget` runs AXRaise, then AXMain = true, then AXFocused = true on the window (ComputerUseService.swift:1648-1665, 1697-1716).
- Failure scenario: an agent clicks element 0 ("standard window ...") of a background app to "select the window". If no child press succeeds, AXRaise can reorder that window above the user's windows without activating the app. That is a visible intrusion that the error text and the PR body say cannot happen.
- Reachability is narrow, because descendant presses usually win first (a separate, known upstream issue). The earlier review logged the mechanism only as Informational I1. What is new here is that the PR now makes an absolute public claim about it.
- Fix, either:
  - (a) drop AXRaise and AXMain from `activateClickTarget` on the default path, or gate them like the global pointer path; or
  - (b) reword the PR body, `noBackgroundWindowMessage` and RELIABILITY.md to "no activation; an explicit click on a window element may raise it within the app". Then pin the chosen behaviour in `BackgroundOperationInvariantTests`, which today only checks `.activate(`.

### Suggestion

**S1. `Int(Double)` trap on `click_count`, now copied into the batch parser.**
- Where: `ComputerUseToolDispatcher.swift:87` (single click, pre-existing) and `parseBatchStep` (`clickCount: Int(optionalDouble("click_count", ...) ?? 1)`).
- JSON `"click_count": 1e20` parses as a finite Double, and `Int(1e20)` traps. That crashes the MCP server or app agent process for every connected host.
- A large but representable value (for example 100000) instead loops that many press or post events.
- Fix: validate `click_count` as a finite integer in 1...3 (or a small cap) in one helper that both parsers share.

**S2. Text-entry role sets drifted apart after 853fde6. Batch focus probing misses controls that type_text now accepts.**
- Where:
  - `BackgroundFocusResolution.swift:19`: the comment says `backgroundFocusTextEntryRoles` "Matches the roles `canUseKeyboardTextFallback` accepts outright". That is no longer true: `canUseKeyboardTextFallback` also accepts the AXSecureTextField role, the AXSearchField/AXSecureTextField subroles, and "text field/area/entry" role descriptions.
  - `backgroundFocusProbeOrder` (same file) filters probes to the 4-role set only.
- Effect: in a batch, a focused role-`AXSecureTextField` field, or a web "text entry area" AXGroup, is found only if it was the pinned focus. Otherwise the batch `type_text` refuses, while the same single call works. This fails closed and is inconsistent.
- Fix: filter probes with `canUseKeyboardTextFallback(role:subrole:roleDescription:)` or `isClickFocusTextEntry`, and correct the comment. `ClickTextEntryFocus.swift:16` ("every role type_text can deliver to") is stale in the same way.

**S3. The web text-entry match relies on the localized AXRoleDescription.**
- Where: `canUseKeyboardTextFallback` (ComputerUseService.swift:535-541).
- Before 853fde6, a settable AXValue made up for this. Now an AXGroup contenteditable whose role description is localized (a non-English macOS UI language) is refused where it used to work.
- The PR body's "type_text scope" limitation covers custom controls but not the locale case.
- Fix: add one line to the PR body limitation, or match on a locale-independent signal.

**S4. The PR body's carried-frame claim is broader than the code.**
- Claim: "reuses the last returned screenshot frame ... and fails closed otherwise."
- Compact `get_app_state` still captures with `.always` (ComputerUseService.swift:608, the default `capture`) but never returns the image. Rule 1 of `resolveScreenshotPixelSize` then prefers that unreturned image, so a resize between the full state and a compact state is not refused.
- This is user decision 5 and was L2 in the first review. The code is accepted. Only the PR body wording is off: add it to "Human actions required", or qualify the sentence.

## PR body claim check (verified)
- Supported:
  - Text-only default and `include_screenshot` on all 7 action tools plus `perform_actions`.
  - Batch refuses `element_index` steps without received state.
  - Batch x/y fails closed on resize, whether the frame is the pinned image or `lastReturned`.
  - type_text judged by role, with non-text focus refused before any write.
  - The text-field click focus write is an AXFocused write only.
  - Launch uses `activates = false`.
  - Instructions stay under 2048 characters (base only, cascadeGuide known).
  - 590 tests.
- Not supported as worded: I2 ("clicks never ... raise") and S4 ("fails closed otherwise").

## Public contract changes (all additive or intentional)
- New tool `perform_actions`, which makes the tool list 10 (11 with the advisor). Count sites in the smoke suite, tests, ARCHITECTURE.md and QUALITY_SCORE.md are updated.
- New optional `include_screenshot` on 7 tools.
- Action results no longer carry an image by default. This is a behaviour change for existing macOS hosts, and the guidance documents it.
- `set_value ""` is now accepted.
- The `type_text` and `click` descriptions changed. The server instructions were rewritten.
- New error texts: the off-stage, frame-mismatch and no-background-window messages, and the type_text focus message.

## Test quality
- 853fde6 tests are real. They cover the pure seam with production inputs, check both setValue outcomes, and assert zero writes and zero keys on refusal.
- The live wiring of `typeTextFocus` (the subrole read) is covered only indirectly. That is acceptable for a 6-line adapter.
- `BackgroundOperationInvariantTests` is source-grep based. It is useful as a tripwire, but it does not cover AXRaise (see I2).

## Verdict
**Request changes (docs and claims only).** Fix I1 (usage.md example) and I2 (either the code, or the PR body plus the error text plus RELIABILITY wording) before merge. S1 is a cheap hardening fix worth doing in the same pass. S2-S4 are optional.

## Unresolved questions
- For I2, is a raise within the app on an explicit window-element click acceptable to the user? If yes, only the wording changes. If no, remove AXRaise and AXMain from the default path.
