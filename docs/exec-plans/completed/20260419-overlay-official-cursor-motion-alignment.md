# Align mainline overlay with official cursor motion

## Goal

Adjust the mainline `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SoftwareCursorOverlay.swift` cursor-move behavior from its current approximate single-segment Bezier + fixed-duration easing to a two-layer model closer to the official `Codex Computer Use.app`:

- The officially lifted `20` candidate paths, measurement, and score selection.
- The officially lifted `VelocityVerlet` progress advancement and `closeEnough` return timing.

## Scope

- In scope:
  - Add an independent Swift cursor motion kernel to the mainline package.
  - Switch the overlay's path selection to the officially lifted `CursorMotionPath` / `Segment` / measurement / score.
  - Switch the overlay's move timing to the binary-backed `VelocityVerlet` progress.
  - Keep the repo's existing target-window hit-priority strategy, but demote it to a tie-break on top of the official candidate set, rather than continuing to use the old 7 fixed candidates.
  - Add unit tests, history, and architecture docs.
- Out of scope:
  - Do not modify `experiments/CursorMotion/`.
  - Do not extend this change to the full official choreography of pulse / fog / idle sway.
  - Do not claim to have recovered the full field-level naming semantics of the official `finished` gate.

## Background

- The current mainline overlay uses a simplified single-segment cubic with a fixed-duration `easeInOut`.
- Over the past couple of days, the official binary has been confirmed to have:
  - `20` candidate paths.
  - `CursorMotionPathMeasurement(length, angleChangeEnergy, maxAngleChange, totalTurn, staysInBounds)`.
  - A score formula and an in-bounds-first selection strategy.
  - The `SpringAnimation -> VelocityVerletSimulation` chain's `response=1.4`, `dampingFraction=0.9`, `dt=1/240`, `stiffness` / `drag` formulas, and single-step update order.
  - `CloseEnoughConfiguration(progressThreshold=1.0, distanceThreshold=0.01)`.

## Risks

- Risk: swapping out both the current overlay's candidates and its timing in one go could regress the existing "window-hit priority" behavior.
- Mitigation: keep the existing target-window hit-test, but place it as a tie-break on top of the official candidate pool.

- Risk: mainline click calls execute the real click immediately after `moveCursor` finishes, so if it waits for the spring values to fully settle, the experience would slow down.
- Mitigation: align mainline `moveCursor` with the official `closeEnough` semantics, returning once `progress >= 1` and `abs(target - progress) <= 0.01`.

- Risk: the reverse-engineering of `0x1005934b0` still has field-naming-level uncertainty.
- Mitigation: mainline only adopts the already-confirmed path / measurement / `VelocityVerlet` / close-enough logic, and does not disguise the unconfirmed `finished` naming as exact.

## Verification

- `swift test`
- Add unit tests for the path model, covering at least:
  - `CursorMotionPath` start/end points and the straight fallback.
  - The official candidate count is `20`.
  - The best candidate for the reference sample matches the reverse-engineering script.
  - Spring progress returns at the close-enough gate, with endpoint locking observed.

## Progress Log

- [x] Extract a reusable mainline motion kernel
- [x] Switch the overlay to the official candidates + spring progress
- [x] Docs, history, and tests all synced

## Decision Log

- 2026-04-19: This round, the mainline overlay only ingests the geometry and timing kernel already binary-confirmed; it does not wait for the remaining field naming of the `finished` predicate to be fully nailed down.
- 2026-04-19: The target-window hit strategy is kept, but changed from "the primary selector among the old 7 candidates" to "a tie-break on top of the official candidate pool."
- 2026-04-19: The mainline runtime directly reuses the official `closeEnough` spring shape, but does not treat `1.429166...` as the true wall-clock move duration; actual elapsed time continues to be mapped via this repo's already-validated local calibration formula.

## Results

- Added a reusable mainline motion kernel to `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/CursorMotionModel.swift`, including `CursorMotionPath`, candidate measurement/score, the `VelocityVerlet` progress animator, and the official candidate-generation logic.
- Switched `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SoftwareCursorOverlay.swift` to select paths from the official candidate pool, and demoted the target-window hit sampling to a tie-break.
- Added candidate-count, reference-sample best-candidate, and `closeEnoughTime` regression tests to `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`.
- Ran `swift test`; currently passing.
