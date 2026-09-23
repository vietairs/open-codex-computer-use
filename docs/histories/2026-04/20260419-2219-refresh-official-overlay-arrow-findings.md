## [2026-04-19 22:19] | Task: Refresh findings on the official overlay arrow

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Keep digging into the official `Codex Computer Use.app` to confirm whether the gray, white-outlined, drop-shadowed arrow seen in recent screenshots is actually a static asset in the bundle; the user explicitly pointed out it is not the previously exported `SoftwareCursor` or `HintArrow`, and asked to re-investigate the overlay rendering chain instead.

### 🛠 Changes Overview
**Scope:** `docs/references/codex-computer-use-reverse-engineering/`, `docs/histories/`

**Key Actions:**
- **[Correct the current-version assessment]**: Re-checked `HintArrow`, `SoftwareCursor`, and `LensSequence` in the bundled `computer-use` `1.0.750` against the gray-white arrow in the current screenshots, confirming none of the three can be directly equated with the final pointer.
- **[Strengthen rendering-side evidence]**: Based on strings from `SkyComputerUseService`, recorded names such as `SoftwareCursorStyle`, `FogCursorViewModel`, `CursorView`, `CAShapeLayer`, `SkyLensView`, `currentFrameIndex`, narrowing the conclusion from "looks like some image asset" to "more like a code/layer composition render."
- **[Run a same-thread app-server test]**: Chained `get_app_state` and `click` through the same `codex app-server` thread, confirming `click`'s returned screenshot does not show this arrow; then attached to the official service and enumerated by owner pid across the board, re-capturing a window named `Software Cursor` in the current `1.0.750` build.
- **[Capture a runtime sample]**: Ran `screencapture -l <windowid>` directly against the `Software Cursor` window, saving the full window and the raw arrow crop to `docs/references/codex-computer-use-reverse-engineering/assets/extracted-2026-04-19/`.
- **[Capture the full 2x overlay bounds]**: Continued by calling `CGWindowListCreateImage(..., .boundsIgnoreFraming | .bestResolution)` directly, confirming the `Software Cursor`'s full runtime pixel bounds are `252x252`, not the `170x170` crop seen through the default capture chain; this matches the larger frame the user's screenshot tool boxed.
- **[Add a standalone test script]**: Added `scripts/render-synthesized-software-cursor.swift`, a single-file AppKit script that renders the `126x126` overlay independently on screen. The default mode reads the repo-saved `official-software-cursor-window-252.png` directly as the official baseline image, to make sure size and silhouette line up first; `--procedural` still keeps a pure-code fallback to iterate on the fog and pointer approximation separately.
- **[Add a default-tier wobble effect]**: Also wired a slight center-fixed angle wobble into the independent script's default reference-baseline mode, plus `--snapshot-delay`, to make it easy to export independent samples at different time phases.
- **[Tighten the wobble per binary evidence]**: Then re-checked the repo's reverse-engineering docs against `SkyComputerUseService` runtime evidence again, confirming what's directly visible on the `CursorView` side is `_animatedAngleOffsetDegrees` / `_loadingAnimationToken`, while the `FogCursorViewModel` side has velocity / pressed / activity / angle; so the default tier was tightened from "whole-image translation + breathing scale + pulse" back to a small "center-fixed, clockwise/counterclockwise slight angle" wobble.
- **[Adjust the center wobble amplitude]**: Based on a further look at the official visuals, adjusted the default tier's center wobble to a total swing close to "clock 55 minutes to 00 minutes," bringing the standalone script closer to the pendulum-like rotation range the user observed.
- **[Update the reverse-engineering doc]**: Revised `software-cursor-overlay.md` so the conclusion converges to "the final gray-white arrow cannot be exported directly from a static bundle asset, but it can be captured directly from the runtime `Software Cursor` window."

### 🧠 Design Intent (Why)
This round is not about widening the range of guesses further, but about fixing the repo's claims to match the evidence. The existing docs had already proven the official app has an independent software-cursor/overlay rendering chain, but continuing to equate "the gray-white arrow in recent screenshots" directly with the exported `SoftwareCursor` asset, or continuing to treat the `170x170` small image captured by `screencapture -l` as the full bounds, would both mislead the direction of future reverse-engineering work. After updating the conclusion to "the static asset guess is wrong, the runtime `Software Cursor` window is still the source, and its full pixel bounds are actually `252x252` — it was just being cropped by framing/padding in the default capture chain" — future work can more clearly continue digging around `CursorView`, `SoftwareCursorStyle`, `FogCursorViewModel`, and the host/service composition boundary. Landing a standalone Swift script in the repo, and converging the default render to "directly show the official `252x252` runtime baseline, with `--procedural` separately trying a code approximation," stabilizes an independent test entry point first, before continuing to break down the procedural recreation.

### 📁 Files Modified
- `docs/references/codex-computer-use-reverse-engineering/software-cursor-overlay.md`
- `scripts/render-synthesized-software-cursor.swift`
- `docs/references/codex-computer-use-reverse-engineering/assets/extracted-2026-04-19/official-software-cursor-window.png`
- `docs/references/codex-computer-use-reverse-engineering/assets/extracted-2026-04-19/official-software-cursor-window-252.png`
- `docs/references/codex-computer-use-reverse-engineering/assets/extracted-2026-04-19/official-software-cursor-window-252-center-crop.png`
- `docs/references/codex-computer-use-reverse-engineering/assets/extracted-2026-04-19/official-software-cursor-pointer-raw-crop.png`
- `docs/histories/2026-04/20260419-2219-refresh-official-overlay-arrow-findings.md`
