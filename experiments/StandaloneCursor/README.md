# Standalone Cursor

This directory carries a new standalone-cursor demo track. The goal is not to keep piling on a parameter-tuning UI, but to port the reconstruction results already converged on in `scripts/cursor-motion-re/official_cursor_motion.py` directly into a runnable Swift app.

## Scope boundaries

- Directly reuse the geometry and timing core already confirmed in the Python script:
  - `2` base candidates + `3 x 3 x 2` arched candidates
  - `sample(progress)` and `measure(...)`
  - `prefer in-bounds, then lowest score`
  - the raw spring timeline with `response=1.4`, `dampingFraction=0.9`, `dt=1/240`
- Deliberately does not introduce the wall-clock duration mapping that hasn't been recovered yet.
- Deliberately does not reuse the more experimental visual dynamics / knob-tuning structure from `CursorMotion`.

## How to run

```bash
swift run StandaloneCursor
```

## Current interaction

- Drag the `START` / `END` handles to recompute the `20` candidate paths in real time.
- The right-hand panel lists every candidate along with score, length, turn count, and in-bounds status.
- By default it auto-selects a path using the same strategy as the Python script; you can also manually lock in a specific candidate.
- `Replay` replays the currently selected path along the raw spring timeline.

## Use cases

- Seeing how the actual trajectory and timing behave once the Python reconstruction logic is ported to Swift.
- Quickly checking the candidate-path pool, scores, and endpoint lock / close-enough timing, without continuing to tune visual feel.
- Comparing against `CursorMotion` to distinguish a "script-level binary lift" from a "freer experimental demo."
