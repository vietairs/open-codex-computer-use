# Software Cursor Slider Parameter Investigation

This document answers one narrowly focused question:

- Is there direct evidence, in the currently shipping `Codex Computer Use.app`, for the 5 sliders seen in the video (`START HANDLE`, `END HANDLE`, `ARC SIZE`, `ARC FLOW`, `SPRING`)?
- If the shipping bundle doesn't contain this debug-UI copy, which already binary-confirmed geometry / timing quantities are they closest to?
- When these quantities change, which part of the actual curve gets stretched, tightened, or shifted?

## Conclusions up front

The most solid conclusions right now are these 4:

1. In the shipping bundle, the 4 full slider phrases `START HANDLE`, `END HANDLE`, `ARC SIZE`, and `ARC FLOW` were not found.
2. Words like `SPRING` / `DEBUG` / `MAIL` / `CLICK` can be found in the shipping bundle, but they're all highly ambiguous tokens, and this alone cannot support the claim that "the debug UI from the video is still in the release app."
3. Even though the slider copy doesn't appear directly in the release bundle, the binary clearly retains the corresponding motion structures:
   - `CursorMotionPath.startControl`
   - `CursorMotionPath.arc`
   - `CursorMotionPath.arcIn`
   - `CursorMotionPath.arcOut`
   - `CursorMotionPath.endControl`
   - `Animation.SpringParameters(response, dampingFraction)`
4. The most reasonable interpretation right now is:
   - The sliders in the video look more like an internal debug build's tuning UI layered on top of these underlying geometry / timing quantities.
   - What the shipping binary retains is "fixed constants + candidate tables + segment logic," not slider labels with matching names.

## Evidence, by layer

### 1. Shipping-bundle phrase scan

Running a full byte scan of the local shipping bundle

`~/.codex/plugins/cache/openai-bundled/computer-use/1.0.750/Codex Computer Use.app`

currently gives:

- `START HANDLE`: not found
- `END HANDLE`: not found
- `ARC SIZE`: not found
- `ARC FLOW`: not found
- `SPRING`: found, but an ambiguous word
- `DEBUG`: found, but an ambiguous word
- `MAIL`: found, but an ambiguous word
- `CLICK`: found, but an ambiguous word

The key point here is the first four. As full phrases, they do not appear in the shipping bundle, so "a slider label exists in the release binary" cannot be treated as established fact.

### 2. Motion struct / timing struct evidence

Even though the phrases don't match, this batch of motion structures can already be directly recovered from `SkyComputerUseService`'s Swift metadata and strings:

- `CursorMotionPath`
  - `start`
  - `end`
  - `startControl`
  - `arc`
  - `arcIn`
  - `arcOut`
  - `endControl`
  - `segments`
- `CursorMotionPathMeasurement`
  - `length`
  - `angleChangeEnergy`
  - `maxAngleChange`
  - `totalTurn`
  - `staysInBounds`
- `Animation.SpringParameters`
  - `response`
  - `dampingFraction`

So "the underlying curve can indeed be decomposed into quantities like handle / arc / spring" is already a binary-backed conclusion; what isn't nailed down yet is "the one-to-one mapping between the 5 sliders in the internal debug UI and these fields."

## Current best-guess slider mapping

The layer below still carries inference, but every item is pinned to an already-confirmed binary quantity as much as possible.

### `START HANDLE`

Currently closest to:

- `CursorMotionPath.startControl`
- `startExtent` in the candidate builder

In the current binary lift, `startExtent` comes from a piecewise function:

```text
48
distance * 0.41960295031576633
640
```

which is then written into `startControl` after additional bounds clipping.

Intuitive effect:

- Mainly changes how far the motion "flicks out in the direction of the cursor's initial heading" during the start phase.
- With a larger handle, the early part of the curve is longer, and it turns back toward the target later.
- With a smaller handle, it bites back toward the main axis faster at the start.

### `END HANDLE`

Currently closest to:

- `CursorMotionPath.endControl`
- `endExtent` in the candidate builder

It controls how long the guide vector is stretched before the endpoint, which intuitively is more like "the handle length of the braking and settling motion."

Intuitive effect:

- When larger, the tail end more easily produces a longer settling hook.
- When smaller, the tail end snaps back to the target earlier.

But this one is especially prone to being absorbed by bounds clipping, so in some samples it can look like "barely changed at all."

### `ARC SIZE`

Currently closest to:

- `handleExtent`
- `arcExtent`
- `tableA`
- `tableB`

The already-confirmed primary scale is:

```text
handleExtent = piecewise(distance * 0.2765523188064277)
arcExtent = clamp(distance * 0.5783555327868779, 38, 440)
tableA = [0.55, 0.8, 1.05]
tableB = [0.65, 1.0, 1.35]
```

Intuitive effect:

- When larger, the arched family's apex sits farther from the chord, and the curve is wider, more curved, and longer.
- When smaller, the arched family looks more like a tightened ellipse or a shallow arc.

### `ARC FLOW`

No independent `flow` field has been recovered so far.

The closest fixed quantity in the shipping binary is:

```text
arcAnchorBias = guide * (startExtent * 0.65)
```

That is, the arc anchor gets pushed some distance toward the guide direction, rather than sitting strictly at the chord midpoint.

So the most conservative statement right now is:

- `ARC FLOW` looks more like tuning "how far forward or backward the apex shifts along the path," not simply "how big the arc is."
- What it mainly changes is "whether the widest part of the path appears earlier or later along the route."

This judgment is weaker than for `START/END HANDLE` and `ARC SIZE`, because the shipping binary currently has no clearly named independent `flow` field recovered.

### `SPRING`

This one has the most direct binary evidence of the 5.

The cursor-move timing chain has already been directly confirmed to go through:

- `Animation.SpringParameters(response=1.4, dampingFraction=0.9)`
- `Animation.VelocityVerletSimulation.Configuration(dt=1/240, idleVelocityThreshold=28800)`

So at minimum, this can be confirmed:

- "Spring is indeed a first-class timing input to cursor motion."
- The default shipping-release constants are `response=1.4`, `dampingFraction=0.9`.

What hasn't been recovered yet:

- Exactly how the single `SPRING` slider in the internal debug UI maps onto that `response/dampingFraction` pair.

There is also a piecewise remap helper at `0x1005879a4` near the animation library, but the current evidence still points to "the main cursor-move chain uses 1.4 / 0.9 directly," rather than going through that helper first.

## Effect on the actual curve

Below are the most notable behavioral conclusions from running a `slider-study` on two samples.

### Sample A: default lab point

Input:

```text
start = (220, 440)
end   = (860, 260)
bounds = (0, 0, 1120, 760)
```

The baseline selection is still `base-scaled-guide`, not the arched family.

So:

- `START HANDLE`
  - At `-25%`, the chosen path length is about `744.1`, with a max offset from the chord of about `44.6`
  - At `+25%`, the chosen path length is about `776.9`, with a max offset from the chord of about `49.8`
  - This shows it directly affects the currently visible primary path
- `END HANDLE`
  - Barely changed in this sample set
  - Not because "the binary has no end handle," but because `endControl` is already pinned down by bounds clipping
- `ARC SIZE`
  - The current chosen path still doesn't change
  - But the best arched candidate's offset from the chord rises from about `90.1` to about `152.9`
  - This shows this one currently affects more the competitiveness and width of the arched family
- `ARC FLOW`
  - The current chosen path still doesn't change
  - But the best arched candidate's apex progress shifts from about `0.558` to about `0.863`
  - This shows it mainly changes "whether the widest part of the arc appears earlier or later"
- `SPRING`
  - Baseline endpoint-lock is about `1.4291667s`
  - At `response -15%`, the endpoint-lock moves earlier, to about `1.225s`
  - At `response +15%`, the endpoint-lock is delayed to about `1.6375s`

### Sample B: a more centered end-handle sample

Input:

```text
start = (240, 420)
end   = (760, 360)
bounds = (0, 0, 1280, 900)
```

This set shows `END HANDLE`'s actual role more clearly:

- `end_extent -25%`
  - Chosen path length is about `632.4`
  - Max offset from the chord is about `55.2`
  - `endControl ≈ (899.55, 177.60)`
- `end_extent +25%`
  - Chosen path length is about `666.4`
  - Max offset from the chord is about `75.1`
  - `endControl ≈ (939.02, 126.0)`

In other words:

- The end handle isn't "absent from the shipping binary"
- Rather, its visible effect depends heavily on whether the current path has already been clipped by bounds

## Current firm boundaries

What can be said directly:

- The shipping binary does not contain the full label phrases `START HANDLE` / `END HANDLE` / `ARC SIZE` / `ARC FLOW`.
- The shipping binary clearly contains `startControl / arc / arcIn / arcOut / endControl / SpringParameters(response,dampingFraction)`.
- `SPRING`'s participation in timing is direct binary evidence.
- `START HANDLE` / `END HANDLE` / `ARC SIZE` / `ARC FLOW` currently look more like a debug-UI mapping layered on top of fixed geometry quantities in the release builder.

What still cannot be said for certain:

- That the 5 sliders have already been mapped one-to-one to fields inside the shipping binary.
- That `ARC FLOW` has already been recovered as an independent field.
- That the single `SPRING` slider's release mapping has been confirmed to definitely go through `0x1005879a4`.

## Reproducible commands

View the current binary's motion structures and constants:

```bash
python3 scripts/cursor-motion-re/reconstruct_cursor_motion.py inspect --pretty
```

View the slider-sensitivity analysis:

```bash
python3 scripts/cursor-motion-re/reconstruct_cursor_motion.py slider-study \
  --start 220 440 \
  --end 860 260 \
  --bounds 0 0 1120 760 \
  --pretty
```
