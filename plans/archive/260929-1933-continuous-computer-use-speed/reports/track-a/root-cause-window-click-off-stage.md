# Root cause: `click` on Mail's window element moves it off stage (1070014)

Source: hvn-root-causer (read-only), saved by the controller. Status: DONE_WITH_CONCERNS. The step that fired is inferred from source, not observed.

## Symptom
Under Stage Manager, Mail runs as a background app with its window on stage. `click app=Mail element_index=<window>` in `auto` returns cgWindowNotFound after about 1.1 s, and the window moves into the strip. The x/y click at 3e306ce did the same. Clicks on the search field element (AXPress, then a focus write) never did.

## Findings (CUS = packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift)
- **The error is raised after the action ran.**
  - cgWindowNotFound comes only from `noBackgroundWindowMessage` (Errors.swift:7-11). It is thrown at AccessibilitySnapshot.swift:414 (no AX window found) or :445. We infer :414.
  - In the click flow, the only snapshot rebuild that can throw it is the post-action `finishAction` → `refreshSnapshot` (CUS:951-955, 1403-1421). The pre-click snapshot is the cached one (CUS:1392-1398, 1425-1431).
  - So the message "has no visible window / does not activate or raise" is misleading: a press or posted events had already been delivered.
- **`auto` order for a window target:**
  1. A preferred press on the window. Mail's window exposes only AXRaise, so this does nothing.
  2. A descendant AXPress. It searches 3 levels deep, skips title-bar buttons, and tries the smallest frame first (CUS:1616-1622, 1737-1754, 1780-1829).
  3. A hit-test press at the window centre.
  4. `performNonAXClickFallback`: `clickBackgrounded` posts mouse down/up with `CGEvent.postToPid` and window fields 91/92 (CUS:2385-2432, InputSimulation.swift:87-134).
- **H1 (most likely for repro #1): step 2 pressed a hidden tab-bar or toolbar control**, such as "new tab" or "Close tab" when only one tab is open. Hidden buttons may report zero-area frames, which sort first. That press changes the window set, and nothing is posted after it.
- **H2 (repro #2 and x/y): the posted mouse down/up makes Stage Manager restage the window.** The mechanism is unconfirmed. This part is macOS WindowManager behaviour.
- **Eliminated:** the visual cursor, the AXEnhancedUserInterface/AXManualAccessibility writes, and `finishAction` recovery (it only unhides). The same code ran in clean calls.

## Pre-existing vs new
- **x/y posted clicks are pre-existing.** InputSimulation.swift has no diff against 8f5c523 or origin/main, and the x/y path has always used `allowActivationFallback: false`.
- **Window-element clicks: the tail step changed.**
  - Up to 853fde6, the last step was `activateClickTarget` (raise/main/focus), and no events were posted.
  - Since e89601c, the last step is `clickBackgrounded` at the window centre.
- **The descendant press (step 2) is unchanged in every version, but its pick changed.** Before 1070014 it picked a traffic light; since 1070014 it picks the next-smallest tab-bar or toolbar control.

## Fix options (lowest risk first)
1. **Refuse window-role targets for element clicks** in `auto`/`accessibility`.
   - Where: in `click` right after `lookupElement` (CUS:815), before `moveVisualCursor`. `record.role` is already known. Batch steps share this path.
   - Error text: "element N is the window itself; click a control inside it by element_index."
   - This covers both H1 and H2 for window targets.
2. **Make the error honest.** When the post-action refresh throws the no-window error, say that the click was performed and the window then could not be read (it may have left the stage, closed, or been re-tabbed), and suggest get_app_state.
3. Skip only the posted fallback for windows. Not recommended, because it leaves H1 in place.
4. Posted x/y clicks under Stage Manager: first probe live (clickBackgrounded vs clickTargeted vs sky_click on an empty content area), then decide. This is a follow-up.

## Unconfirmed / how to confirm
- **Which step fired in #1:** rerun once with `OPEN_COMPUTER_USE_DEBUG_INPUT_FALLBACKS=1`. The stderr line "click decision handled by descendant …" means H1; if it is absent, the click fell through to posted events (H2).
- **The frames and subrole of the hidden "Close tab" / "new tab" buttons.**
- **Whether pid-posted clicks restage background windows at all** (the option 4 probe).

## Confirmed live (11:40, debug run at 1070014)
- Run: scratchpad `live-window-click-debug.py`, with the bench agent relaunched via `open --stderr` and `OPEN_COMPUTER_USE_DEBUG_INPUT_FALLBACKS=1`.
- Decision log:
  - `record=index=0 role=AXWindow actions=[AXRaise]`
  - `handled by descendant index=-1 role=nil actions=[AXPress] frame=x=14 y=57 w=18 h=18`
- **H1 is confirmed.** The descendant press hit an 18×18 button at the top left, just under the toolbar. That is the tab bar's "Close tab" button, and pressing it closed Mail's only window.
- The posted-event fallback never ran.
- After the click, Mail had no window at all (not off stage). The user confirmed the window was closed and reopened it.
- **Decision (user):**
  - Refuse window-role element clicks.
  - Make the post-click no-window error honest.
  - Stop the descendant search from pressing hidden or zero-size tab-bar close buttons under other containers.
