# Software Cursor Motion Model

This document focuses on the software cursor's "motion model" itself — no longer just whether an overlay window exists, but a more specific question: given what we currently have from reverse-engineering, what structure can we infer for that natural, tunable, slightly springy mouse curve seen in the official demos?

The conclusion up front: combining the video, the `SkyComputerUseService` strings, and the types and fields recovered this time directly from `__swift5_types` / `__swift5_fieldmd`, we can say with reasonable confidence that the official implementation isn't just a single fixed cubic Bezier, but a dedicated motion engine with at least 3 layers:

- A path geometry layer: `CursorMotionPath` + `Segment`.
- A per-frame animation/physics advancement layer: `BezierAnimation` + `SpringAnimation` + `VelocityVerletSimulation`.
- A "when is the next interaction allowed to start" timing gate layer: `CloseEnoughConfiguration` + `CursorNextInteractionTiming`.

## Observed Facts

### 1. The video has an explicit tuning UI

In the X video the user provided, 5 sliders are consistently visible in the top-left corner:

- `START HANDLE`
- `END HANDLE`
- `ARC SIZE`
- `ARC FLOW`
- `SPRING`

3 toggles are visible in the top-right corner:

- `DEBUG`
- `MAIL`
- `CLICK`

This shows that, at least in the official internal debug build, cursor motion isn't a black-box constant, but a set of parameters that can be tuned live.

One caveat needs adding: a full-package phrase scan of the currently shipping local bundle
`~/.codex/plugins/cache/openai-bundled/computer-use/1.0.750/Codex Computer Use.app`
did not hit the full labels `START HANDLE`, `END HANDLE`, `ARC SIZE`, `ARC FLOW`. In other words, the slider UI in the video remains valid evidence, but it looks more like an internal debug build or an unreleased debug panel, rather than a ready-made UI that can be directly recovered from strings in the current release app.

### 2. `SkyComputerUseService` has not just strings, but recoverable Swift motion types

This time, beyond `strings`, two additional steps were taken:

- Used `otool -l` to confirm the location of the `__swift5_typeref`, `__swift5_reflstr`, `__swift5_fieldmd`, and `__swift5_types` sections.
- Parsed the type descriptors in `__swift5_types`, then cross-referenced `__swift5_fieldmd` to map field descriptors back to specific type names.

This yields not just scattered keywords, but evidence of "which type owns which fields."

#### Cursor path and state related types

The core types and fields statically recovered from `SkyComputerUseService`:

```text
ComputerUseCursor
  delegate
  targetWindowID
  isMoving
  shouldFadeOut
  window
  correspondingApplicationPID
  style
  activityState

Window
  style
  appMonitor
  wantsToBeVisible
  cursorMotionProgressAnimation
  cursorMotionNextInteractionTimingHandler
  cursorMotionCompletionHandler
  cursorMotionDidSatisfyNextInteractionTiming
  currentInterpolatedOrigin
  useOverlayWindowLevel
  correspondingWindowID

Style
  velocityX
  velocityY
  isPressed
  activityState
  isAttached
  angle

CloseEnoughConfiguration
  progressThreshold
  distanceThreshold

CursorNextInteractionTiming
  closeEnough
  finished

ActivityState
  idle
  loading
  paused

CursorMotionPathMeasurement
  length
  angleChangeEnergy
  maxAngleChange
  totalTurn
  staysInBounds

Segment
  end
  control1
  control2

CursorMotionPath
  start
  end
  startControl
  arc
  arcIn
  arcOut
  endControl
  segments
```

This batch of fields largely confirms several things:

- The official cursor path is not a hardcoded single-segment cubic, but a `CursorMotionPath` that explicitly stores `segments`.
- Each `Segment` itself carries `control1` / `control2` / `end`, showing the underlying primitive is still a cubic Bezier, but the higher-level path can be composed of multiple segments.
- Alongside the path is a `CursorMotionPathMeasurement`, whose fields aren't just length — they also include `angleChangeEnergy`, `maxAngleChange`, `totalTurn`, and `staysInBounds`. This strongly suggests the official implementation scores candidate paths for geometric quality, rather than simply taking one.
- `CloseEnoughConfiguration(progressThreshold, distanceThreshold)` together with `CursorNextInteractionTiming(closeEnough, finished)` shows the official implementation explicitly models a state of "the animation isn't fully finished yet, but is already close enough to allow the next interaction."

#### Animation and velocity-advancement related types

`SkyComputerUseService` also carries an independent animation module:

```text
BezierAnimation
  parameters

Parameters
  curve
  duration

InterpolatableAnimation
  id
  _value
  _targetValue
  eventHandler
  state
  _initialValue
  startTime

SpringAnimation
  simulation

BezierFunction
  x1
  x2
  y1
  y2
  cx
  cy
  bx
  by
  ax
  ay

BezierParameters
  curve
  duration

SpringParameters
  response
  dampingFraction

VelocityVerletSimulation
  configuration
  time
  velocity
  force

Configuration
  response
  stiffness
  drag
  dt
  idleVelocityThreshold

AnimationDescriptor
  bezier
  spring
```

The key thing here isn't the names themselves, but the field combinations:

- `BezierParameters(curve, duration)` shows time progression really does have an explicit Bezier-timing layer, rather than relying solely on system default easing.
- `BezierFunction(x1, x2, y1, y2, cx, cy, bx, by, ax, ay)` shows this Bezier layer isn't an abstract keyword — the cubic polynomial coefficients have actually been pre-expanded.
- `SpringParameters(response, dampingFraction)` is a spring input that's user-tunable or configurable at a higher level.
- `VelocityVerletSimulation(configuration, time, velocity, force)` and `Configuration(response, stiffness, drag, dt, idleVelocityThreshold)` make it nearly certain that the underlying mechanism isn't a one-shot closed-form function, but a display-link-driven, per-frame physics simulation.

### 3. `Fog` / `wiggle` are also not just figures of speech, but independent view models

This time we can also see a set of types directly corresponding to "slight wiggle while thinking" and "fog glow":

```text
FogCursorViewModel
  _velocityX
  _velocityY
  _isPressed
  _activityState
  _isAttached
  _angle

CursorView
  viewModel
  cursorRadius
  _animatedAngleOffsetDegrees
  _loadingAnimationToken
  fogRadius
  cursorScaleAnchorPoint
  fogScaleAnchorPoint
```

This shows:

- The cursor's heading really is velocity-driven, not pure positional interpolation.
- The "thinking wiggle" has at least a dedicated `_animatedAngleOffsetDegrees` and `_loadingAnimationToken` at the render layer.
- The fog isn't a simple shadow either — it has `fogRadius` and a corresponding scale anchor modeled independently.

### 4. The current open-source repo already has a simplified approximate implementation

`packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SoftwareCursorOverlay.swift` currently already has:

- Multiple cubic Bezier candidates generated from the start and end points.
- Sample-based hit testing against the target `windowID`, filtering out paths that obviously drift outside the target window.
- Cursor rotation driven by the path tangent.
- Click pulse and idle sway.

But it does not yet explicitly model the parameters that appear in this official evidence:

- `start handle`
- `end handle`
- path segmentation and turn-energy scoring
- `arc flow`
- `spring`

Nor does it have a "velocity-state spring settle" or a "next-interaction timing gate."

## Structural conclusions we can now be fairly confident about

The following still involves some inference, but it's no longer "pure guessing" — it's based on the static type evidence above.

### 1. How the curve is computed

The most plausible structure right now is:

1. First build a high-level `CursorMotionPath`.
2. This path contains at least:
   - `start`
   - `end`
   - `startControl`
   - `endControl`
   - `arc`
   - `arcIn`
   - `arcOut`
   - `segments`
3. Then expand the path into a set of concrete `Segment`s.
4. Each `Segment` uses `control1` / `control2` / `end` to generate the actual cubic Bezier.
5. Then compute a `CursorMotionPathMeasurement` for the whole path:
   - `length`
   - `angleChangeEnergy`
   - `maxAngleChange`
   - `totalTurn`
   - `staysInBounds`
6. Only paths that satisfy the quality and window-hit constraints get accepted and played.

This is considerably more complex than "just draw a single cubic straight from start to end," and is much closer to what a team member described as "calculates natural and aesthetic motion paths."

### 2. How velocity is advanced

Based on the types and fields, velocity advancement is likely not "run at a constant rate along the Bezier parameter `t`," but instead:

1. Use `BezierAnimation` / `BezierParameters(curve, duration)` to drive a base progress.
2. In phases that need springiness and a settled feel, layer on `SpringAnimation`.
3. The spring itself iterates frame by frame via `VelocityVerletSimulation`:
   - maintains `time`
   - maintains current `velocity`
   - maintains current `force`
   - advances according to `Configuration(response, stiffness, drag, dt, idleVelocityThreshold)`
4. `DisplayLinkAnimationDriver(displayLink)` drives the per-frame advancement.

The name `VelocityVerletSimulation` is especially telling, since it already exposes "what numerical method drives the spring." From current evidence, the official implementation looks more like it's doing per-frame integration, rather than simply calling an off-the-shelf `CASpringAnimation` and letting the system evaluate it as a black box.

The shipping default progress spring recovered so far is `response=1.4`, `dampingFraction=0.9`, `dt=1/240`. Per `CloseEnoughConfiguration(progressThreshold=1.0, distanceThreshold=0.01)`, the endpoint-lock / close-enough time is about `343 / 240 = 1.4291667s`. This means the default visible movement shouldn't have an additional local distance-compression layer stacked on top; both short and long distances reuse the same spring progress timeline, with only the path geometry and visible pose giving a different sense of speed.

### 3. When the next interaction is allowed to start

The pair of types `CloseEnoughConfiguration(progressThreshold, distanceThreshold)` and `CursorNextInteractionTiming(closeEnough, finished)` show that the official implementation explicitly distinguishes "the action is close enough to proceed" from "the action is fully finished."

This means:

- While the visual animation hasn't fully settled, the system may already allow the model to move on to the next tool interaction.
- This gate looks at at least two things simultaneously:
  - how much progress has run, `progressThreshold`
  - how much distance remains to the target, `distanceThreshold`

This is much closer to the continuous, unbroken feel of operation seen in official demos, compared to "always dumbly wait for the animation to finish before continuing."

## Corrected parameter-mapping judgments

Compared to the previous version of this document, there's one important correction here.

### `START HANDLE`

This now most plausibly maps to `CursorMotionPath.startControl`, and to `control1` on the final segmented cubic.

### `END HANDLE`

This now most plausibly maps to `CursorMotionPath.endControl`, and to `control2` on the final segmented cubic.

### `ARC SIZE`

The previous version mapped this directly to `arcHeight`; that judgment now needs to be downgraded.

New evidence shows:

- The fields confirmed on the cursor path type itself are `arc`, `arcIn`, `arcOut`.
- `arcHeight` has so far only been confirmed on `SystemSettingsAccessoryTransitionGeometryStyle`, not as a field on the cursor path type itself.

So a more conservative statement is: `ARC SIZE` more likely acts first on `CursorMotionPath.arc` or a segment control-point offset, rather than being confirmed as directly targeting some field literally called `arcHeight`.

### `ARC FLOW`

This judgment is firmer than in the previous version, because `arcIn` / `arcOut` really do exist on `CursorMotionPath`:

- `arcIn` most likely controls the pacing of entering the main arc from the start side.
- `arcOut` most likely controls the pacing of settling into the target on the end side.
- `ARC FLOW` most likely redistributes the balance between these two quantities.

### `SPRING`

This judgment is also more specific than before. It can now be pinned to an entire chain:

- Upper-level parameters: `SpringParameters(response, dampingFraction)`
- Runtime simulation: `VelocityVerletSimulation`
- Simulation configuration: `Configuration(response, stiffness, drag, dt, idleVelocityThreshold)`

## Design implications for an independent implementation

If we're going to carve out a version from the current repo that could later be open-sourced independently, we shouldn't keep stuffing all the logic into `SoftwareCursorOverlay`, but should split it into 4 layers:

### 1. Motion Parameters

Pure value types, with no AppKit dependency.

Should include at least:

- `startHandle`
- `endHandle`
- `arcHeight`
- `arcFlow`
- `spring`

### 2. Motion Path Builder

Takes a start point, end point, and parameters as input, and produces:

- `CursorMotionPath`
- `segments`
- `control1`
- `control2`
- `measurement`
- tangents

This layer is responsible only for geometry, not timing.

### 3. Motion Simulator

Layers time advancement on top of the path geometry:

- Bezier progress animation
- spring simulation
- velocity
- force
- next-interaction timing gate
- completion timing

### 4. Cursor Renderer / Demo Host

Only the outermost layer touches AppKit / SwiftUI, and is responsible for:

- overlay window
- debug slider UI
- target point annotation
- click / mail / debug toggles

## Recommendation for where this lands in the repo

For a cleaner path to a later independent open-source release, this should be developed in its own directory for now, rather than coupled directly to the MCP runtime:

- Suggested directory: `experiments/CursorMotion/`
- First stage: a pure local demo app that doesn't wire up real tool calls.
- Once the parameter model stabilizes, decide whether to move the `Motion Parameters` / `Path Builder` pieces back down into `packages/` for reuse.

This avoids two problems:

- Repeatedly modifying the live `click` overlay just to chase the official feel.
- Demo/tuning-UI code contaminating the main product's boundaries.

## Current assessment

The most sensible direction for an independent implementation right now isn't "keep fine-tuning the weights of the existing candidate Beziers," but rather:

1. First extract the motion model out of the overlay rendering.
2. Explicitly model `handle`, `arc`, `spring`, and `closeEnough timing` as first-class parameters.
3. Make the path builder produce "multi-segment cubic + measurement" instead of a single-segment template curve.
4. Make the timing simulator produce "Bezier progress + spring settle + velocity state."
5. Build a local Swift demo with sliders/toggles.
6. Use this demo to approach the trajectory and settling feel seen in the video.

Only then would this directory really be ready for independent open-sourcing.
