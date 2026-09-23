# Mainline visual cursor pose dynamics refactor

## Goal

Refactor the mainline `SoftwareCursorOverlay` from a single-layer model — "path sample directly drives tip + tangent directly drives angle" — into a two-layer model closer to the official structure: the path layer only supplies an `currentInterpolatedOrigin`-style motion target, and the actually displayed tip/velocity/angle/fog are continuously advanced by independent visual dynamics state.

## Scope

- Includes:
  - Introducing a reusable visual cursor dynamics kernel into `OpenComputerUseKit`.
  - Removing the current ad-hoc, patch-style `terminal settle` and replacing it with a unified 2D state that spans move / pulse / idle.
  - Adjusting `SoftwareCursorView`'s render inputs to add velocity-driven pose and fog/offset presentation.
  - Adding unit tests, architecture docs, and a history entry.
- Excludes:
  - No changes to `experiments/CursorMotion/`.
  - No claim of having precisely restored the full field formulas of the official `FogCursorViewModel`.
  - Not extending this change to full host choreography or loading-state tokens.

## Background

- Related docs:
  - `docs/references/codex-computer-use-reverse-engineering/software-cursor-motion-model.md`
  - `docs/references/codex-computer-use-reverse-engineering/software-cursor-motion-reconstruction.md`
  - `docs/references/codex-computer-use-reverse-engineering/software-cursor-overlay.md`
- Related code paths:
  - `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/CursorMotionModel.swift`
  - `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SoftwareCursorOverlay.swift`
- Known constraints:
  - Another session is still advancing `CursorMotion`, so this change must not touch the experimental target.
  - The endpoint clamp of `CursorMotionPath.sample(progress)` has already been binary-confirmed.
  - States such as `Style.velocityX / velocityY / angle`, `currentInterpolatedOrigin`, `FogCursorViewModel._velocityX / _velocityY / _angle`, and `CursorView._animatedAngleOffsetDegrees` exist, but have not yet been fully lifted at the formula level.

## Risks

- Risk: this change touches the overlay's core update loop and could easily break the click/pulse/idle chaining relationship.
- Mitigation: build the visual dynamics as a pure-Swift kernel, and prioritize unit test coverage for "follow, overshoot, angle lag, settle to rest."

- Risk: if the independent dynamics parameters of the visual tip are too strong, the real click point and the visual cursor could drift too far apart.
- Mitigation: cap the tip lag/fog offset upper bounds, and pin the target position during click/pulse to stay around the real click point.

- Risk: the current reverse-engineering effort has not yet recovered all of the official render-anchor formulas.
- Mitigation: for this change, only introduce state layering backed by clear evidence, without pretending it's an exact replica; keep unknown parts as tunable-but-test-protected approximations within the repo.

## Milestones

1. Determine which visual dynamics state and render inputs need to be split out of the mainline.
2. Complete the refactor in `OpenComputerUseKit` and replace `terminal settle`.
3. Add tests, docs, and a history entry, and complete verification.

## Verification

- Commands:
  - `swift test`
- Manual checks:
  - No noticeable endpoint-pivot flip after a move ends.
  - When entering the endpoint horizontally or diagonally, the visible tip shows a natural small forward overshoot/settle-back arc.
  - pulse / idle inherit the same pose state rather than resetting to zero.
- Observation checks:
  - The mainline code no longer relies on the ad-hoc `terminal settle` patch to drive the wrap-up.

## Progress log

- [x] Milestone 1
- [x] Milestone 2
- [x] Milestone 3

## Decision log

- 2026-04-19: Instead of continuing to reinforce the special-case patch near the endpoint, we switched directly to the "path target + independent visual dynamics" two-layer model, because the current problem stems from missing state layering, not from picking the wrong single path candidate.
- 2026-04-19: The mainline visual cursor does not pretend to be an exact replica of the `FogCursorViewModel` formulas this time; instead, it lands the state layering already backed by binary evidence into the main runtime first: a `currentInterpolatedOrigin`-style target point, independent `velocity/angle`, and velocity-driven fog/body lag.

## Outcome log

- Added `CursorVisualDynamicsConfiguration`, `CursorVisualDynamicsState`, `CursorVisualRenderState`, and `CursorVisualDynamicsAnimator` to `OpenComputerUseKit` as a reusable visual dynamics kernel for the mainline overlay.
- Removed the mainline overlay's ad-hoc `terminal settle` path; `move`, `pulse`, and `idle` now uniformly advance the same 2D visual dynamics state continuously.
- Expanded `SoftwareCursorView`'s input from a single `rotation` to `rotation + cursorBodyOffset + fogOffset + fogScale`, so velocity lag and fog now show up in the mainline runtime rendering.
- Added regression tests for the visual dynamics and ran `swift test`, which passed.
