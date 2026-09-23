# Software Cursor Motion Reconstruction

This document is narrower in scope than `software-cursor-motion-model.md`. It specifically records the implementation details that have now been confirmed directly from the `SkyComputerUseService` control flow after pushing the analysis further to the function level, as well as which parts are still only reconstruction.

## Summary of Findings

The 4 most valuable findings from this round are:

- `CursorMotionPath.sample(progress)` has now been reconstructed at essentially the function level.
- The 5 output fields of `CursorMotionPathMeasurement` can now be mapped to the sampling loop and angle-accumulation logic.
- The real field layout of `CursorMotionPath` / `Segment` can now be matched one-to-one against the field-write instructions.
- Candidate path filtering is no longer just a guess at "there's probably a set of weights" — the score formula, the in-bounds-first strategy, and the geometric generation shape of the 20 candidates can now all be confirmed.

After pushing further into the timing side this round, 4 more findings that can be tied directly to binary evidence were added:

- Cursor path animation is not an abstract easing black box — it's a progress-animation chain driven by `Animation.SpringAnimation`.
- The `closeEnough`-related types and field relationships can now be matched directly from Swift metadata.
- The spring path internally does resolve down to `Animation.VelocityVerletSimulation.Configuration`, and `stiffness / drag`, `dt = 1/240`, and the `VelocityVerlet` single-step update order can now all be written out directly.
- The several slots in `ComputerUseCursor.Window` that hold cursor animation state can now be matched to the field-write order in the main control flow.

## Confirmed Function-Level Behavior

### 1. `CursorMotionPath.sample(progress)` "picks a segment, then evaluates a cubic"

Function address: `0x10005c1dc`

The control flow confirms:

1. The input `progress` is first clamped to `0...1`.
2. Based on `segments.count`, the global `progress` is mapped to a specific `segmentIndex` and a local `t` within that segment.
3. If `progress >= 1`, it falls directly onto the last segment with local `t = 1`.
4. Every segment evaluates a point using the standard cubic Bezier formula:
   - start point
   - `control1`
   - `control2`
   - end point
5. At the end of the function, a helper function is also called, returning two additional scalar values; based on the call site, these look more like tangent/orientation-related data.

This shows that the official path-sampling layer isn't a black-box easing — it's standard piecewise cubic.

### 2. `CursorMotionPathMeasurement` samples at a fixed step count, not a closed-form formula

Function address: `0x100060ac0`

Behavior that can be directly confirmed:

- It iterates over `segments`.
- Each segment advances by a fixed `24` sample points.
- A small step is only counted as a valid step when the distance between adjacent points exceeds `0.01`.
- For each valid step:
  - accumulates `length`
  - computes heading via `atan2(dy, dx)`
  - unwraps adjacent headings into `[-pi, pi]`
  - accumulates the squared angle change
  - records the maximum absolute turn angle
  - accumulates the total absolute turn angle

From the registers and the final write-back order, the 5 fields can be matched up as:

- `length`
- `angleChangeEnergy`
- `maxAngleChange`
- `totalTurn`
- `staysInBounds`

### 3. `staysInBounds` is a boolean maintained along the way during the measurement phase

This isn't separate post-processing.

`0x100060ac0` continuously maintains a boolean flag inside the sampling loop, and this field only stays `true` as long as every key sample point still satisfies the boundary constraint.

The most conservative current interpretation is:

- If the caller supplies bounds, the measurement performs a containment check on each sample point individually.
- The implementation shows a fixed `20.0` margin participating in the check, so it's not a strict, bare-rectangle boundary test.

## Newly Confirmed Candidate-Selection Logic

### 0. The memory layout of `CursorMotionPath` and `Segment` is now pinned down

By combining Swift field metadata with the field-write/field-read order in `0x10005fd98` / `0x10005c1dc`, the layout of these two key structs can be matched:

- `CursorMotionPath`
  - `start`: `0x00`
  - `end`: `0x10`
  - `startControl`: `0x20`
  - `arc`: `0x30`
  - `arcIn`: `0x48`
  - `arcOut`: `0x60`
  - `endControl`: `0x78`
  - `segments`: `0x88`
- `Segment`
  - `end`: `0x00`
  - `control1`: `0x10`
  - `control2`: `0x20`

The read order for `Segment` inside `0x10005c1dc` also shows that:

- A segment's start point isn't stored separately.
- The first segment's start point comes from `CursorMotionPath.start`.
- Later segments' start points come from the previous segment's `Segment.end`.
- `Segment.end / control1 / control2` are all absolute points that participate directly in the formula during cubic sampling.

### 1. The total candidate count isn't 18 — it's 20

Function address: `0x10005fd98`

After flattening out the candidate-generation function further this round, the following can be confirmed:

- There are two coefficient tables:
  - `tableA = [0.55, 0.8, 1.05]`
  - `tableB = [0.65, 1.0, 1.35]`
- A nested loop enumerates the `3 x 3` combinations.
- Each combination then branches into a left/right mirrored pair.
- Before entering the nested loop, the function first constructs two base candidates.

So the total candidate count isn't the "around 18" from the previous, more conservative write-up — it's closer to:

- `2` base candidates
- `3 x 3 x 2 = 18` mirrored candidates
- `20` total

### 2. Candidate generation can now be traced down to field-level geometry, not just table-level guesswork

Still within `0x10005fd98`.

What can now be directly confirmed:

- A set of guide-related coefficients is initialized into a global once via `swift_once`:
  - `(-0.6946583704589973, 0.7193398003386512)`
- These numeric values themselves are confirmed; however, after cross-checking against the official video afterward, treating them directly as a fixed screen-coordinate guide vector produces noticeably wrong, twisted loops in some quadrants. The current, more conservative reconstruction treats them as a coefficient pair within a path-local basis, which is then projected into world coordinates to generate the candidate geometry. This "local-basis projection" layer is still reconstruction-level inference at this point, not a conclusion already nailed down instruction-by-instruction from the disassembly.
- The path builder first constructs two base candidates:
  - `base-full-guide`
  - `base-scaled-guide`
- It then constructs `18` two-segment cubic arched candidates built around the two coefficient tables.

The main scale factors that can be directly confirmed include:

- `distance * 0.41960295031576633`
- `distance * 0.9`
- `distance * 0.15`
- `distance * 0.2765523188064277`
- `distance * 0.5783555327868779`
- `clippedTravel * 0.65`

One earlier finding was written too roughly and needs correcting:

- `arcExtent` can still be safely written as:

```text
arcExtent = clamp(distance * 0.5783555327868779, 38, 440)
```

- But `handleExtent` is not a simple `clamp(..., 50, 520)` — it's this piecewise logic in this version of the bundled binary:

```text
rawHandle = distance * 0.2765523188064277

if rawHandle < 50:
  handleExtent = 50
else if rawHandle < 640:
  handleExtent = rawHandle
else:
  handleExtent = 520
```

Given that this guide-coefficient pair's raw storage satisfies `x < 0, y > 0`, the base candidate's guide travel can also be simplified from the original branch tree into this piecewise form:

```text
startExtent =
  48                               if distance * 0.41960295031576633 < 48
  distance * 0.41960295031576633   if distance * 0.41960295031576633 < 640
  640                              if distance * 0.15 < 640
  640                              otherwise

endExtent =
  48       if distance * 0.41960295031576633 < 48
  distance * 0.9
           if distance * 0.41960295031576633 < 640
  48       if distance * 0.15 < 640
  640      otherwise
```

After further applying bounds clipping, this yields:

- `fullStartControl = start + guide * startExtent`
- `fullEndControl = end - guide * endExtent`
- `scaledStartControl = start + guide * (startExtent * 0.65 after clipping)`
- `scaledEndControl = end - guide * (endExtent * 0.65 after clipping)`

The mirrored candidates can also now be resolved into concrete geometry:

- First, the arc anchor is computed using the midpoint, the signed normal, `tableA`, and `handleExtent`.
- Then `arcIn / arcOut` are computed using `tableB`, `arcExtent`, and a forward vector normalized from `(dx, arcExtent)`.
- Each arched candidate is two cubic segments:
  - first segment: `start -> arc`
  - second segment: `arc -> end`

### 3. The scoring formula can now be written out directly

Function address: `0x100060da0`

The most important progress this round was pulling apart how the score is composed after candidate measurement.

For each candidate path, the function first computes:

- `directDistance = max(distance(start, end), 1)`
- `excessLengthRatio = max(length / directDistance - 1, 0)`

Then the score is:

```text
score =
  320 * excessLengthRatio
  + 140 * angleChangeEnergy
  + 180 * maxAngleChange
  + 18 * totalTurn
  + (staysInBounds ? 0 : 45)
```

This shows that the official filtering logic clearly prefers:

- not being much longer than a straight line
- not having too much angular jitter
- not having any single overly sharp turn
- not accumulating too much total turning
- if a candidate goes out of bounds, a fixed penalty is added directly

### 4. The selection strategy is "keep in-bounds candidates first, then compare score"

After computing the measurement and score for every candidate, `0x100060da0` doesn't simply take the minimum over the whole batch.

It first runs a filtering pass:

- If any candidate with `staysInBounds == true` exists, the minimum score is taken only among that in-bounds subset.
- Only when there are no in-bounds candidates at all does it fall back to taking the minimum score over the whole set.

This matters a lot for the visual result, because it explains why the official path looks both "playful" and unlikely to cut through windows or go out of bounds.

## Newly Confirmed Timing / Animation Chain

### 1. `CloseEnoughConfiguration` / `CursorNextInteractionTiming` can now be resolved to real nested types

The Swift metadata now lets us directly recover this parent/child relationship:

- `ComputerUseCursor.CloseEnoughConfiguration`
  - `progressThreshold`
  - `distanceThreshold`
- `ComputerUseCursor.CursorNextInteractionTiming`
  - `closeEnough`
  - `finished`

This shows that the `1.0` and `0.01` values seen earlier aren't scattered constants — they now map to real fields:

- `progressThreshold = 1.0`
- `distanceThreshold = 0.01`

Looking at the stack-write order at `0x10005be24..0x10005be3c`, these two values are exactly the close-enough configuration used by the cursor path animation when constructing `next interaction timing`.

### 2. The real fields of `AnimationDescriptor` / `SpringParameters` / `Transaction` have also been recovered

Also via `__swift5_types` + `__swift5_fieldmd`, the following can now be confirmed:

- `Animation.AnimationDescriptor`
  - `bezier`
  - `spring`
- `Animation.SpringParameters`
  - `response`
  - `dampingFraction`
- `Animation.Transaction`
  - `priority`
  - `delay`
  - `completion`
  - `id`
  - `driverSource`
  - `descriptor`

The most important part here is:

- The spring constants used in the cursor path's main chain can now be directly confirmed as:
  - `response = 1.4`
  - `dampingFraction = 0.9`
- The binary also does in fact import
  - `SwiftUI.Animation.spring(response:dampingFraction:blendDuration:)`

So "the official cursor path animation uses a spring, not a custom bezier duration" is now a binary-backed conclusion, no longer just a string-level guess.

### 3. `SpringAnimation` resolves further down into `VelocityVerletSimulation.Configuration`

The new key chain is:

- `Animation.SpringAnimation` metadata accessor: `0x1005768c4`
- allocating wrapper: `0x100576790`
- designated init body: `0x10057652c`
- `Animation.VelocityVerletSimulation.Configuration` metadata accessor: `0x100591fd4`
- `Configuration` init main chain: `0x100592f20`
- config completion: `0x100593cfc`

This chain shows that:

- The "velocity" underlying the cursor path animation is not simple fixed-length sampling.
- It's built up further into a `VelocityVerletSimulation` via the spring parameters.

And the fields of `Animation.VelocityVerletSimulation.Configuration` can now be directly recovered as:

- `response`
- `stiffness`
- `drag`
- `dt`
- `idleVelocityThreshold`

Values and formulas that can currently be directly confirmed:

- `dt = 1/240 = 0.004166666666666667`
- `idleVelocityThreshold = 28800.0`
- `0x100593cfc`
  - `stiffness = min(response > 0 ? (2π / response)^2 : +inf, 28800.0)`
- `0x100593f18`
  - `drag = 2 * dampingFraction * sqrt(stiffness)`
- `0x100593404`
  - if `targetTime - time > 1.0`, first clamp `time` to `targetTime - 1/60`
  - then advance in a loop by `dt` until `time >= targetTime`
- `0x100594110`
  - `velocityHalf = velocity + force * (dt / 2)`
  - `current = current + velocityHalf * dt`
  - `force = stiffness * (target - current) + (-drag) * velocityHalf`
  - `velocity = velocityHalf + force * (dt / 2)`

So it can now be clearly stated that:

- This chain is a binary-backed `VelocityVerlet` spring simulation, not a vague "some kind of spring-like easing."
- `stiffness / drag`, the two core quantities, are no longer stuck at "known to exist but the formula hasn't been fully transcribed."

### 4. `SpringAnimation`'s frame update / finished predicate have now mostly been pulled apart

The two most important functions here are:

- `0x1005761bc`
- `0x1005934b0`

`0x1005761bc` can now be confirmed to follow this control chain:

- Copies a current-value-like buffer from hidden self's `0x68` slot via `0x1005730bc`.
- Copies a target-value-like buffer from hidden self's `0x70` slot via `0x100573390`.
- Calls `0x100593404` to advance the spring simulation.
- Calls `0x1005934b0` to compute the finished predicate.
- Returns via the optional `nil` branch when finished; returns via the optional `some(updatedValue)` branch when not finished.

`0x1005934b0` can now be confirmed to have two gate stages:

- First gate stage:
  - Reads two more scalar slots from hidden self.
  - First computes `Swift.max(slotA, slotB)`.
  - Then squares another threshold field and compares against it.
  - Only continues further when `max(slotA, slotB) <= threshold^2`.
- Second gate stage:
  - Explicitly constructs a `0.01` float literal.
  - Broadcasts it, via `SIMDStorage`, into a vector with the same scalar count as the animatable value.
  - Runs a series of component-wise multiplications, subtractions, and type conversions afterward.
  - At the end, instead of an approximate comparison, it derives a difference scalar `A` and tests:
    - `A > 0`
    - `0 > A`
  - Only counts as finished when neither side holds.

It's important to clearly separate confirmed from inference here:

- Confirmed:
  - The optional `nil / some(updatedValue)` branch structure of `0x1005761bc`
  - The threshold-square gate of `0x1005934b0`
  - The `0.01` float literal broadcast
  - The two-sided comparison implementing an exact-zero gate
- Still inference:
  - `0x68 / 0x70` are very likely `InterpolatableAnimation._value / _targetValue`
  - The threshold field read from metadata `+0x30` inside `0x1005934b0` is very likely `idleVelocityThreshold`

### 5. The visible geometry locks onto the endpoint first — this can now be pieced together from several strands of binary evidence

This needs to separate "confirmed" from "combined inference":

- Confirmed:
  - `CursorMotionPath.sample(progress)` clamps `progress` to `0...1`
  - `SpringAnimation`'s progress is driven by the `VelocityVerlet` chain above
  - The finished return of `0x1005761bc` is controlled separately by `0x1005934b0`
- So it can cautiously be inferred that:
  - Once the raw spring progress first reaches `>= 1.0`, the visible geometry position gets clamped to the path endpoint
  - This may happen earlier than the raw spring state becoming numerically fully at rest

This is also why the new standalone demo needs to output, at the same time:

- `raw_progress_first_ge_target_time`
- `first_endpoint_lock_time`
- `close_enough_first_time`

In current samples, it's typically possible to directly observe:

- raw progress has already crossed `1.0`
- the geometric point has already stopped at the endpoint
- but raw spring velocity / force is still nonzero

This conclusion — "the endpoint locks first, and finished may not return immediately" — is still labeled as inference for now, because it depends on piecing together three strands of evidence: the clamp in `sample(progress)`, the raw state of `VelocityVerlet`, and the finished gate in `0x1005934b0`.

### 6. `ComputerUseCursor.Window`'s animation state slots can now be matched against the main control flow's writes

The real field order of `ComputerUseCursor.Window` can now also be recovered:

- `style`
- `appMonitor`
- `wantsToBeVisible`
- `cursorMotionProgressAnimation`
- `cursorMotionNextInteractionTimingHandler`
- `cursorMotionCompletionHandler`
- `cursorMotionDidSatisfyNextInteractionTiming`
- `currentInterpolatedOrigin`
- `useOverlayWindowLevel`
- `correspondingWindowID`

Combined with the run of consecutive field writes at `0x10005be94..0x10005bf18`, these writes in the cursor-move animation's main chain can be matched directly to:

- `cursorMotionProgressAnimation`
- `cursorMotionNextInteractionTimingHandler`
- `cursorMotionCompletionHandler`
- `cursorMotionDidSatisfyNextInteractionTiming`

This means the top-level control flow is no longer just "some anonymous object writing a few slots" — it can now be mapped back to the real internal state of `ComputerUseCursor.Window`.

### 7. There's also a confirmed piecewise remap helper in the `SpringParameters` area

`0x1005879a4` sits on the `Animation.SpringParameters` side, and it applies the following piecewise mapping to its second input value:

```text
if x <= -1:
  mapped = +inf
else if x < 0:
  mapped = 1 / (1 + x)
else if x == 0:
  mapped = 0
else:
  mapped = 1 - min(x, 1)
```

This shows that the bundled binary does have a layer of spring-parameter normalization logic that can map a value near `[-1, 1]` to a damping-related parameter.

It's worth emphasizing:

- The cursor path move chain currently uses directly confirmed values of `response = 1.4`, `dampingFraction = 0.9`.
- The remap helper above is another reusable spring-parameter path within the same animation library, and it doesn't imply the cursor-move main chain necessarily passes through this remap first.

## Parts Still Under Reconstruction

### 1. Automatic bounds discovery hasn't been lifted directly into the script's input layer yet

Before calling `0x10005fd98`, the main app first runs `0x10005fa84`:

- It picks bounds from the runtime screen/region list that cover both the start and end points.
- If no such single rect can be found, it falls back to taking the union of candidate rects.

To keep the current script standalone and reproducible, it requires the caller to pass `--bounds` directly; this runtime screen-discovery step hasn't been wired in yet.

### 2. Duration / true time-based speed hasn't been fully recovered yet

Currently, the script can stably output:

- path sample points
- tangent
- `speed_units_per_progress`

But the "speed" here is still a geometric speed, i.e.:

- the distance between adjacent equal-progress sample points

True time-based speed is still missing a layer:

- how progress advances over time
- the final wiring of `BezierParameters.duration` / `AnimationDescriptor` / `CloseEnoughConfiguration` within the cursor-motion main chain

In other words, the question "which route does it take" can now be answered fairly reliably, but "how fast is this route traveled" isn't yet at the point of being claimed as exact.

Going further than the previous version, the following are now confirmed:

- the spring family
- the close-enough thresholds
- `response / dampingFraction`
- the fields of `VelocityVerletSimulation.Configuration`
- `stiffness / drag`
- `dt = 1/240`
- the update + finished-predicate control flow of `0x1005761bc` / `0x1005934b0`

All of these can now be confirmed directly from the binary.

What's still not fully lifted is:

- the complete assembly order of `Animation.Transaction` within the cursor-move main chain
- the precise semantic naming of several generic temporary buffers in the second stage of `0x1005934b0`
- the final symbol-level proof of `0x68 / 0x70 -> _value / _targetValue`
- how the real wall-clock duration emerges onto the final timeline from the combination of the spring simulation and transaction scheduling

## Scripting Landing Point

To avoid touching `CursorMotion`, this round added a standalone set of scripts under `scripts/cursor-motion-re/`:

- `reconstruct_cursor_motion.py inspect`
  - Reads the official binary and outputs the recovered motion types, fields, constants, and candidate coefficient tables.
- `reconstruct_cursor_motion.py demo`
  - Takes start/end points and optional bounds as input, and outputs candidate paths, measurements, and sample points.

The script explicitly distinguishes between two categories of implementation:

- `confirmed_from_binary`
  - piecewise cubic path sampling
  - `CursorMotionPathMeasurement`
  - candidate coefficient table extraction
  - candidate score formula
  - in-bounds-first selection strategy
- `reconstructed`
  - the duration/timing model
  - runtime bounds discovery before the call

This way, as the analysis continues to dig deeper, each reconstructed piece can be swapped out for a more accurate function-level implementation one at a time, rather than starting the whole thing over.
