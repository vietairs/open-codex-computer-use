## [2026-04-18 14:30] | Task: Stand up a standalone cursor motion lab

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Combining the official video and the cursor-overlay clues already analyzed, open a separate directory in the current repo, implement a standalone, open-sourceable software cursor motion curve, and keep pushing the analysis and delivery forward.

### 🛠 Changes Overview
**Scope:** `Package.swift`, `experiments/CursorMotion/`, `docs/`, `README`

**Key Actions:**
- **[Add a standalone target]**: Add `CursorMotion` to the Swift Package, runnable standalone via `swift run CursorMotion`.
- **[Implement the motion demo]**: Add a parameterized cursor motion model, Bezier path generation, spring/timing simulation, and a SwiftUI tuning UI.
- **[Fill in click interaction]**: Support clicking anywhere on the canvas to generate multiple candidate paths, and select one path to drive the cursor animation.
- **[Converge candidate curves and display logic]**: Expand into multiple descriptor-driven trajectory families, and keep the primary path visible even with `DEBUG` off.
- **[Fix click coordinates and the dead zone]**: Unify the coordinate semantics between AppKit click-capture and the SwiftUI canvas, remove the misleading rectangular event-exclusion area, and avoid a hidden dead zone in the bottom region where clicks did nothing.
- **[Tighten demo control state]**: Change the `DEBUG` toggle's on-state to a clear highlight, and make the top controls occupy only their own area, no longer blocking canvas events with a full-layer transparent container.
- **[Enhance turn/brake feel]**: Change path generation from "only looking at the start-end connecting line" to a mixed constraint of "line direction + cursor heading", and add `turn` / `brake` families, making the primary path more likely to follow the initial heading first, then turn back in, and end with a braking pull-back.
- **[Redo timing / rotation]**: Change progress advancement from spring + `easeInOut` to a minimum-jerk, bell-shaped timing closer to a human hand's pointing motion; also keep the cursor continuously facing the tangent direction during motion, then smoothly return to its classic orientation on arrival.
- **[Remove extra end-of-path displacement]**: Remove the settle overshoot at the position layer, keeping continuous motion and natural deceleration, no longer shifting an extra bit at the end.
- **[Add curvature-aware timing]**: Build a weighted-effort lookup for the path, mapping high-curvature and large-heading-change segments to slower time advancement, giving the "initial turn-back" and "final convergence" phases a more natural speed distribution, instead of just walking the Bezier parameter `t` uniformly.
- **[Switch to an asset-based cursor]**: Switch the standalone lab's vector arrow to a target-bundled PNG asset, establish a separate glyph calibration, and converge the resting pose to closely match the default orientation seen in the video.
- **[Switch to tip-anchor hit alignment]**: No longer position using the center of the whole cursor image; instead align the image's tip to the motion sample point, avoiding click-coordinate offset reappearing after switching to an upward-facing asset.
- **[Converge heading-follow during motion]**: Unify the motion simulator's rotation into an absolute pose based on the glyph's neutral heading, continuously following the curve's tangent direction during motion, then smoothly returning to the resting angle when finished.
- **[Add a launch/whip-turn candidate family]**: Add a `launch` family to the path builder that more strongly emphasizes the current heading's inertia, and add an explicit launch bias during control-point generation, making the start phase feel more like charging forward along the current heading first, then cutting back toward the target.
- **[Add path-quality ranking]**: Candidate paths are no longer ranked purely by family constant; ranking now also weighs how well the start heading fits, early-segment turn strength, end-segment tangent alignment, and terminal straightness, so a primary path that "both whips out and finishes cleanly" is chosen more reliably.
- **[Strengthen end-segment braking timing]**: Split the weighted-effort lookup from a single edge profile into start/end segments; the early segment weights turn-back effort more heavily, the late segment weights braking effort more heavily, and the total duration of heavily weighted paths is stretched slightly, making the final deceleration and convergence more pronounced.
- **[Refactor to the official two-layer model]**: Switch the standalone lab from the old "path sample + end-of-path rotation settle" implementation to the recovered `20` official candidate paths, official-style spring progress, and standalone visual dynamics consistent with the main runtime.
- **[Remove the speculative tuning main path]**: The lab control panel no longer treats sliders with not-fully-confirmed semantics, such as `START HANDLE` / `ARC FLOW` / `SPRING`, as the primary entry point; it now directly displays the selected candidate's id, score, and measured values.
- **[Verify on the real app]**: Actually launch the app corresponding to `swift run CursorMotion`, confirm that both `REPLAY` and canvas clicks switch the candidate path, and observe that the end segment isn't a rotation in place but that the path layer first forms a hooking-back arc, with visual dynamics then adding pose lag and idle sway.
- **[Sync repo knowledge]**: Add the motion-model reverse-engineering analysis doc, the active execution plan, architecture notes, the README entry, and a history entry.

### 🧠 Design Intent (Why)
The main `SoftwareCursorOverlay` is better suited to carrying product behavior, not to continuing to pile on tuning knobs and experimental UI. This time, the cursor-curve experiment was split out into a standalone lab in order to first stabilize the parameter model and the visual feel, then decide which parts are worth feeding back into the main MCP implementation or open-sourcing separately.

### 📁 Files Modified
- `Package.swift`
- `README.md`
- `README.zh-CN.md`
- `docs/ARCHITECTURE.md`
- `docs/exec-plans/active/20260418-standalone-cursor-lab.md`
- `docs/references/codex-computer-use-reverse-engineering/README.md`
- `docs/references/codex-computer-use-reverse-engineering/software-cursor-motion-model.md`
- `experiments/CursorMotion/README.md`
- `experiments/CursorMotion/Sources/CursorMotion/CursorMotionModel.swift`
- `experiments/CursorMotion/Sources/CursorMotion/CursorLabRootView.swift`
- `experiments/CursorMotion/Sources/CursorMotion/CursorMotionApp.swift`

### 🔁 Follow-up (2026-04-19)
**Scope:** `experiments/CursorMotion/`, `docs/`

**Key Actions:**
- **[Sync the main runtime's recovered motion model]**: The standalone lab now directly uses the recovered base/arched candidate generation strategy, the `VelocityVerlet` progress spring, and standalone visual dynamics.
- **[Redo the lab UI's semantics]**: The control panel now displays the selected candidate path and measurements, instead of continuing to expose sliders that could be misread as "confirmed official semantics".
- **[Add standalone verification]**: Actually launch the app, and verify via desktop interaction that both `REPLAY` and clicking a new target switch the candidate, with the UI reflecting the selection result (e.g. `BASE-SCALED-GUIDE` / `ARCHED`) in real time.
- **[Restore heading-follow for the arrow]**: Based on layered evidence from `SoftwareCursorStyle.velocityX / velocityY / angle` and `CursorView._animatedAngleOffsetDegrees` in the bundled `SkyComputerUseService`, fix the lab's pose from "a single, small, constrained angle offset" back to "primary heading follows velocity direction + a small additional wiggle offset".
- **[Add lab-chooser constraints]**: After the user pointed out that the default sample would select an overly exaggerated large loop, clearly separate the two layers of "recovered candidate pool" versus "in the real environment there is also a target-window chooser"; the lab now adds a synthetic corridor hit-count, avoiding treating some overly absurd-but-smooth arched candidates across the whole canvas as the official mandatory result.
- **[Fix candidate coordinate-system interpretation]**: After comparing against the official video, confirmed that previously treating the recovered guide/arc constants directly as fixed screen-coordinate vectors produced distorted loops in certain quadrants; now the path is first projected onto a local start→end basis before generating candidates, and the candidate family re-converges to a C-shaped/elliptical distribution around the main axis.
- **[Switch the main path to a heading-driven chooser]**: After further comparison with the official video, confirmed the standalone lab cannot use the raw reverse-engineered `20`-candidate pool directly as the default path selection; it now feeds the current visible heading and the final resting pose together into the chooser, so that "a single-sided C-shape when a turn is needed, near-straight when no turn is needed" becomes the default distribution again.
- **[Sync path selection to the runtime overlay]**: The main `SoftwareCursorOverlay` now also switches to the same heading-driven candidate family; the raw reverse-engineered `20` candidates are still kept in `StandaloneCursor` / the Python reconstruction script for analysis comparison, but are no longer used directly as the runtime's primary chooser.
- **[Add heading-constraint regression tests]**: Add tests that explicitly verify two behaviors — "prefer a near-straight line when heading is already aligned" and "prefer a large turn-back arc when the start heading is reversed" — to prevent regressing back to strange, distorted curves.

### 🔁 Follow-up (2026-04-20, synthesized overlay style)
**Scope:** `experiments/CursorMotion/`, `Package.swift`, `docs/`

**Key Actions:**
- **[Revert to matching script visuals]**: After comparing against the reference image from the user's `render-synthesized-software-cursor.swift` script, confirmed the lab's currently reused bright-white asset style is wrong; switched to prioritizing the official `252x252` runtime baseline image from the repo, falling back to the same procedural pointer/fog as the script when it's missing.
- **[Tighten the settle state]**: `CursorMotionSimulator`'s idle state no longer drifts in XY; it keeps position fixed and only retains a small, fixed-center wobble angle, matching the script's default "slight rotation in place".
- **[Retract incorrect doc wording]**: The README, architecture notes, and execution plan no longer claim the lab reuses `SoftwareCursorKit`'s shared glyph renderer; they now explicitly reference the scripted baseline/procedural renderer.

### 📁 Additional Files Modified
- `Package.swift`
- `experiments/CursorMotion/Sources/CursorMotion/CursorGlyphCalibration.swift`
- `experiments/CursorMotion/Sources/CursorMotion/CursorLabRootView.swift`
- `experiments/CursorMotion/Sources/CursorMotion/CursorMotionModel.swift`
- `experiments/CursorMotion/Sources/CursorMotion/SynthesizedCursorGlyphView.swift`
- `experiments/CursorMotion/README.md`
- `docs/ARCHITECTURE.md`
- `docs/exec-plans/active/20260418-standalone-cursor-lab.md`

### 🔁 Follow-up (2026-04-20, decouple visible arrow angle)
**Scope:** `experiments/CursorMotion/`, `docs/`

**Key Actions:**
- **[Separate internal heading from visible angle]**: Keep the motion model's internal `rotation` for the next segment's path-selection reference, but add a separate `displayRotation` for glyph rendering, avoiding the arrow continuously pointing along the path direction like a car's nose while moving.
- **[Change to a slight lean]**: The visible angle during the moving phase now only applies a small deflection based on turn dynamics; the idle phase still retains the small in-place wobble.
- **[Sync doc wording]**: The README, architecture notes, and active plan no longer describe the lab's current behavior as "the arrow's primary heading visibly follows the motion direction".

### 📁 Additional Files Modified
- `experiments/CursorMotion/Sources/CursorMotion/CursorMotionModel.swift`
- `experiments/CursorMotion/Sources/CursorMotion/CursorLabRootView.swift`
- `experiments/CursorMotion/README.md`
- `docs/ARCHITECTURE.md`
- `docs/exec-plans/active/20260418-standalone-cursor-lab.md`

### 🔁 Follow-up (2026-04-20)
**Scope:** `experiments/CursorMotion/`, `docs/`

**Key Actions:**
- **[Remove the leftover white dot at the start point]**: The `CursorMotion` canvas no longer persistently renders a white marker at the start point, avoiding a misleading white dot left at the origin after the cursor moves along the curve.
- **[Tighten the DEBUG-off state]**: With `DEBUG` off, the selected primary trajectory and target-point marker are no longer kept; the entire debug overlay layer hides together, avoiding leftover trajectory lines and dots outside debug mode.
- **[Switch the primary visuals to a neutral gray-purple]**: Switch the lab's background gradient, debug highlight, and control accent color from the previous pink-leaning scheme to a neutral gray-purple close to `#E3E2E6`, avoiding a visibly pink tint.

### 📁 Additional Files Modified
- `experiments/CursorMotion/Sources/CursorMotion/CursorLabRootView.swift`
- `experiments/CursorMotion/README.md`

### 🔁 Follow-up (2026-04-20, align glyph baseline heading with official cursor artwork)
**Scope:** `experiments/CursorMotion/`, `docs/`

**Key Actions:**
- **[Retract the extra local rotation compensation]**: After comparing against the standalone `render-synthesized-software-cursor.swift` script and the official `252x252` runtime baseline image, confirmed that the lab's extra `restingRotation = -26.5°` was permanently skewing the visible heading during motion.
- **[Change the resting orientation to the upper-left baseline]**: `CursorGlyphCalibration` now defines the zero-rotation baseline directly as the official arrow's natural resting orientation; in the lab's y-down coordinates it uses `neutralHeading = -3π/4` and `restingRotation = 0`, so path heading and glyph orientation share the same reference.
- **[Align with the main runtime's semantics]**: This adjustment also brings `CursorMotion`'s heading calibration approach back in line with `SoftwareCursorOverlay`'s, no longer maintaining an extra experimental local offset layer.

### 📁 Additional Files Modified
- `experiments/CursorMotion/Sources/CursorMotion/CursorGlyphCalibration.swift`
- `docs/exec-plans/active/20260418-standalone-cursor-lab.md`

### 🔁 Follow-up (2026-04-20, fix y-axis mismatch in glyph rendering)
**Scope:** `experiments/CursorMotion/`, `docs/`

**Key Actions:**
- **[Locate the rendering coordinate-system mismatch]**: After further investigating the user-reported "tail leading" phenomenon, confirmed that `CursorMotion`'s path / heading advances in SwiftUI's y-down coordinates, but `SynthesizedCursorGlyphView` actually uses AppKit's default y-up drawing coordinates.
- **[Unify the flip of angle and offset]**: Add an explicit conversion at the glyph rendering layer, uniformly mapping screen-space `rotation`, `cursorBodyOffset`, and `fogOffset` into AppKit drawing space, avoiding the visible pose being vertically mirrored during motion.
- **[Keep the motion model unchanged]**: This time the candidate paths and the spring were not touched further; only the display-layer coordinate mapping was fixed, leaving heading-driven path selection and visual dynamics still operating with their original y-down geometric semantics.

### 📁 Additional Files Modified
- `experiments/CursorMotion/Sources/CursorMotion/SynthesizedCursorGlyphView.swift`
- `docs/exec-plans/active/20260418-standalone-cursor-lab.md`

### 🔁 Follow-up (2026-04-20, restore visible heading during moves)
**Scope:** `experiments/CursorMotion/`, `docs/`

**Key Actions:**
- **[Retract the slight-lean assumption based on official frame sampling]**: After comparing against the official frames 1-9 provided by the user, confirmed that during the moving phase the arrow's primary heading continuously follows the current move heading, rather than only retaining a small turn lean.
- **[Remove the extra displayRotation layer]**: `CursorMotion`'s glyph rendering goes back to directly using the visual dynamics' primary `rotation`; the previously added `displayRotation / visibleRotationOffset` has been removed, avoiding losing the primary heading.
- **[Keep the small idle wobble]**: The idle phase still uses the small wobble-angle approximation corresponding to `_animatedAngleOffsetDegrees`, but this offset layer is applied on top of the primary heading again, rather than replacing the visible orientation during moving.
- **[Sync current doc wording]**: The README, architecture notes, and active execution plan are uniformly changed back to describing it as "the arrow follows heading during the moving phase, then returns to the resting pose once stopped".

### 📁 Additional Files Modified
- `experiments/CursorMotion/Sources/CursorMotion/CursorMotionModel.swift`
- `experiments/CursorMotion/Sources/CursorMotion/CursorLabRootView.swift`
- `experiments/CursorMotion/README.md`
- `docs/ARCHITECTURE.md`
- `docs/exec-plans/active/20260418-standalone-cursor-lab.md`

### 🔁 Follow-up (2026-04-20, restore slider tuning surface)
**Scope:** `experiments/CursorMotion/`, `docs/`

**Key Actions:**
- **[Restore the top-left slider panel]**: Re-add the five sliders the user pointed out had been removed — `START HANDLE`, `END HANDLE`, `ARC SIZE`, `ARC FLOW`, `SPRING` — back to the top-left of `CursorMotion`, and keep `REPLAY` / candidate metrics as an auxiliary observation panel.
- **[Reconnect parameter semantics]**: `CursorMotionParameters` is no longer just an empty shell of default values; these sliders now directly drive the heading-driven path builder's start/end handle, arc size/flow, plus the progress spring configuration and travel duration.
- **[Add custom slider styling]**: Implement the local tuning controls with a thin track + white circular thumb closer to the user's screenshot, avoiding just falling back to the system default control style.
- **[Sync doc boundaries]**: Both the `CursorMotion` README and the active execution plan are changed to explicitly state that "the sliders are local tuning entry points, not a binary-confirmed mapping to official fields".

### 📁 Additional Files Modified
- `experiments/CursorMotion/Sources/CursorMotion/CursorMotionModel.swift`
- `experiments/CursorMotion/Sources/CursorMotion/CursorLabRootView.swift`
- `experiments/CursorMotion/README.md`
- `docs/exec-plans/active/20260418-standalone-cursor-lab.md`

### 🔁 Follow-up (2026-04-20, apply arc-size semantics from slider investigation)
**Scope:** `experiments/CursorMotion/`, `docs/`

**Key Actions:**
- **[Clarify that ARC SIZE isn't cursor size]**: `ARC SIZE` is now explicitly settled as a "path curvature" knob, no longer leaving room for it to be misread as the cursor glyph's size.
- **[Wire it to arc height and control-point lateral offset]**: The heading-driven path builder now uses `ARC SIZE` to tune `baseArcHeight`, the guide normal bias, and the start/end normal scale all at once, so the slider directly affects the mid-segment's offset from the chord and the overall opening width of the curve.
- **[Wire it to chooser preference]**: The scoring was also extended to account for `ARC SIZE`'s effect on family selection; smaller arcs lean more toward `direct/tight`, and larger arcs are more likely to keep wider arcing paths such as `turn/brake/orbit`.
- **[Add default-sample verification]**: Verified with the lab's default points: at `arcSize=0.04`, `brake-primary-tight` is selected with `curveScale≈10.3` and mid-segment `y≈326.8`; at `0.12` it's still within the primary family, but `curveScale≈47.7` and mid-segment `y≈345.5`, directly showing the increased curvature.

### 📁 Additional Files Modified
- `experiments/CursorMotion/Sources/CursorMotion/CursorMotionModel.swift`
- `experiments/CursorMotion/README.md`
- `docs/exec-plans/active/20260418-standalone-cursor-lab.md`

### 🔁 Follow-up (2026-04-20, remove mid-curve point feel introduced by arc-flow)
**Scope:** `experiments/CursorMotion/`, `docs/`

**Key Actions:**
- **[Locate that it isn't a SPRING problem]**: Re-checked and confirmed `SPRING` only affects progress timing and isn't involved in path geometry; the "extra point in the middle" the user saw came from the first-round implementation of `ARC FLOW`.
- **[Remove the middle join directly]**: `ARC FLOW` is no longer implemented via an explicit mid-anchor two-segment curve; it's pulled back to a single-segment cubic with front/back control-point phase offsets, eliminating the geometric source of "an extra node in the middle of the curve" at the root.
- **[Remove the midpoint debug emphasis]**: The `DEBUG` overlay also no longer separately renders that middle anchor, avoiding the visual impression that "there's a control node in the middle of the curve".
- **[Keep ARC FLOW's effective boundary]**: After the fix, `ARC FLOW` still affects the path's front/back phase, but no longer expresses it via an explicit join.

### 📁 Additional Files Modified
- `experiments/CursorMotion/Sources/CursorMotion/CursorMotionModel.swift`
- `experiments/CursorMotion/Sources/CursorMotion/CursorLabRootView.swift`
- `docs/exec-plans/active/20260418-standalone-cursor-lab.md`

### 🔁 Follow-up (2026-04-20, apply spring semantics from slider investigation)
**Scope:** `experiments/CursorMotion/`, `docs/`

**Key Actions:**
- **[Pull SPRING back to the official center setting]**: The `SPRING` slider no longer uses the previous mapping where "dragging it higher actually settled faster"; it now uses a centered remap around the official `response=1.4 / damping=0.9`, returning exactly `.official` at `spring=0.5`.
- **[Keep timing determined only by spring]**: This time no new distance-driven duration layer was introduced; `travelDuration` continues to be taken directly from the spring's endpoint-lock time, staying consistent with the current reverse-engineering boundary.
- **[Settle the semantics as left-fast, right-slow]**: The current setting is now stable as "left is faster and snappier, right is slower and steadier". Sampled: `spring=0.25 / 0.5 / 0.75` correspond to endpoint-locks of about `1.0958s / 1.4292s / 1.8750s` respectively.
- **[Add default-setting verification]**: Additionally verified that at `spring=0.5`, `progressSpringConfiguration == .official`, so the default setting continues to hit the official `343/240` endpoint-lock fast path exactly, rather than only computing an approximation.

### 📁 Additional Files Modified
- `experiments/CursorMotion/Sources/CursorMotion/CursorMotionModel.swift`
- `experiments/CursorMotion/README.md`
- `docs/exec-plans/active/20260418-standalone-cursor-lab.md`

### 🔁 Follow-up (2026-04-20, apply arc-flow semantics from slider investigation)
**Scope:** `experiments/CursorMotion/`, `docs/`

**Key Actions:**
- **[Clarify that ARC FLOW doesn't change arc magnitude]**: `ARC FLOW` is now explicitly settled as "the widest arc segment's front/back phase position along the main axis", no longer conflated with `ARC SIZE` as the same "curvature amount" knob.
- **[First wire ARC FLOW to an explicit mid-anchor]**: In the first round of implementation, the heading-driven path builder briefly switched the `turn / brake / orbit` families to an explicit-mid-anchor two-segment curve, letting `ARC FLOW` move the arc's apex forward/back more directly.
- **[Keep the local geometric semantics of start/end handle and arc size]**: This did not roll back the already-confirmed semantics of `START/END HANDLE` and `ARC SIZE`; instead, `ARC FLOW`'s control over the apex phase was layered on top of them.
- **[Subsequently pulled back to a single-segment cubic]**: After the user confirmed the explicit mid-anchor made the curve read as "an extra point in the middle", `ARC FLOW` was pulled back to a single-segment cubic's front/back phase offset; it still retains phase control, but no longer implements it via a visible join.

### 📁 Additional Files Modified
- `experiments/CursorMotion/Sources/CursorMotion/CursorMotionModel.swift`
- `experiments/CursorMotion/README.md`
- `docs/exec-plans/active/20260418-standalone-cursor-lab.md`

### 🔁 Follow-up (2026-04-20, align default move speed with official endpoint-lock timing)
**Scope:** `experiments/CursorMotion/`, `docs/`

**Key Actions:**
- **[Remove distance-driven duration compression]**: `CursorMotion`'s default move no longer compresses wall-clock duration based on path length using a local empirical formula, avoiding medium-to-long-distance moves being noticeably faster than official.
- **[Align the default setting with the official 1.429s timeline]**: Based on the latest reverse-engineering-confirmed `343 / 240 = 1.4291667s` endpoint-lock time, the default `response=1.4 / damping=0.9` setting is aligned directly to the official spring timeline.
- **[Keep the spring slider but tighten its semantics]**: The `SPRING` slider continues to change only the progress spring's response / damping and the corresponding settle time, no longer layering on an independent distance-based duration fudge factor.
- **[Sync doc wording]**: The README and active plan now both explicitly state the official endpoint-lock duration for the default setting, avoiding continuing to describe move speed as an unstable, locally calibrated result.

### 📁 Additional Files Modified
- `experiments/CursorMotion/Sources/CursorMotion/CursorMotionModel.swift`
- `experiments/CursorMotion/README.md`
- `docs/exec-plans/active/20260418-standalone-cursor-lab.md`

### 🔁 Follow-up (2026-04-20, simplify slider panel styling)
**Scope:** `experiments/CursorMotion/`, `docs/`

**Key Actions:**
- **[Remove extra top-left text]**: Remove `REPLAY`, `RESET`, the heading-driven title, and candidate metrics from the slider panel entirely, keeping only the 5 tuning sliders.
- **[Pull back to the current color scheme]**: Panel text is changed from low-contrast white back to dark, and the slider accent is switched from a pink-leaning highlight back to the lab's current neutral gray-purple palette.
- **[Sync the docs]**: The README and active plan no longer describe the top-left panel as an observation panel with `REPLAY`; it's now explicitly described as a pure slider-tuning entry point.

### 📁 Additional Files Modified
- `experiments/CursorMotion/Sources/CursorMotion/CursorLabRootView.swift`
- `experiments/CursorMotion/README.md`
- `docs/exec-plans/active/20260418-standalone-cursor-lab.md`

### 🔁 Follow-up (2026-04-20, preserve cursor state on resize)
**Scope:** `experiments/CursorMotion/`, `docs/`

**Key Actions:**
- **[Fix resize snap-back]**: When the window size changes, `configure(...)+snap(to: start)` is no longer re-invoked; now only the canvas bounds are updated, avoiding the cursor being forcibly pulled back to the start point due to a resize.
- **[Remove the incorrect resize clamp]**: The top-left slider panel's and canvas's resize flow no longer incidentally rewrites the `start/end` coordinates, avoiding a window-size change unexpectedly overwriting the current session state.
- **[Sync the record]**: The active plan is updated with this resize bugfix, making explicit that "resizing the window should not change the current cursor position" has been closed out.

### 📁 Additional Files Modified
- `experiments/CursorMotion/Sources/CursorMotion/CursorLabRootView.swift`
- `docs/exec-plans/active/20260418-standalone-cursor-lab.md`

### 🔁 Follow-up (2026-04-20, preserve live path origin while tuning sliders)
**Scope:** `experiments/CursorMotion/`, `docs/`

**Key Actions:**
- **[Fix slider-tuning snap-back]**: When `motionParameters` changes, the outer `@State start/end` is no longer fed back into `updateParameters`; the current session's debug curve is now rebuilt from the reference origin of the most recent real move and `queuedTarget`, avoiding the curve's start point occasionally snapping back to the initial point.
- **[Keep the current session's start heading]**: While tuning sliders, the `startRotation` recorded at the start of this move continues to be used, rather than temporarily taking the settled endpoint pose; this way the candidate chooser doesn't suddenly switch to a different start heading just because of when the tuning happened.
- **[Sync the record]**: The active plan is updated with this bugfix, making explicit that "adjusting parameters should not overwrite the current session position" has been closed out under the same principle as the earlier resize fix.

### 📁 Additional Files Modified
- `experiments/CursorMotion/Sources/CursorMotion/CursorLabRootView.swift`
- `docs/exec-plans/active/20260418-standalone-cursor-lab.md`

### 🔁 Follow-up (2026-04-20, keep debug path visible while tuning sliders)
**Scope:** `experiments/CursorMotion/`, `docs/`

**Key Actions:**
- **[Fix the DEBUG line disappearing]**: After the previous round bound slider tuning directly to `currentState.point -> queuedTarget`, it degenerated into a zero-length `target -> target` path in the settled state; now "the cursor's current point" and the "reference path" are separated, so tuning under DEBUG mode still shows full curve feedback.
- **[Keep the current cursor from snapping back]**: While tuning, the simulator is still only snapped to the current position; the cursor itself is not pulled back to the start point just because the full reference path is restored.
- **[Sync doc wording]**: Both the active plan and README are updated with this change, making it explicit that the slider's visual feedback comes from the current session path, not simply rebuilt directly from the live endpoint.

### 📁 Additional Files Modified
- `experiments/CursorMotion/Sources/CursorMotion/CursorLabRootView.swift`
- `experiments/CursorMotion/README.md`
- `docs/exec-plans/active/20260418-standalone-cursor-lab.md`

### 🔁 Follow-up (2026-04-20, simplify top-right debug controls)
**Scope:** `experiments/CursorMotion/`, `docs/`

**Key Actions:**
- **[Remove extra toggles]**: The top-right keeps only the `DEBUG` switch; the local test toggles for `MAIL` / `CLICK` have been removed, avoiding extra noise together with the top-left parameter panel.
- **[Make click pulse always-on by default]**: The click pulse continues to display following the current move state, no longer additionally controlled by a UI toggle, avoiding keeping a meaningless state branch around just because a control was removed.
- **[Widen the visual contrast of the switch]**: The `DEBUG` switch's on-state is changed to the same accent gradient as the left-side sliders, and the off-state is settled into a light-gray background with a dark knob, avoiding the two states' base colors being too close to distinguish.

### 📁 Additional Files Modified
- `experiments/CursorMotion/Sources/CursorMotion/CursorLabRootView.swift`
- `experiments/CursorMotion/README.md`
- `docs/exec-plans/active/20260418-standalone-cursor-lab.md`

### 🔁 Follow-up (2026-04-20, reduce background gradient bleed through panel cards)
**Scope:** `experiments/CursorMotion/`, `docs/`

**Key Actions:**
- **[Tighten the card background color]**: `CursorPanelBackground` no longer uses a semi-transparent light-gray gradient; it's settled into a more solid gray-white card background, reducing the underlying BG gradient from directly tinting the panel a different hue.
- **[Strengthen border legibility]**: The card's stroke and shadow are strengthened together, so the top-left slider panel stands out from the page background even when it falls over a gray-white-leaning background region.
- **[Sync doc wording]**: The README and active plan now both explicitly describe it as a "more solid gray-white card", avoiding continuing to think of the panel as a semi-transparent floating layer.

### 📁 Additional Files Modified
- `experiments/CursorMotion/Sources/CursorMotion/CursorLabRootView.swift`
- `experiments/CursorMotion/README.md`
- `docs/exec-plans/active/20260418-standalone-cursor-lab.md`

### 🔁 Follow-up (2026-04-20, align top-left and top-right panel shells)
**Scope:** `experiments/CursorMotion/`, `docs/`

**Key Actions:**
- **[Unify the panel shell]**: The top-left slider panel and the top-right `DEBUG` panel now both reuse the same `CursorPanelShell`, unifying padding, corner radius, stroke, and shadow, avoiding continuing to piece them together from two approximately-but-not-quite-consistent container styles.
- **[Consolidate duplicate wrapper code]**: The `padding + background` containers previously written separately on each side have been merged; future adjustments to the panel appearance now only need to change one place.
- **[Sync doc wording]**: The README and active plan are updated with this panel-shell alignment, making it explicit that the left and right control areas now belong to the same visual component.

### 📁 Additional Files Modified
- `experiments/CursorMotion/Sources/CursorMotion/CursorLabRootView.swift`
- `experiments/CursorMotion/README.md`
- `docs/exec-plans/active/20260418-standalone-cursor-lab.md`

### 🔁 Follow-up (2026-04-20, apply start/end handle semantics from slider investigation)
**Scope:** `experiments/CursorMotion/`, `docs/`

**Key Actions:**
- **[Tighten START HANDLE semantics]**: `START HANDLE` no longer just participates in a symmetric scaling of the global curve reach; it now primarily changes the start segment's guide line/heading mix, start reach, and start-side normal offset, letting the early trajectory more clearly express "how far to whip out first, and how long before it turns back into the main axis".
- **[Tighten END HANDLE semantics]**: `END HANDLE` is also changed to primarily act on the end guide / end reach / end-side normal, so the length of the final convergence hook and the timing of settling back onto the target can vary independently, rather than scaling proportionally together with the start segment.
- **[Loosen bounds clipping for the default sample]**: The lab's path selection no longer uses an overly tight corridor bounds; it now uses the actual canvas bounds after inset; this way, under the default sample, `END HANDLE` no longer appears to "barely react" due to premature clipping.
- **[Add verification sampling]**: In addition to `swift build --product CursorMotion`, a small script sampling was also done using the default points, confirming that `START HANDLE` and `END HANDLE` also change the early/late path samples and control geometry under small adjustments near the default setting.

### 📁 Additional Files Modified
- `experiments/CursorMotion/Sources/CursorMotion/CursorMotionModel.swift`
- `experiments/CursorMotion/Sources/CursorMotion/CursorLabRootView.swift`
- `experiments/CursorMotion/README.md`
- `docs/exec-plans/active/20260418-standalone-cursor-lab.md`

### 🔁 Follow-up (2026-04-20, rename standalone lab to Cursor Motion)
**Scope:** `Package.swift`, `README*`, `experiments/CursorMotion/`, `docs/`

**Key Actions:**
- **[Unify the standalone demo naming]**: Fully consolidate the previous `StandaloneCursorLab` under `CursorMotion`; the Swift Package product, experiment directory, entry-app name, and run command are all changed to `swift run CursorMotion`.
- **[Sync the English/Chinese README entries]**: The `Cursor Motion` section of the repo root README is now uniformly described as "an open-source cursor motion system for macOS", and explicitly supports both running from source and downloading the app from the Releases page.
- **[Sync repo knowledge]**: Remaining old names in the architecture notes, experiment README, active/completed plans, references, and history are all replaced accordingly, avoiding the docs continuing to mix in the old name.

### 📁 Additional Files Modified
- `Package.swift`
- `README.md`
- `README.zh-CN.md`
- `docs/ARCHITECTURE.md`
- `docs/exec-plans/active/20260418-standalone-cursor-lab.md`
- `docs/exec-plans/active/20260419-official-cursor-motion-reconstruction.md`
- `docs/exec-plans/active/20260420-cursor-slider-binary-investigation.md`
- `docs/exec-plans/completed/20260419-overlay-official-cursor-motion-alignment.md`
- `docs/exec-plans/completed/20260419-standalone-cursor-from-python-reconstruction.md`
- `docs/exec-plans/completed/20260419-visual-cursor-pose-dynamics-refactor.md`
- `docs/histories/2026-04/20260419-1333-add-binary-guided-cursor-motion-re-demo.md`
- `docs/histories/2026-04/20260419-2300-add-standalone-cursor-from-python-reconstruction.md`
- `docs/histories/2026-04/20260420-1151-investigate-cursor-slider-binary-mapping.md`
- `docs/references/codex-computer-use-reverse-engineering/software-cursor-motion-model.md`
- `docs/references/codex-computer-use-reverse-engineering/software-cursor-motion-reconstruction.md`
- `experiments/CursorMotion/README.md`
- `experiments/CursorMotion/Sources/CursorMotion/CursorMotionApp.swift`
- `scripts/cursor-motion-re/README.md`

### 🔁 Follow-up (2026-04-20, add tag-driven Cursor Motion DMG release)
**Scope:** `.github/workflows/release.yml`, `scripts/`, `docs/`

**Key Actions:**
- **[Add a local DMG build script]**: Add `scripts/build-cursor-motion-dmg.sh`, supporting `native` / `arm64` / `x86_64` / `universal`, which builds `Cursor Motion.app` and packages it into `CursorMotion-<version>.dmg`.
- **[Add GitHub Releases upload]**: `release.yml` adds a `release-cursor-motion-dmg` job on release-tag push, building `CursorMotion`'s universal DMG and automatically publishing it to the corresponding tag's GitHub Releases page via `gh release create/upload`.
- **[Sync release docs]**: `docs/CICD.md` and `docs/releases/RELEASE_GUIDE.md` have been updated with this distribution pipeline, the version source, and the current boundary of only doing ad-hoc codesigning.
- **[Add local verification]**: Locally verified that both `./scripts/build-cursor-motion-dmg.sh --configuration release --arch native --version 0.0.0-local` and `--arch universal --version 0.0.0-local-universal` successfully produce a `.dmg`.

### 📁 Additional Files Modified
- `.github/workflows/release.yml`
- `docs/CICD.md`
- `docs/exec-plans/active/20260418-standalone-cursor-lab.md`
- `docs/releases/RELEASE_GUIDE.md`
- `scripts/build-cursor-motion-dmg.sh`

### 🔁 Follow-up (2026-04-20, make packaged Cursor Motion match swift-run glyph quality)
**Scope:** `experiments/CursorMotion/`, `scripts/`

**Key Actions:**
- **[Locate the release-app missing-resource issue]**: Re-checked and confirmed the visual mismatch between `swift run CursorMotion` and the DMG version isn't a motion-algorithm divergence, but that the official `official-software-cursor-window-252.png` wasn't bundled into the `.app`; the release app therefore fell back to the procedural glyph, visibly more jagged and less accurately oriented than the official baseline.
- **[Add in-bundle resource loading]**: `SynthesizedCursorGlyphView` now prioritizes reading the official cursor PNG bundled into the `.app` from `Bundle.main`, only falling back to the repo's reference path in development or when the bundle resource is missing.
- **[Add DMG packaging resources and high-DPI flag]**: `build-cursor-motion-dmg.sh` now copies the official cursor PNG to `Cursor Motion.app/Contents/Resources/`, and explicitly writes `NSHighResolutionCapable=true` into `Info.plist`, avoiding silently continuing to produce a low-fidelity app.
- **[Add local verification]**: Locally rebuilt `./scripts/build-cursor-motion-dmg.sh --configuration release --arch native --version 0.1.13-glyphfix`, and confirmed that the PNG inside the `.app` matches the repo's reference image via SHA256.

### 📁 Additional Files Modified
- `experiments/CursorMotion/Sources/CursorMotion/SynthesizedCursorGlyphView.swift`
- `scripts/build-cursor-motion-dmg.sh`

### 🔁 Follow-up (2026-04-20, reuse Open Computer Use logo for packaged Cursor Motion icon)
**Scope:** `scripts/`, `docs/`

**Key Actions:**
- **[Locate the missing bundle icon]**: The user pointed out again that `Cursor Motion.app` inside the DMG still shows the generic Finder placeholder icon; confirmed this time it's not a cursor glyph resource issue, but that the `.app`'s `Info.plist` still lacks `CFBundleIconFile`, and there's also no `.icns` inside the bundle.
- **[Directly reuse the existing icon-render pipeline]**: `build-cursor-motion-dmg.sh` now directly reuses `scripts/render-open-computer-use-icon.swift` to generate `CursorMotion.icns`, having the packaged `Cursor Motion` use `Open Computer Use`'s existing logo for now.
- **[Add the bundle icon declaration]**: The packaging script writes `CursorMotion.icns` into `Contents/Resources/`, and adds `CFBundleIconFile=CursorMotion.icns` to `Info.plist`, so Finder / Dock reads the actual app icon.
- **[Add local verification]**: Locally rebuilt `./scripts/build-cursor-motion-dmg.sh --configuration release --arch native --version 0.1.14-iconcheck`, and confirmed both `CursorMotion.icns` and the official cursor PNG exist inside `.app/Contents/Resources/`.

### 📁 Additional Files Modified
- `docs/exec-plans/active/20260418-standalone-cursor-lab.md`
- `scripts/build-cursor-motion-dmg.sh`
