# Avoid Synthetic Row Side Action Clicks

### Request

Investigate and fix the issue where clicking a Feishu (飞书) conversation row in OCU is prone to hitting the "done" checkmark that hovers in on the right side of the row, causing the message conversation to get archived.

### Changes

- Added an `isSyntheticText` flag on the summary `text` record synthesized by the accessibility renderer.
- Element-targeted `click` now uses a left-side safety anchor for synthetic text instead of defaulting to the parent container's center point.
- When clicking synthetic text, filters out the compact hover action on the right (e.g. "Done" / done / archive) before allowing the remaining inline candidates to participate in click selection, preventing the side action from being ranked as the top candidate, while still preserving the ability to click the main row to open the conversation.
- Extended the right-side compact hover action filter to descendant candidates of a general row/container/text, so that clicking the side action itself still activates it, but clicking the row or the row's text no longer treats the side action as the primary candidate.
- For static text clicks, now prefers computing the click anchor using a larger row-level parent container frame first, reducing the risk of hitting an adjacent row due to Electron text-frame offsets.
- When a hit point resolves back to a page-wide Electron/WebArea-level AX element, no longer scans the entire large container's descendant candidates, to avoid a distant clickable element hijacking the click for the current row.
- Narrowed the activation-only fallback to window-level elements only; ordinary static text or containers can no longer claim the click was handled just because `AXFocused` / `AXMain` succeeded — they must still fall through to a directed mouse event.
- Synthesized session-row text in Electron/WebArea now preferentially finds the nearest row-level `AXPress` ancestor and executes it silently, avoiding reliance on the physical-mouse fallback and avoiding hitting the row's right-side side action.
- A re-test found that this WebArea row-level ancestor click optimization mistakenly affected the Chrome/GitHub pinned repository card: the release version of OCU can click a profile's pinned `container` directly to enter the repo, but the dev build would prematurely mark the click as handled without navigating. This optimization is now scoped down to Electron/Lark-style targets only; browser WebArea falls back to the general link/container click path.
- The app-agent proxy now passes through `OPEN_COMPUTER_USE_*` environment variables, making it easier for debug toggles to take effect inside the Dev `.app` agent; normal verification still does not enable the global physical pointer fallback.
- Added unit tests covering the click-anchor strategy for synthetic text vs. ordinary elements, the boundary of the right-side side-action filter, protection against overly broad hit records, the boundary of row-level AX ancestor clicks, the boundary of the Electron-scoped WebArea optimization, and the role boundary of the activation-only fallback.
- Updated the architecture doc to document the click boundary for synthetic text.

### Motivation

The readable text in a Feishu (飞书) conversation list is often a summary synthesized by the renderer for a parent row/container, rather than a real, independent clickable text element. The old logic used this parent container's center point and kept scanning its clickable descendants; when Lark (飞书) hovers in a "Done" button on the right of the row, this button could get selected as the first `AXPress` candidate, turning "open the conversation" into an accidental "done/archive the conversation." The new strategy treats synthetic text as representing only the row's readable summary: the click lands in a safe zone on the left, and descendant candidates are limited to targets that don't look like a right-side side action.

Real-world verification also surfaced another false positive: unclickable static text would prematurely end in the activation-only fallback because `AXFocused` / `AXMain` returned success, so the conversation never actually switched. This fallback is now reserved for window-level elements only; Electron/WebArea row text now prefers the row-level `AXPress` ancestor, keeping the AX action silent, and no longer treats the global physical pointer fallback as the normal passing criterion.

The Chrome/GitHub pinned card re-test exposed a scoping problem with the optimization: a GitHub profile's pinned repository card is also a `container` with a URL in the AX tree, but it belongs to the browser's WebArea, not an Electron conversation list. For this kind of general browser page, the original target / hit-test / directed mouse fallback chain should be preserved; the Electron row-ancestor click optimization should only serve Lark/Feishu-style targets, so fixing the conversation list doesn't break the existing Chrome behavior.

### Files

- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/ARCHITECTURE.md`

### Validation

- `swift test`
- `./scripts/run-tool-smoke-tests.sh`
- `./scripts/build-open-computer-use-app.sh debug`
- Real verification against Feishu (飞书) using the dev app:
  - Under the old patch, clicking session row text like `AgentSphere 双周会群` (AgentSphere Biweekly Meeting Group) / `AgentSphere 研发群` (AgentSphere R&D Group) no longer triggered "Done," but also did not switch the conversation.
  - Under the old patch, clicking the row container could still archive the conversation, confirming the side-action filter can't apply only to synthetic text.
  - Under the new patch, clicking the `AgentSphere 研发群` (AgentSphere R&D Group) row text kept the conversation row intact — it was no longer archived by "Done" — but at that point the conversation still didn't switch; this was later traced to the plain static-text activation-only fallback returning success prematurely.
  - Using only OCU dev app's AX path for re-testing: dynamically located and opened the `司开星` (Kaixing Si) conversation, confirmed the title on the right, then sent `OCU AX静默测试笑话：为什么程序员喜欢喝咖啡？因为没有咖啡因，线程就起不来。` (OCU AX silent test joke: why do programmers like drinking coffee? Because without caffeine, the thread won't start.) — the message appeared in both the list preview and the message area, and the input box cleared.
  - Then dynamically located and opened the `徐昱嵩` (Yusong Xu) conversation, confirmed the title on the right, first used an AX click to focus the text entry area, then sent `OCU AX静默测试笑话：为什么测试工程师进咖啡店先点空杯？因为要测边界条件。` (OCU AX silent test joke: why does a test engineer order an empty cup first at a coffee shop? To test the boundary conditions.) — again confirmed successful sending in both the list preview and the message area.
  - The verification process did not set `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS`, and did not rely on the global physical mouse fallback.
  - Additionally ran non-destructive real-app smoke tests against Chrome, Finder, and Sublime Text: `get_app_state` worked normally, and clicking the currently selected tab / the currently selected Finder sidebar row / the currently selected Sublime tab all succeeded.
  - Used the already-installed release version of OCU `0.1.49` as a control against a Chrome/GitHub profile: directly clicking all 6 pinned repository `container`s successfully entered the repo and read the star count each time.
  - After the fix, rebuilt the dev app, terminated the old dev app agent, then ran the same verification with the dev OCU against the same Chrome/GitHub profile: dynamically resolved all 6 pinned repository `container`s, clicked into each repo one by one, read the star count, went Back to the profile, and all 6 URLs matched expectations.
