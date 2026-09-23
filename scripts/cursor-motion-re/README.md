# Cursor Motion RE Scripts

This directory holds standalone scripts related to reverse-engineering the official `Codex Computer Use.app` cursor motion. It doesn't depend on `CursorMotion`, and isn't wired into the main runtime.

The current scripts focus on two things:

- Extracting motion-related Swift types, fields, and constants from the officially bundled `SkyComputerUseService`.
- Based on the already binary-confirmed `CursorMotionPath.sample(progress)`, `CursorMotionPathMeasurement`, the `CursorMotionPath`/`Segment` layout, the `0x10005fd98` candidate geometry, and the already-established `SpringAnimation -> VelocityVerletSimulation` timing evidence, outputting a version of binary-lifted candidate paths and analysis results.

## Files

- `official_cursor_motion.py`
  - The reverse-engineering helper module, containing minimal Mach-O section parsing, Swift field-metadata recovery, constant-table reading, and a standalone path / measurement / candidate demo implementation.
- `reconstruct_cursor_motion.py`
  - The CLI entry point.

## Usage

View the motion types, fields, constants, and candidate coefficient tables recovered from the official binary:

```bash
python3 scripts/cursor-motion-re/reconstruct_cursor_motion.py inspect
```

Generate candidate paths for a given start/end point and output JSON:

```bash
python3 scripts/cursor-motion-re/reconstruct_cursor_motion.py demo \
  --start 100 120 \
  --end 720 380 \
  --bounds 0 0 1280 800 \
  --samples 32 \
  --pretty
```

Without `--bounds`, `stays_in_bounds` degrades to `true`, and only the geometric quantities are computed.

To dump the full path and samples for every candidate at once, add:

```bash
python3 scripts/cursor-motion-re/reconstruct_cursor_motion.py demo \
  --start 100 120 \
  --end 720 380 \
  --bounds 0 0 1280 800 \
  --samples 32 \
  --include-all-candidates \
  --pretty
```

Analyze whether the 5 sliders seen in the video still have direct evidence in the shipping bundle, and output a sensitivity analysis of them against the currently binary-confirmed geometry / spring quantities:

```bash
python3 scripts/cursor-motion-re/reconstruct_cursor_motion.py slider-study \
  --start 220 440 \
  --end 860 260 \
  --bounds 0 0 1120 760 \
  --pretty
```

## Output Notes

- `inspect`:
  - Outputs the motion-related types and fields recovered from the official binary.
  - Outputs the data-section constants, candidate coefficient tables extracted from the current version of the bundled app, and the scoring / layout / piecewise geometry constants confirmed directly from disassembly.
  - Additionally outputs binary-confirmed timing evidence: the field relationships of `CloseEnoughConfiguration` / `CursorNextInteractionTiming` / `SpringParameters` / `AnimationDescriptor` / `Transaction` / `VelocityVerletSimulation.Configuration`, as well as the cursor path animation's `response=1.4`, `dampingFraction=0.9`, `dt=1/240`, `idleVelocityThreshold=28800`.
  - `VelocityVerlet`'s `stiffness` / `drag` formulas and the single-step `VelocityVerlet` update order are now transcribed directly from the binary.
  - Also includes the `0x1005761bc` / `0x1005934b0` finish-predicate evidence block, making clear which parts are confirmed control flow and which are still just field-naming inference.
- `demo`:
  - Outputs `candidate_summaries` and `chosen_candidate` by default, avoiding printing every candidate's full sample points at once.
  - `--include-all-candidates` additionally outputs the full control points, measurement, and sample points for every candidate.
  - `sample(progress)` and `measure_path()` are implementations lifted directly from the function control flow.
  - The candidate score, in-bounds priority strategy, `CursorMotionPath`/`Segment` layout, and the 20 candidate geometries have all been transcribed directly from the currently bundled binary.
  - The timeline output additionally flags `raw_progress_first_ge_target_*`, `first_endpoint_lock_*`, and `close_enough_first_*`, to help compare spring progress, visible endpoint lock, and the close-enough determination.
  - What's still not fully recovered is the duration / wall-clock timing, the precise semantic naming of a few generic buffers in the second section of `0x1005934b0`, and the runtime bounds auto-discovery layer that happens before the call.
  - `first_endpoint_lock_*` depends on one confirmed premise: `sample(progress)` clamps to `0...1`; but its final linkage with `SpringAnimation`'s finished optional-return is still labeled as "inference stitched together from multiple confirmed evidence fragments."
  - The currently output `speed_units_per_progress` is a geometric speed, not a time-based speed with real duration; duration is still being reverse-engineered.
- `slider-study`:
  - First scans the shipping bundle to confirm whether the full phrases `START HANDLE` / `END HANDLE` / `ARC SIZE` / `ARC FLOW` still exist.
  - Then maps these 5 knobs respectively onto the currently binary-confirmed `startControl` / `endControl` / `arc*` / `SpringParameters`-related quantities, and outputs the baseline and perturbed changes in the chosen candidate / best arched candidate / endpoint-lock timing.
  - The output clearly distinguishes "release bundle phrase evidence" from "slider-mapping inference based on binary-confirmed geometry."
