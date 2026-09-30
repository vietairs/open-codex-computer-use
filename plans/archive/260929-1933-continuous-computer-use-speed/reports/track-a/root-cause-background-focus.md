# Root cause: background focus signal, focus theft audit (Track A bench guard)

Read-only. B = baseline afb60fa (`.claude/worktrees/ocu-speed-bench`), A = Track A d6b4cc8 (`.claude/worktrees/continuous-computer-use-speed`).
Kit paths are relative to `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/`. `InputSimulation.swift`, `SkyClickSimulation.swift`, `SkyLightSPI.swift`, `AppDiscovery.swift` are identical in A and B, so their line numbers apply to both. Where a file differs, lines are given as A / B.

## Headline

1. **`type_text` steals focus by design when the snapshot has no focused element.** `ComputerUseService.swift` A:1071-1081 / B:889-899. When `focusedElement` is nil or not a text element, the code calls `NSRunningApplication.activate` on the target, sleeps 80 ms, posts the keys, then re-activates the app that was frontmost before. A background Mail has AX focus nil, so every `type_text` activates Mail. This breaks decision 19 in both trees. In A the batch path has the same flaw: it reads focus live through the app element (`liveFocusedElement`, A:1351-1364), which is also nil in the background.
2. **The missing focus line is expected from the code; the Mail-side cause is still unconfirmed.** The server's only focus source is `AXFocusedUIElement`: from the system-wide element when the target is frontmost, otherwise from the app element (`AccessibilitySnapshot.swift` A:588-596 / B:528-536). The line is printed only when that element is `CFEqual` to a rendered node (A:1134-1136) and there is no selected text (A:143-149). The server never reads the per-element `AXFocused`. The prefetch list has no `AXFocused` (`AccessibilityAttributePrefetch.swift:6-10`), and no `AXSelectedTextRange` is read anywhere.
3. **The bench abort was the guard working, not a harness bug.** With the current server, a background `type_text` cannot happen without activation. So a fail-closed guard must either block before `type_text` (as it did) or come with a server change.

## 1. Focus theft audit

| # | Code path (file:line, A / B) | What it does | Reached by default tool calls? | Steals user focus? |
|---|---|---|---|---|
| 1 | `ComputerUseService.swift` A:1073-1079 / B:891-897, `typeText` keyboard-fallback branch | `activate(options: [])` on the target, types, re-activates the original app | **Yes**, `type_text` (single call, and batch step in A) whenever the focus is nil or a non-text element. That is always the case for a background Mail. | **Yes.** The target becomes frontmost for at least 80 ms. Keys the user types during that window go to the target. The restore step also re-orders windows. |
| 2 | `AccessibilitySnapshot.swift` A:488-512 / B:428-452, `recoverVisibleWindow` | `unhide`, `activate(.activateAllWindows)`, `/usr/bin/open -b <bundle>`, AXRaise, set AXMain and AXFocused on the window | Only with `recoveryPolicy == .allowActivation` (the default for `get_app_state`, every `finishAction`, and every click except `sky_click`, A:29-31) **and** when no AX window is found (A:385-387) or no CG window exists for the pid (A:400-402). A background Mail with a visible window does not trigger it. A hidden app, or one with no windows, does. | **Yes, when reached.** |
| 3 | `ComputerUseService.swift` A:1633-1693 / B:~1200-1250, `activateClickTarget` | AXRaise, then set AXMain and AXFocused on the element | `click` with the `auto` or `accessibility` method, **only when the target role is AXWindow** (`canUseActivationOnlyClickFallback`, A:519-525) and no pressable descendant handled the click | AXRaise and AXMain raise and order the window, but the app should not become active. **Most likely a visual raise, not keyboard theft. Unconfirmed.** |
| 4 | `InputSimulation.swift:49-57` `prepareAppForGlobalPointerInput`, plus `.cghidEventTap` posts at :172 and :311 | AXRaise/AXMain/AXFocused on the window, else `activate(.activateAllWindows)`, then HID-tap events that move the real pointer | Only when `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1` (A:247-256): `click_method=global`, and the scroll/drag/click fallbacks (A:2360-2367, 2385-2392, 2409-2416, 2483-2491) | **Yes.** The gate is off by default. |
| 5 | `AppDiscovery.swift:363-371` `openApplication` | `NSWorkspace.openApplication` with a default `OpenConfiguration`, so `activates` is true | Any tool, when the queried app is **not running** (`resolve` → `launchIfPossible`, :144-156, :301-321) | **Yes**, on launch. |
| 6 | `SkyLightSPI.swift:155-188` plus `SkyClickSimulation.swift:145-205` | Sends `SLPSPostEventRecordTo` "focused" and later "unfocused" records to the target PSN, then posts via `SLEventPostToPid` and `postToPid` | Only with `click_method=sky_click` | By design it makes AppKit **believe** it is active without a WindowServer front change. **Unconfirmed that no visible focus change happens.** |
| 7 | `ComputerUseService.swift` A:966 / B:802, `perform_secondary_action` | Runs any listed action, including "Raise" on a window | Only when a caller explicitly asks for Raise | Visual raise. Not reached by the combio mix. |
| 8 | `click` in auto mode on elements with no AX handler → `clickBackgrounded` / `clickTargeted` (`InputSimulation.swift:71-134`, `CGEvent.postToPid`) | Mouse events posted only to the target pid, with window fields 91/92 and `CGEventSetWindowLocation` | Default click fallback when AX cannot handle the target | No pointer move, no HID tap. Whether AppKit makes the window key on a pid-posted mouseDown **is unconfirmed**. |
| 9 | Not a risk: `SoftwareCursorOverlay.swift:305-314, 829-830` | `.nonactivatingPanel`, `ignoresMouseEvents`, `canBecomeKey == false` | Always, when the visual cursor is on | No. |
| 10 | Not a risk: `AccessibilitySnapshot.swift` A:651-652 / B:590-591 | Sets AXManualAccessibility and AXEnhancedUserInterface on the app element | Every snapshot | No focus change. |

Also absent: no `CGWarpMouseCursorPosition` or `CGAssociateMouseAndMouseCursorPosition` anywhere, and no `kAXFrontmost` setter. `press_key`, `set_value`, `scroll` (AX actions first, then pid post) and `drag` (pid post) never call activate by default.

Per-tool summary, with default env:
- **Safe:** `press_key`, `set_value`, `scroll`, `drag`, `get_app_state`/screenshot (safe as long as the app is running and has a window).
- **Steals focus:** `type_text`, whenever focus is nil or not a text element.
- **Can raise a window:** `click`, only when the target role is AXWindow.
- **Launches and activates:** any tool, when the app is not running.
- **`perform_actions` (Track A only):** inherits each step's behaviour. Its `type_text` step always uses the live focus from the app element (A:1060-1064), so a background batch activates the target. Its final state uses the `allowActivation` recovery policy unless a step uses `sky_click` (`BatchActionRunner.swift:128-135`).

## 2. Keyboard delivery to a background app

- **`press_key`:** `CGEvent.postToPid` for modifier down, key down/up, and modifier up (`InputSimulation.swift:267-302`). It uses no SkyLight, no activation, and no AX.
- **`type_text`, first choice:** an AX value write, `AXUIElementSetAttributeValue(kAXValue, base+text)`, on the snapshot's focused element (A:1975-1994 / B:1535-1552). It sends no keystrokes and needs no activation, but **only runs when focus is non-nil and settable**.
- **`type_text`, keyboard route:** otherwise Unicode chunks go through `postToPid` (`InputSimulation.swift:222-242`). If the focused element is not text-like, the activation from section 1 row 1 runs first.
- **Where pid-posted keys land in an inactive app is unconfirmed.** AppKit sends keyDown to `NSApp.keyWindow`'s first responder, and command key equivalents go through `mainMenu performKeyEquivalent`. The window's first responder survives while the app is inactive, but whether AppKit treats that window as key is not established. Two points of evidence from the original session:
  - `press_key Return` landed in Mail's first responder, the message web view (see `plans/reports/test-260929-1720-live-mail-combio-and-remote-jev.md`, item 2).
  - `cmd+option+f` is a menu key equivalent, so it can plausibly move the first responder even without a key window.
- **Clicking the search field (row 203) does not target the field.** Row 203 has no AX actions (the diag render line is `203 search text field (settable, string)` with no Secondary Actions). `performAXClickSequence` therefore falls through to `descendantClickCandidates` (A:1591-1597, 1826-1848). The child `204 button Search` sits on the leading edge, so the trailing-side filter (A:435-477) does not drop it, and **AXPress goes to the Search button**. That matches the original run's observation that "the Search button only opened the suggestions popover". Whether that AXPress also makes the field the first responder is unconfirmed; most likely it does not. The pid-posted mouse fallback is not reached for row 203.

## 3. A focus signal that works in the background

What the server reads today (both trees):
- the app or system-wide `AXFocusedUIElement` only;
- `AXSelectedText` of that element (`copySelectedText`, A:1435);
- nothing else: no per-element `AXFocused`, no `AXSelectedTextRange`, no `AXMainWindow`, and no window-level `AXFocusedUIElement`.

Candidate signals (none verified live, because live probing was forbidden in this task):
- (a) **`AXFocused` on each element during the tree walk.** Add `kAXFocusedAttribute` to `AXAttributePrefetch.renderAttributes`. This adds no extra round trip, because Track A already batches each node's reads into one multi-attribute call. It fixes the missing line if Cocoa reports `AXFocused=true` for a first responder in a non-key window of an inactive app. **Unconfirmed; this is the key probe.**
- (b) **`AXFocusedUIElement` on the focused or main window element.** Standard Cocoa windows do not usually expose it. Low confidence.
- (c) **`AXSelectedTextRange` on the field.** It is non-nil while the field editor is attached, which is plausible while the window is inactive. Medium confidence. It is an indirect signal, since the field editor can stay attached after focus moves elsewhere in some apps.

Proposed server change (a product fix, not harness-only):
- `preferredFocusedElement`: when the app element returns nil, fall back to the rendered element with `AXFocused==true`.
- A `liveFocusedElement` (A:1351) twin for the batch path: read `AXFocused` on the resolved field element.
- **Remove or gate the activate-and-restore branch in `typeText` (A:1071-1081 / B:889-899). This is required by decision 19 regardless of the focus fix.** Replace it with fail-closed behaviour: throw "no background-safe focus target", or optionally use SkyLight synthetic focus (row 6), which is private SPI and still unconfirmed.

Scope:
- The defect predates Track A; B has the same code. Track A's decision 12 (batch reads focus live) inherits it: a background `perform_actions` `type_text` activates the app.
- Recommendation: a small separate fix PR, or add it to Track A only if the user accepts the scope change, because it touches `type_text` behaviour, which is a public contract.

## 4. Bench guard options (all fail closed)

| Option | Keeps call mix? | Change needed | Fails closed? | Notes |
|---|---|---|---|---|
| **G1 (recommended):** server fix (section 3), then the guard requires `(focused)`/focus line = search field after cmd+option+f, `require_search_value` after `type_text`, and the value check again before Return | Yes | **Server + harness** | Yes | `type_text` then takes the AX set-value path: no keys, no activation. |
| **G2:** add a frontmost check around every call (`lsappinfo front`, before and after), aborting if the frontmost app changes or becomes Mail | Yes | Harness only | Detects theft, **but after the fact**. Use it as a tripwire alongside G1, not as the only guard. | Run it on every bench round, since decision 19 covers bench runs too. |
| **G3:** swap `type_text` for `set_value 203 "combio"` (AX, background-safe), then `require_search_value`, then have a harness-side AX helper verify `AXFocused` or `AXSelectedTextRange` on the field before Return | No (set_value 2, type_text 0) | Harness only, but the helper needs its own Accessibility grant | Yes, if the probe signal holds | The original run showed that `set_value` alone does not run the search, so Return still needs keyboard focus. |
| G4: keep the current guard as is | Yes | none | Yes, but it never runs in the background | This is the observed B0 abort. |

Not acceptable: removing the guard, or running with Mail frontmost (rejected by decision 19).

A separate hazard to fix whichever option is chosen: `click` on row 203 presses the Search button (section 2). Its effect on the popover could change which element holds focus. The G1 guard already covers this.

## 5. Could the original combio session have typed into the wrong place?

**Yes. Flagged.** Evidence from the session transcript, 07:10-07:14Z:
- **07:11:28** `press_key Return`: the focus line before it was `86 HTML content` (the message web view), and the report confirms Return went to the web view.
- **07:11:53** a coordinate click at (600,12) opened New Message, and a `press_key Return` was issued 0.24 s later, in parallel. The focus line afterwards was the compose `message body`, so the Return most likely typed a newline into a draft. The draft was then discarded with Don't Save.
- **07:11:37** `click 248` and `press_key Return` were issued 0.16 s apart, so they raced.
- **07:13:14** `type_text "combio"` ran while the focus was `243 search text field (settable)`. It therefore used the AX value write: no keystrokes and no activation. The text was correct.
- **Caveat on the premise:** the original session **did** show focus lines, while the B0 background render shows none. Either Mail was actually frontmost for part of that session, or the missing line in B0 has another cause (H2 below). "The original ran in the background" is therefore unverified.

## Hypotheses for the missing focus line (B0)

- **H1 (most likely, unconfirmed):** Mail's app-level `AXFocusedUIElement` is nil while Mail is inactive. This is consistent with the code path (A:588-596) and with the lines being present in the original session if Mail was frontmost then.
- **H2 (open):** `AXFocusedUIElement` returns an element that is not `CFEqual` to any rendered node, for example one beyond the tree limits. The line is then suppressed by A:1134. A live read of the app attribute would separate H1 from H2.
- **H3 (eliminated):** the focus line was replaced by "Selected text". The diag render has no `Selected text:` line.

## Unconfirmed; the evidence that would settle it
- H1 vs H2: read `AXFocusedUIElement` on the app element of a background Mail (nil or not).
- Whether `AXFocused` or `AXSelectedTextRange` on row 203 is true or non-nil after cmd+option+f while Mail is in the background. This decides whether G1 and G3 are viable.
- Whether a pid-posted keyDown to an inactive Mail reaches the window's first responder: type into the field via `press_key` while in the background, then read its value.
- Whether AXRaise/AXMain on a window (rows 3 and 7) or the `sky_click` synthetic focus (row 6) changes the frontmost app: `lsappinfo front` before and after.
