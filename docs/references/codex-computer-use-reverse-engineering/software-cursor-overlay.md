# Software Cursor Overlay

This document focuses on one very specific question: is the cursor overlay that Codex Computer Use visibly renders during real operations an independent software cursor, rather than something that directly hijacks the user's current hardware mouse cursor?

The conclusion up front: as of the latest re-review on April 19, 2026 against the bundled `computer-use` `1.0.750`, that "gray body, white edge, with shadow" arrow seen in the most recent screenshots still cannot be matched one-to-one against a single static asset directly inside the bundle; but it can now be captured directly from the runtime `Software Cursor` window, and that matches exactly the "large bounding box, small arrow" phenomenon that screenshot tools can frame. In other words, this arrow can be reconstructed, but its source isn't `HintArrow`, the raw `SoftwareCursor` PNG, or a ready-made image from `LensSequence` — it's more like a runtime visual composed from `CursorView` / `SoftwareCursorStyle` / `FogCursorViewModel` / `CAShapeLayer`.

## Observed Facts

### 1. The main host is a Dock-icon-less resident agent app

`Codex Computer Use.app/Contents/Info.plist` shows:

```json
{
  "CFBundleExecutable": "SkyComputerUseService",
  "CFBundleIdentifier": "com.openai.sky.CUAService",
  "CFBundleName": "Codex Computer Use",
  "LSUIElement": 1
}
```

`LSUIElement = 1` here indicates this is a typical agent-style macOS app, better suited to hosting a status bar item, floating windows, and background interaction rather than being a normal foreground application.

### 2. Cursor-related assets exist directly in the main app's resources

Running `assetutil --info` on the main app's `Assets.car` shows these names:

```text
Name: "CUAAppIcon_Assets/cursor"
Name: "CUAAppIcon_Assets/cursor dark"
Name: "menubar-cursor"
RenditionName: "menubar-cursor.svg"
```

This shows the official package contains not only menu bar icon resources, but also graphic assets separately named `cursor` / `cursor dark`.

Furthermore, these assets can now be exported directly as PNGs:

- [appicon-cursor.png](assets/extracted-2026-04-17/appicon-cursor.png)
- [appicon-cursor-dark.png](assets/extracted-2026-04-17/appicon-cursor-dark.png)
- [menubar-cursor.png](assets/extracted-2026-04-17/menubar-cursor.png)

In addition, both `Package_SlimCore.bundle` and `Package_ComputerUse.bundle` allow direct export of the small-size `SoftwareCursor` resource used at runtime:

- [software-cursor-slimcore.png](assets/extracted-2026-04-17/software-cursor-slimcore.png)
- [software-cursor-computeruse.png](assets/extracted-2026-04-17/software-cursor-computeruse.png)

The binary hashes of the two exported `SoftwareCursor` PNGs are identical, which shows that, at least in the current version, they reference the same image.

But the April 19, 2026 re-review against bundled `computer-use` `1.0.750` also added a very important correction:

- `HintArrow` is confirmed to only be the blue arrow used in permission onboarding, not the gray-and-white pointer seen in the recent overlay screenshots.
- The directly exported `SoftwareCursor` original image is `200x230` in size and contains an extra bright patch on the right / an additional layer mixed in, which does not map one-to-one to the final pointer body in the recent screenshots.
- The `48x48` sequence of frames under `LensSequence/` is a blue lens animation effect, and is also not the gray-and-white arrow body itself.

So the claim "the gray-and-white arrow can be dug directly out of `Assets.car` as an equivalent PNG" is currently not supported by the evidence.

### 3. Complete cursor window and animation clues show up in the `SkyComputerUseService` strings

Running `strings` on `SkyComputerUseService` directly shows these symbols and log messages:

```text
cursorWindow
imageView
imageLayer
cursorRadius
cursorScaleAnchorPoint
cursorMotionProgressAnimation
Moving mouse to %s
Start Bezier cursor animation (%{public}s).
Move cursor to (%f, %f) %s animation (%{public}s).
Signal cursor movement completion (%{public}s).
Enable the virtual cursor in Computer Use.
Detach the computer use cursor from the command palette.
```

This set of evidence is stronger than "there's a cursor resource," because it already reaches down to the level of window objects, layer objects, and motion animation objects.

Continuing further down the strings in the current `1.0.750`, there's another group of evidence more important than "a single image asset" — evidence about the rendering side:

```text
SoftwareCursorStyle
FogCursorStyle
FogCursorViewModel
AgentCursor
CursorView
cursorRadius
fogRadius
cursorScaleAnchorPoint
fogScaleAnchorPoint
CAShapeLayer
SkyLensView
isTinted
imageLoadingTasks
currentFrameIndex
animationStartTime
```

This indicates the current implementation is at least not as simple as "slap a single PNG on screen" — it's more like:

- There's an independent cursor / fog style and view model;
- At least part of the picture is generated via a `CAShapeLayer` or a similar shape/layer path;
- Another part of the visual effect is then composited on top via `imageLayer`, `SkyLensView`, and sequence-frame animation.

### 4. The current `1.0.750` runtime windows still include a `Software Cursor`

After hooking the official service on April 19, 2026, enumerating `CGWindowListCopyWindowInfo` in full by owner pid shows at least two key windows under the `Codex Computer Use` process name in the currently bundled `1.0.750`:

```text
OwnerName: Codex Computer Use
WindowName: Software Cursor
Layer: 0
Bounds: X=795 Y=353 Width=126 Height=126
IsOnscreen: 1
```

```text
OwnerName: Codex Computer Use
WindowName: Item-0
Layer: 25
Bounds: X=-14336 Y=0 Width=38 Height=37
```

Where:

- `Item-0` clearly looks like the menu bar status item window.
- `Software Cursor` is the most critical piece of direct evidence — the name alone already states its role.
- This time it doesn't stop at window metadata — this window can now be screenshotted directly:
  - [official-software-cursor-window.png](assets/extracted-2026-04-19/official-software-cursor-window.png)
  - [official-software-cursor-window-252.png](assets/extracted-2026-04-19/official-software-cursor-window-252.png)
  - [official-software-cursor-window-252-center-crop.png](assets/extracted-2026-04-19/official-software-cursor-window-252-center-crop.png)
  - [official-software-cursor-pointer-raw-crop.png](assets/extracted-2026-04-19/official-software-cursor-pointer-raw-crop.png)

The size difference between the two capture pipelines here is important:

- `screencapture -l <windowid>` and `CGWindowListCreateImage(..., .bestResolution)` both give `170x170`, which looks more like "an already-cropped, visible-window image with framing/shadow removed."
- Calling `CGWindowListCreateImage(..., .boundsIgnoreFraming | .bestResolution)` directly gives `252x252`, which exactly equals the pixel size of a `126x126` logical window on a screen with `backingScaleFactor = 2.0`.
- Within that `252x252` image, the area that actually carries the fog/body alpha is only `152x152`, and the bright center pointer is only about `30x29` — which is why visually you get "a large bounding box but a tiny arrow in the middle."

This shows that "the final visual can't be exported directly from a bundle asset" and "the final visual can be extracted from the runtime overlay" can both be true at the same time — and the large bounding box your screenshot tool frames is, in essence, the full `252x252` pixel boundary of the `Software Cursor` window.

### 5. `Software Cursor` moves as tool actions repeat

After two consecutive safe clicks on Finder, re-enumerating the windows shows the `Software Cursor` coordinates changed:

First time:

```text
WindowName: Software Cursor
Bounds: X=1949 Y=696 Width=126 Height=126
```

Second time:

```text
WindowName: Software Cursor
Bounds: X=1949 Y=796 Width=126 Height=126
```

This shows it isn't static decoration — it's an independent window driven to move by operation events.

### 6. In the current `1.0.750`, the app-server's returned images still show no cursor, but the window itself can be captured

On April 19, 2026, another same-thread test was performed:

- Chained `get_app_state` and `click` within the same ephemeral thread directly via `codex app-server`, to avoid the "Finder not activated" error introduced by the CLI opening a new thread each time.
- The image returned by `click` shows no visible cursor, indicating this arrow isn't baked into the images returned by ordinary `get_app_state` / `click` calls.
- Initially, doing high-frequency diffing on `CGWindowListCopyWindowInfo` only turned up small windows like `Item-0`, without picking out the `Software Cursor` window itself right away.
- But after hooking the service and switching to a full enumeration by owner pid, the `Software Cursor` window could again be seen directly in the current `1.0.750`, and could be captured on its own via `screencapture -l <windowid>`.
- Going one level further and calling the older `CGWindowListCreateImage` symbols directly reveals a more precise layering: the default capture pipeline only gives a cropped `170x170` result, while `boundsIgnoreFraming + bestResolution` returns the full `252x252` runtime overlay.

This tightens the earlier claim that "the current version doesn't stably reproduce a same-named window" into a more accurate statement:

- The arrow is not visible in the images returned by ordinary `click` / `get_app_state` calls;
- But in the current version, `Software Cursor` still exists as an independent window — it's just easy to miss if you only do "new-window diffing" instead of a full pid-based scan;
- Therefore "the host side may participate in some of the compositing" still holds, but the conclusion "the service side no longer has an independent software cursor window" does not currently hold.

### 7. After building a per-tool trigger matrix on April 20, 2026, it can be confirmed the overlay isn't tied only to `click`

This round added a finer-grained test of the official path, focused not on "does `Software Cursor` exist" but on "which public tools actually pull it out."

There's an important precondition here:

- On this machine's everyday Codex user configuration, the official bundled `computer-use@openai-bundled` is off by default, while the local `open-computer-use` MCP is on.
- So for this round, every sample first switched to an isolated temporary `HOME`, enabling only the official bundled `computer-use`, and then went through the same signed host path via `codex app-server`.
- Otherwise it would be very easy to mix the local open-source implementation with the official closed-source implementation and reach the wrong conclusion.

Under this precondition, running same-thread tool calls against `1.0.750` while simultaneously capturing `SkyComputerUseService` logs and `CGWindowList`, the conclusion can be summarized in the table below:

| Tool | 2026-04-20 Result | Direct Evidence Observed |
| --- | --- | --- |
| `set_value` | Triggers | Hit `Prepare to interact with element ...`, `Move to location ...`, `Move cursor to ...`; for the `Activity Monitor` search-box sample, also saw `Start Bezier cursor animation ...` |
| `scroll` | Triggers | Hit `Prepare to interact with element 1`, `Move cursor to ...`, `Start Bezier cursor animation ...`, `Moving mouse to ...` |
| `drag` | Triggers | Hit `Move cursor to ...`, `Start Bezier cursor animation ...`, `Moving mouse to ...`, `Dragging from ... to ...` |
| `perform_secondary_action` | Triggers | For the `Raise` sample on the `TextEdit` window, hit `Prepare to interact with element 0` and `Move cursor to ...` |
| `click` | Depends on path | Coordinate clicks hit `Move cursor to ...`, `Start Bezier cursor animation ...`, `Moving mouse to ...`, `Clicking at ...`; but element-scoped `click(element_index)` doesn't always |
| `type_text` | Not triggered this round | None of the three sample sets — foreground `TextEdit`, foreground `Activity Monitor`, and "Finder foregrounded while delivering text to background `TextEdit`" — showed a `Computer Use Cursor` log, nor was a `Software Cursor` window enumerated |
| `press_key` | Not triggered this round | Neither the `Return` sample on foreground `TextEdit`, nor "Finder foregrounded while delivering `Return` to background `TextEdit`," showed a cursor motion log |
| `get_app_state` | Not triggered | No `Computer Use Cursor`-related logs seen |
| `list_apps` | Not individually replayed, but statically unlikely to trigger it | No cursor-motion-related runtime evidence currently exists |

Three more important convergences here:

- `set_value` is confirmed not to be simple "direct AX assignment and done." On at least some controls, it goes through a phase of element preparation first, then moves the software cursor near the target.
- `type_text` and `press_key` currently look more like pure keyboard-injection paths. Especially in samples where "the target app is not in the foreground," `TextEdit`'s text content was indeed modified, but there was no `Software Cursor` window and no `Computer Use Cursor` motion log anywhere in the whole time window.
- `click` needs to be split into two categories: coordinate clicks look more like "real mouse simulation," while element-scoped `click` sometimes goes through a path closer to an Accessibility action, so it doesn't always show the overlay.

This also matches up with the feature flags found in the binary:

- `feature/computerUseCursor`
- `feature/computerUseAlwaysSimulateClick`
- `Prefer simulating physical clicks over Accessibility actions.`

In other words, the official implementation looks more like it decides whether to show the overlay based on which execution path this particular interaction ends up taking, rather than a simple one-size-fits-all decision by public tool name.

### 8. April 22, 2026 re-review: cursor position state does not get torn down immediately after every interaction

This round did another static + runtime re-review against bundled `computer-use` `1.0.755`, focused on whether "should it start fresh from `(0,0)` between successive `click` / `set_value` calls."

Statically, `SkyComputerUseService`'s Swift metadata still recovers the same set of state fields:

```text
ComputerUseCursor
  isMoving
  shouldFadeOut
  window
  style
  activityState

ComputerUseCursor.Window
  wantsToBeVisible
  cursorMotionProgressAnimation
  cursorMotionNextInteractionTimingHandler
  cursorMotionCompletionHandler
  cursorMotionDidSatisfyNextInteractionTiming
  currentInterpolatedOrigin
  useOverlayWindowLevel
  correspondingWindowID
```

The key point about this set of fields is: visibility state like `wantsToBeVisible` / `shouldFadeOut` is separate from `currentInterpolatedOrigin`, the position state. In other words, structurally, the official implementation doesn't clear the cursor origin the moment it fades out or a single action ends.

The runtime logs support this reading too. Within the same official service session, across repeated `Move cursor to ...` / `Start Bezier cursor animation ...` / `Signal cursor movement completion ...` sequences, AppKit repeatedly calls `orderFront` on the same window number corresponding to the same `ComputerUseCursor.Window` object. About 5 minutes after the last movement completion, `Codex Computer Use idle timeout reached; terminating service` appears.

So the more accurate lifecycle model right now is:

- On fresh service / fresh cursor window initialization, `currentInterpolatedOrigin` and the window origin start from `(0,0)`.
- Each action move updates the interpolated origin and style state of the same `ComputerUseCursor.Window`.
- After movement completion, the cursor settles into an idle/resting pose and keeps its current position; a next interaction that follows shortly after continues moving from the currently visible cursor.
- Task/turn completion triggers cleanup via the `turn-ended` lifecycle hook, and the cursor should disappear.
- `(0,0)` should be the semantics of a fresh session / service reset, and shouldn't be replayed after every single `click` or `set_value` wraps up.

## Current Inference

### 1. The small yellow mouse pointer is a software cursor, not the system hardware cursor

The most reasonable explanation right now is:

- The real system events are still delivered to the target app through the automation / event-tap path.
- The small yellow mouse pointer the user sees is a "software cursor" layer rendered by `SkyComputerUseService` itself.
- This software cursor layer moves and animates independently, so it can visually simulate "the mouse is moving" without actually hijacking the system arrow the user normally sees.

### 2. It's still an independent overlay window right now, but the final visual isn't a static asset

The current conclusion holds for three reasons:

- `cursorWindow` shows up directly in the strings.
- The runtime `CGWindowList` for the current `1.0.750` can still enumerate a clearly named `Software Cursor` window.
- This window's owner is `Codex Computer Use`, not the controlled app.

So the safer way to phrase it is:

- The official implementation still currently has an independent software cursor / overlay window;
- This window is maintained by the service, not a drawing layer inserted inside the target app;
- But the final gray-and-white arrow inside that window is not equal to any single PNG directly exportable from the bundle.

### 3. The current gray-and-white arrow can be extracted from the runtime window, but still looks more like a code/layer composite than a directly exportable asset

This point is still somewhat inferential, but the direction is clearer now than "comes directly from the `SoftwareCursor` image":

- `HintArrow`, `SoftwareCursor`, and `LensSequence` all fail to match the gray-and-white arrow in the recent screenshots.
- The binary doesn't just have `imageView` / `imageLayer` — it has a whole additional set of names leaning toward "runtime rendering," like `SoftwareCursorStyle`, `FogCursorViewModel`, `CursorView`, `CAShapeLayer`, `cursorRadius`, `fogRadius`.
- The official `click` return screenshot shows no such arrow, but capturing the `Software Cursor` window on its own does pull it out — showing it does exist within an independent overlay compositing chain, just not within the normal screenshot return path.
- The full runtime overlay boundary this arrow sits within is `252x252`, and a large portion of that area is just transparent padding and translucent fog — it's not a single ready-made cursor texture placed separately in the bundle.

So the current picture is more like an "independent window + partial assets + code drawing + host/service compositing" runtime visual, rather than a final pointer that can be exported directly from `Assets.car`.

### 4. A standalone compositing verification script has already been added to the repo

To avoid having to re-hook the official service every time just to do a visual calibration by eye, this round also added a single-file Swift verification entry point:

```bash
swift scripts/render-synthesized-software-cursor.swift --seconds 12
```

This script is now split into two modes:

- Default mode: directly reads the `official-software-cursor-window-252.png` already checked into the repo, renders this `252x252` runtime overlay baseline image independently onto a `126x126` transparent window, and only adds one extra layer — a "pendulum-like, centered" angle wobble. The standalone script currently keeps this wobble to a total swing close to "a clock hand from `55` minutes to `00` minutes," used to first align the "standalone test" with the official visual pose.
- `--procedural` mode: still keeps a pure-code fallback version that approximates the official visual using radial fog + pointer contour, to make it easier to later iterate independently on the pointer path, fog falloff, and pressed state.

In other words, this script currently prioritizes serving as an "independently verifiable official baseline," rather than claiming the procedural version is already a 1:1 reproduction.

This idle wobble was later tightened further based on binary evidence:

- On the `CursorView` side, what can currently be directly confirmed is `cursorRadius`, `_animatedAngleOffsetDegrees`, `_loadingAnimationToken`, `fogRadius`, and two sets of scale anchors;
- On the `FogCursorViewModel` side, what can currently be confirmed is `_velocityX`, `_velocityY`, `_isPressed`, `_activityState`, `_isAttached`, `_angle`;
- So the standalone script's default mode no longer does a "breathing"-style overall scale or extra translation on the whole runtime baseline image — it only keeps a small angle offset pivoting around the image's center.

If you need to capture static samples at different wobble phases, you can add:

```bash
swift scripts/render-synthesized-software-cursor.swift \
  --seconds 1.4 \
  --snapshot-delay 0.9 \
  --save-png /tmp/software-cursor-wobble.png
```

## Why This Experience Doesn't Hijack the User's Mouse

If this reading holds up, then the experience of "it looks like there's an extra small yellow mouse operating on your behalf, while your own real mouse remains fully free" is easy to explain:

- The automation layer is responsible for sending the real clicks and move events;
- The overlay layer is responsible only for what the user sees;
- The two are visually aligned, but logically separate.

This is more stable than directly manipulating the system-visible cursor, and makes it much easier to produce smooth paths, click highlighting, and delay control.

## A Deeper Implementation Inference

Continuing the static analysis of `ComputerUseCursor.Window`, two more inferences can be added that matter a lot for the open-source implementation.

### 1. The official implementation doesn't just set a window level — it also binds to a specific target window id

From `ComputerUseCursor.Window`'s ivars and helper functions, we can see:

- It stores both `useOverlayWindowLevel` and `correspondingWindowID`.
- Helper `0x10005d650` checks whether `correspondingWindowID` still exists in the current window list whenever `useOverlayWindowLevel` is enabled.
- Helper `0x10005d7bc` keeps ordering the cursor window above the corresponding window while the target window is still valid; when the target becomes invalid, it clears the current animation state and falls back to normal front-ordering behavior.

This shows the official implementation isn't "always set the overlay to some fixed level" — it's "try to maintain ordering relative to a specific window; once that target window disappears or becomes invalid, fall back to a default behavior instead."

### 2. Before generating/accepting a trajectory, the official implementation does a window hit-test check

A highly recognizable set of names shows up in `ComputerUseCursor.Window`'s larger methods:

- `distanceThreshold`
- `closeEnough`
- `control1`
- `control2`
- `staysInBounds`

The behavior of the corresponding helper `0x10005c388` also says a lot:

- It reads `correspondingWindowID`.
- It uses the current candidate point's coordinates to do a window hit-test.
- It compares the hit window number against `correspondingWindowID`.
- It only accepts that set of path/control points if the key sample points still land on the target window.

In other words, the official Bezier path isn't "compute it once up front and play it back rigidly" — it carries a layer of target-window-aware constraint checking that keeps the visible mouse trajectory from noticeably drifting outside the controlled window.

## Points Not Yet Fully Confirmed

- No continuous in-window content changes during an animation in progress have been captured yet — what's on hand is still static frames and discrete position points.
- The screenshots currently returned by `get_app_state` / `click` usually don't show this cursor, suggesting the screenshot sampling path and the overlay compositing path aren't fully the same.
- Exactly which layer on the host side composites the final body/shadow/fog of the gray-and-white pointer in the recent screenshots still needs further digging into `CursorView` or the `Codex.app` host path.

## Implications for the Open-Source Implementation

If a usable experience is to be built for `open-computer-use` down the line, this finding is quite valuable:

- "Real input injection" and "software cursor visualization" can be cleanly separated.
- The software cursor can be built as an independent overlay window, rather than being tightly coupled to the real mouse position.
- If a `windowID` is available, the Bezier candidates should first go through a round of window hit-test sampling before deciding which `control1` / `control2` pair to use.
- The overlay should ideally maintain both "ordering relative to the target window" and "whether the target window is still alive" as ongoing state, rather than only ordering layers once when the animation starts.
- Even if event execution fails, the overlay can stay observable, which helps with debugging and user trust.
- Putting both the menu bar status item and the software cursor inside the same `LSUIElement` agent app is a product shape already validated by the official implementation.
