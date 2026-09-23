# Cursor Motion

This directory implements a software cursor-motion demo that can evolve independently and may later be open-sourced on its own.

The current goal is not to replace the main repo's `SoftwareCursorOverlay`, but to first pull "trajectory geometry + timing elasticity + candidate-path visualization" out of the main product code and turn it into a video lab better suited for experimentation and comparison.

## Why it lives here separately

- The main-line `packages/OpenComputerUseKit/.../SoftwareCursorOverlay.swift` already carries product behavior and isn't a good place to keep piling on experimental code.
- Both user-provided videos and official strings indicate cursor motion has its own independent parameter model, which is well suited to a dedicated lab first.
- This may later be open-sourced separately, so keeping it cleanly bounded to its own directory now pays off.

## Current module boundaries

- `Sources/CursorMotionModel.swift`
  - The heading-driven `direct`/`turn`/`brake`/`orbit` candidate families
  - Official-style `VelocityVerlet` spring progress
  - Independent visual dynamics, driving pose via visible tip/velocity/angle/fog
- `Sources/CursorLabRootView.swift`
  - The local demo UI, slider tuning panel, candidate-path overlay, and click interaction
- `Sources/SynthesizedCursorGlyphView.swift`
  - A baseline/procedural cursor renderer based on `scripts/render-synthesized-software-cursor.swift`

## Current references

- `docs/references/codex-computer-use-reverse-engineering/software-cursor-overlay.md`
- `docs/references/codex-computer-use-reverse-engineering/software-cursor-motion-model.md`
- `docs/exec-plans/active/20260418-standalone-cursor-lab.md`

## Current status

There is currently a runnable SwiftUI demo target:

```bash
swift run CursorMotion
```

At this stage it supports:

- Clicking anywhere on the canvas first previews the current heading-driven candidate family, then automatically picks a path and drives the cursor along it.
- The top-left keeps 5 sliders — `START HANDLE`, `END HANDLE`, `ARC SIZE`, `ARC FLOW`, `SPRING` — and the panel itself no longer carries `REPLAY`/`RESET` buttons or extra metric text, making it easier to compare the current trajectory and visual feel directly.
- The top-right now keeps only a single `DEBUG` switch; `MAIL`/`CLICK` have been removed, and the click pulse now always follows the current move state by default, no longer exposed as a separate test toggle.
- The panels in the two corners are now unified into the same, more solid gray-white card container: same padding, corner radius, stroke, and shadow, and the amount of underlying background gradient showing through has been reduced, avoiding blurry card edges in lighter areas.
- Adjusting a slider recomputes the whole reference path for the current session while keeping the cursor body parked at its current position; so with `DEBUG` on, dragging a slider after settling still shows full curve feedback instead of degenerating into a zero-length path.
- `START HANDLE` now primarily changes the guide/reach/normal bias of the starting segment, and `END HANDLE` primarily changes the guide/reach/normal bias of the closing segment; the two no longer just scale the whole curve together.
- `ARC SIZE` now explicitly represents the trajectory's arc itself, not the cursor glyph's size; it changes both the arc height/control-point lateral offset and the chooser's preference between straighter paths and wider arced paths.
- `ARC FLOW` now explicitly represents "whether the widest part of the arc sits further forward or further back along the start→end main axis"; it doesn't make the arc bigger, but instead primarily changes the forward/backward phase bias of the single cubic control point.
- `SPRING` now explicitly represents the speed and damping of the progress spring itself, with no extra distance-based duration fudge stacked on top; the `0.5` position lands exactly on the official `response=1.4`, `damping=0.9`, `343/240` endpoint-lock time, faster to the left and slower to the right.
- The debug overlay shows control points, the arc handle, and the currently selected candidate id/score.
- With `DEBUG` off, no trajectory line or target point is shown — only the cursor body itself — to make it easier to observe the final motion feel in isolation.
- The `DEBUG` switch's on-state now directly reuses the accent gradient from the sliders on the left, while its off-state collapses to a light gray fill, avoiding the two states' background colors being too close to tell apart at a glance.
- The lab's main line no longer directly reuses the raw binary-lifted set of `20` candidates + scores; it now uses a heading-driven chooser constrained by reverse-engineering, feeding the starting heading and final resting pose together into the path selector, so the default curve converges more stably to a one-sided C-shape or a near-straight line.
- The main path's progress no longer uses a speculative `easeInOut` or terminal settle; it now directly reuses the official-style spring progress.
- The default wall-clock move duration is now directly aligned with the reverse-engineered official endpoint-lock time of `343 / 240 = 1.4291667s`; duration is no longer additionally compressed based on path distance.
- The visible cursor no longer sits directly on the path sample; it now passes through an independent visual-dynamics state, which outputs `rotation + cursorBodyOffset + fogOffset + fogScale`.
- Candidate paths are now explicitly constrained to "first turn to face the direction of travel, then advance along the main axis, then finish into the resting pose"; so most cross-direction moves render as a one-sided C-shape, degenerating to a near-straight line only when a direct cut-through is needed, and no longer show the chaotic two-sided S-shape distortion.
- The arrow's visible angle is now realigned with the official frame-extraction and reverse-engineering evidence: it continuously follows the current move heading during the moving phase, then smoothly returns to the default resting pose once nearly stopped, continuing to do a small in-place wobble.
- The cursor glyph no longer uses the earlier bright-white asset; it now prefers displaying the official `252x252` runtime baseline image bundled in the repo, falling back to the same procedural pointer/fog as the script only when that image is missing.
- The settle state no longer drifts in XY; it now matches the reference script with a fixed-center small wobble, so the "settles, then rotates slightly in place" feel is aligned first.

Future implementation work should prioritize keeping:

- Never dress up unverified slider parameter semantics as "the official implementation."
- Sliders can remain as a local tuning entry point, but must be clearly documented as tuning knobs for the heading-driven lab, not a binary-confirmed one-to-one field mapping.
- To avoid `END HANDLE` being clipped prematurely by overly tight corridor bounds in the default sample, the lab now does path selection and control clipping directly against the actual inset canvas bounds.
- The current implementation boundary of `ARC SIZE` is "the arc height and arched-family tendency of the local heading-driven path"; it does not tune the cursor asset's size, and it does not claim to map one-to-one to the release binary's `tableA`/`tableB`/`arcExtent`.
- The current implementation boundary of `ARC FLOW` is "the forward/backward phase bias of the single cubic segment"; it's closer to a geometric forward/backward bias like `arcAnchorBias` in the reverse-engineering notes, and it does not claim to correspond one-to-one to some separate `flow` field inside the release binary.
- The current implementation boundary of `SPRING` is "a centered spring remap around the official `1.4 / 0.9`"; it directly changes the progress spring's `response`/`damping` and the endpoint-lock time, but does not claim to have recovered the exact remap helper behind the release app's internal debug slider.
- Keep the path layer, progress layer, and visible-pose layer separate.
- In scenarios with no real target window, clearly distinguish `StandaloneCursor`'s raw reverse-engineered pool from `CursorMotion`'s heading-driven main-line implementation.
- The demo host can be swapped out, but the motion model and visual dynamics should remain independently reusable.
