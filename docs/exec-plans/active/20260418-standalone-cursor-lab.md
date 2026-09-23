# Cursor Motion

## Goal

Land an independent directory in the current repo, decoupled from the main `OpenComputerUseKit`, implementing a tunable software cursor motion demo in Swift, used to approximate the feel seen in the official videos, and to prepare for a later separate open-source release.

## Scope

- Included:
- Create a new independent directory to hold the cursor motion experiment, without directly polluting the main MCP runtime.
- Split the motion model into a parameter layer, a path layer, a time-simulation layer, and a render layer.
- Build a locally runnable demo, supporting at minimum start/end points, path preview, parameter sliders, and click-to-trigger.
- Capture this round's reverse-engineering findings into `docs/references/`.
- Not included:
- This round does not require wiring into the real `click` tool.
- This round does not require fully replicating the official closed-source material.
- This round does not require publishing the demo as a standalone repo immediately.

## Background

- The user provided X video samples, which clearly show `START HANDLE`, `END HANDLE`, `ARC SIZE`, `ARC FLOW`, `SPRING` tuning parameters.
- The `SkyComputerUseService` strings already show evidence of `BezierParameters`, `SpringParameters`, `arcHeight`, `arcIn`, `arcOut`, `cursorMotionProgressAnimation`.
- The repo already has `SoftwareCursorOverlay.swift`, but it is more of an approximate in-product implementation, and is not well suited to continuing to carry a large amount of parameter tuning and experimental UI.

## Risks

- Risk: sinking experimental code into the main package too early, causing the mainline overlay behavior to keep fluctuating.
- Mitigation: keep it in an independent directory first, and extract shared modules only once it stabilizes.
- Risk: tuning purely from video could mistake "looks visually right" for "structurally correct."
- Mitigation: prioritize modeling around already-confirmed field names, avoiding purely made-up parameter naming.
- Risk: unclear boundary between the demo UI and a future standalone open-source release.
- Mitigation: in the first phase, build only a minimal runnable lab, avoiding introducing MCP/tool-related coupling prematurely.

## Milestones

1. Establish an independent directory and README, clarifying module boundaries.
2. Implement pure parameterized path generation and visualization.
3. Add spring/timing simulation.
4. In the independent lab, complete a version of the official-style path/pose model rebuilt from the latest reverse-engineering results.

## Verification

- Able to run the local demo independently.
- Able to change trajectory geometry and dwell feel in real time via sliders.
- Repo docs can explain the boundary between this directory and the main product code.

## Progress Log

- [x] Milestone 1
- [x] Milestone 2
- [x] Milestone 3
- [x] Milestone 4

## Latest Progress

- 2026-04-18: Added click-anywhere-to-trigger candidate path preview, no longer limited to replay.
- 2026-04-18: Fixed the click-capture coordinate system and event-coverage issue; the bottom area no longer has a hidden dead zone caused by an extra excluded rectangle.
- 2026-04-18: Changed the `DEBUG` toggle's on-state to be clearly highlighted, and changed the controls to a minimal overlay layout, avoiding a transparent container blocking clicks on the canvas.
- 2026-04-18: Upgraded the path model to a "line direction + cursor heading" hybrid constraint, and added `turn` / `brake` candidate families; the selected main path now shows a clearer tendency to first follow the head direction, then bite back toward the target.
- 2026-04-18: Changed timing from spring + `easeInOut` to a minimum-jerk bell-shaped profile, and removed the position layer's end overshoot; the cursor continuously follows the tangent heading during motion, then smoothly straightens out on arrival.
- 2026-04-19: Built a curvature/heading-change-weighted effort lookup for the path, so progress advancement is no longer directly tied to the Bezier parameter `t`, making high-curvature turn segments slower and straight segments faster.
- 2026-04-19: Switched the standalone lab's cursor to a resource-based PNG asset, and changed to tip-anchor-driven hit-point alignment; the resting pose and the moving pose share one heading calibration, continuously facing the current tangent direction during motion.
- 2026-04-19: Added a new candidate path family leaning more toward a "launch/whip" feel, and introduced a path quality score, explicitly measuring starting-heading fit, early-segment turn strength, end-segment tangent alignment, and terminal straightness.
- 2026-04-19: Split timing edge weighting into start/end sides, separately weighting the starting whip-around and the end-segment braking phase, making the speed distribution closer to the "whip first, settle later" rhythm seen in the official videos.
- 2026-04-19: Rebuilt the lab from a speculative-slider-driven curve/settle model into a recovered `20`-candidate path + official-style spring progress + independent visual dynamics; the settle phase no longer relies on the endpoint locking and then rotating in place.
- 2026-04-19: After comparing against the official video, found that the guide/arc-related constants cannot be used directly as screen-coordinate vectors; changed to first project into a local basis from start→end, then generate candidate paths — the default sample and the reverse diagonal case no longer show a knot-like distortion loop near the start point.
- 2026-04-19: After continuing to compare against the official video, confirmed the lab mainline cannot directly use the raw reverse-engineered `20` candidates as the chooser; changed to heading-driven path selection, factoring both the currently visible heading and the final resting pose into path choice — the main path now re-converges onto the distribution of "take a one-sided C-shape when a turn is needed, near-straight when it isn't."
- 2026-04-20: After comparing `scripts/render-synthesized-software-cursor.swift` against the user's screenshots, confirmed the previous bright-white asset style was wrong; changed the lab to prioritize the official `252x252` runtime baseline image checked into the repo, with the same script's procedural pointer/fog as fallback, and tightened idle from XY drift to a small centered rocking angle.
- 2026-04-20: Per user feedback, briefly separated "internal heading" from "visible arrow angle" and tightened the visible arrow during the moving phase to a slight lean; this assumption was subsequently retracted after comparing against official frame extracts.
- 2026-04-20: Per user feedback, restored the 5 sliders in the top-left corner, and reconnected them to the heading-driven path geometry and progress spring; the sliders are now explicitly only a local tuning entry point, not a claim of fully confirmed official field mapping.
- 2026-04-20: Continuing per user feedback, trimmed the top-left control area down to pure sliders, and pulled the slider label/panel accent back to the current neutral gray-purple palette; no longer keeping the `REPLAY` / `RESET` buttons or extra metrics copy, avoiding information noise and low-contrast white text.
- 2026-04-20: Fixed a state-reset bug on window resize; `proxy.size` changes now only update the canvas bounds, no longer re-running `configure + snap(to: start)`, so resizing the window no longer forcibly pulls the cursor back to the start point.
- 2026-04-20: Based on a new round of timing reverse-engineering on `Codex Computer Use.app`, confirmed the default move's wall-clock endpoint-lock is fixed at `343 / 240 = 1.4291667s`; the lab has now removed the distance-driven travel-duration compression — the default tier follows the official spring timeline directly, and the `SPRING` slider now only changes the spring's own response/damping and the corresponding duration.
- 2026-04-20: After comparing against official video frame extracts provided by the user, confirmed the visible arrow during the moving phase does continuously follow the current move heading, rather than only keeping a slight lean; the lab has now retracted that `displayRotation` separation layer, and glyph rendering again directly uses the visual dynamics' main `rotation`.
- 2026-04-20: After continuing to compare `official-software-cursor-window-252.png` against the standalone script's resting orientation, confirmed the extra `-26.5°` glyph compensation the lab previously added was causing the moving heading to be consistently off; the resting baseline is now converged to match the main runtime — "zero rotation means facing top-left," i.e. `-3π/4` in a y-down canvas.
- 2026-04-20: While continuing to investigate the "tail leading" issue, confirmed the real problem is that the lab's motion/heading runs in SwiftUI's y-down coordinates, but glyph rendering lands in AppKit's default y-up `NSView`; the glyph render layer now uniformly applies a y-down -> y-up conversion to angle, body offset, and fog offset, avoiding the moving pose being vertically mirrored.
- 2026-04-20: Pulled the just-confirmed slider semantics further back onto the `CursorMotion` mainline; `START HANDLE` now primarily adjusts the starting segment's guide/reach/normal, `END HANDLE` primarily adjusts the ending segment's guide/reach/normal, no longer just applying symmetric scaling to the entire curve. Also removed overly tight corridor clipping in favor of inset canvas bounds, avoiding `END HANDLE` being clipped away prematurely in the default sample.
- 2026-04-20: Continuing with the same approach, tightened `ARC SIZE`; it now clearly represents trajectory arc curvature rather than cursor size, and is now wired into both the local path's arc height/control-point lateral offset and the chooser's preference between the `direct` and `arched` families. Under default sample points, `arcSize=0.04 -> 0.12` raises `curveScale` from about `10.3` to `47.7`, and the midpoint `y` also rises from about `326.8` to `345.5`.
- 2026-04-20: Continuing to tighten `ARC FLOW`; it now clearly represents "whether the widest arc segment sits further forward or further back along the chord" — implementation-wise it no longer just changes an abstract bias on start/end reach, but instead changes the fore/aft phase offset of a single cubic segment's control point.
- 2026-04-20: Continuing to tighten `SPRING`; it now clearly represents the progress spring's `response / damping` and endpoint-lock time, with the default `spring=0.5` exactly matching the official `.official` config. Under sampling, `spring=0.25 / 0.5 / 0.75` correspond respectively to endpoint-locks of about `1.0958s / 1.4292s / 1.8750s`, and the semantics have converged into a stable "fast on the left, slow on the right."
- 2026-04-20: Fixed the mid-segment "joint feel" introduced by the first `ARC FLOW` implementation; the problem wasn't in `SPRING`, but in that version's explicit mid-anchor two-segment curve creating a real join in the path, which the debug overlay then emphasized further. This has now been pulled back to a single cubic segment — phase control is retained, but geometrically there is no longer a mid join.
- 2026-04-20: Continuing to fix the slider-tuning state flow; "current cursor position" and "the current session's reference path" are now decoupled — when recalculating from a slider change, the entire debug curve is rebuilt from the most recent real move's origin/startRotation + `queuedTarget`, while only the cursor itself is snapped to its current position, so tuning after settling no longer rebuilds the DEBUG line into a zero-length `target -> target` path.
- 2026-04-20: Continuing to tighten the top-right controls; only the `DEBUG` switch remains, `MAIL` / `CLICK` have been removed, click pulse defaults to always-on, and the switch's on/off background color has been pulled apart into the same high-contrast semantics as the left-side sliders.
- 2026-04-20: Continuing to tighten the left/right panel container styling; the top-left slider panel and the top-right `DEBUG` panel now share one unified card shell, no longer separately maintaining different padding/frame wrapping.
- 2026-04-20: Continuing to fix panel legibility against a light background; the card fill is now a more solid gray-white base, with stronger stroke and shadow, reducing the "looks like a different background color" problem caused by the background gradient showing through the panel directly.
- 2026-04-20: Unified the standalone demo's public naming to `Cursor Motion` / `CursorMotion`; the Swift Package product, the experiment directory, the README entry point, and related docs now all standardize on `swift run CursorMotion`, no longer retaining the old `StandaloneCursorLab` name.
- 2026-04-20: Added a tag-driven `Cursor Motion` distribution pipeline; locally, a DMG can be built via `scripts/build-cursor-motion-dmg.sh`, and GitHub Actions automatically generates `CursorMotion-<version>.dmg` and uploads it to GitHub Releases after a release tag is pushed.
- 2026-04-20: Continuing to fix the "packaged build and `swift run CursorMotion` look inconsistent" issue; confirmed the release app previously did not bundle the official `252x252` baseline cursor PNG, causing it to fall back to the procedural glyph. Now the `.app` prioritizes reading the official cursor image from `Bundle.main`, the DMG packaging script also copies this image into `Contents/Resources`, and explicitly turns on `NSHighResolutionCapable`.
- 2026-04-20: Continuing to fix the packaged `Cursor Motion`'s app icon asset chain; now converged onto the checked-in `1024x1024` master PNG in the repo, generating `CursorMotion.icns` via `sips + iconutil` during the DMG packaging step, avoiding continuing to couple Dock optical-size tuning into an ad hoc icon-render script.

## Decision Log

- 2026-04-18: Defined this work as a standalone lab up front, rather than continuing to pile directly into `OpenComputerUseKit`.
- 2026-04-18: Parameter naming prioritizes the intersection of the video UI and the official strings: `start/end handle`, `arc size/flow`, `spring`.
- 2026-04-18: The first demo version first uses an independent SwiftUI target + `CVDisplayLink`-driven simulation, prioritizing verifying parameter semantics and trajectory feel before considering merging with the main overlay.
- 2026-04-19: After obtaining a more complete binary-backed path and visual-layer implementation, changed the lab to directly demonstrate the recovered structure, no longer treating unconfirmed slider semantics as the main implementation.
- 2026-04-19: For the guide coefficients recovered from `swift_once`, the current default implementation strategy is "the constants are confirmed, the world-coordinate interpretation does not hold, a local-basis projection is a closer fit to the official video"; if stronger binary-level evidence is obtained later, this interpretation layer will continue to be revisited.
- 2026-04-19: The raw binary-lift `20`-candidate pool remains on the `StandaloneCursor` analysis track; `CursorMotion` and the main runtime overlay are both unified onto the heading-driven mainline, with the implementation prioritizing "heading constraint + one-sided turning" as the structural behavior closer to the official video.
- 2026-04-20: When restoring the slider UI, continued to describe "the tuning entry point" and "the binary-confirmed structure" separately; the lab can expose `start/end handle`, `arc size/flow`, `spring` as testing knobs, but neither the docs nor the code claim they are a one-to-one match to official fields.
- 2026-04-20: For the `start/end handle` knobs, the current experimental line adopts the strategy of "acting on the local start/end control geometry, not a global uniform scale"; this is closer to the boundary between `startControl/endControl` and `startExtent/endExtent` in the binary lift.
- 2026-04-20: For `ARC SIZE`, the current experimental line adopts the strategy of "acting on the local arc height / normal bias / family chooser, not the cursor glyph size"; this is closer to how `handleExtent / arcExtent / tableA / tableB` bound curve width in the binary lift.
- 2026-04-20: For `ARC FLOW`, the current experimental line adopts the strategy of "acting on the fore/aft phase of a single cubic segment's control point, not merely an abstract reach bias"; this is closer to the reverse-engineered boundary of "the widest arc segment is pushed forward/backward along the guide direction."
- 2026-04-20: For `SPRING`, the current experimental line adopts the strategy of "a centered response/damping remap around the official `.official`, rather than layering on an additional distance-based duration layer"; this is closer to the current binary-backed evidence's boundary of "the main chain directly consumes the `1.4 / 0.9` spring config."
- 2026-04-20: When adjusting the top-left sliders, path reconstruction is now uniformly based on the current session's most recent move's reference origin/startRotation/`queuedTarget`, rather than the outer `@State start/end` or the live endpoint after settling; this way parameter adjustment neither mistakenly pulls the curve start back to the initial position, nor collapses the DEBUG feedback line to zero length.
- 2026-04-20: For the external delivery of `Cursor Motion`, the current strategy adopted is "run from source + distribute an ad-hoc signed DMG via GitHub Releases"; stabilize the tag-driven reproducible packaging pipeline first, without prematurely introducing notarization and Developer ID signing complexity in this round.
- 2026-04-20: For the packaged `Cursor Motion`'s glyph resource, the current strategy adopted is "prioritize the official baseline image inside the bundle, fall back to the repo reference path"; this way the release app no longer silently falls back to the low-fidelity procedural glyph due to a missing resource.
- 2026-04-20: For the packaged `Cursor Motion`'s app icon, the current strategy adopted is "directly reuse `Open Computer Use`'s existing `.icns` render script for now"; fix the no-icon issue in Finder/DMG first, and design a dedicated icon separately later if needed.
