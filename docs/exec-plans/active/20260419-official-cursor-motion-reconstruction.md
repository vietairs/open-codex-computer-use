# Official Cursor Motion Reconstruction Scripts

## Goal

Continue reverse-engineering the official `Codex Computer Use.app` cursor motion implementation, and, without touching the existing `CursorMotion`, land an independent set of binary-analysis and demo scripts under `scripts/` that can output candidate paths, sampled points, and geometric measurements for a given start/end point.

## Scope

- In scope:
  - Dig deeper into the function-level behavior of `SkyComputerUseService` related to `CursorMotionPath`, `CursorMotionPathMeasurement`, `BezierAnimation`, and `SpringAnimation`.
  - Implement independent Python scripts under `scripts/` that read the official bundled app and extract motion types, constants, and candidate coefficient tables.
  - Implement a binary-guided path sampling / measurement / candidate generation demo that outputs JSON coordinate samples and measurement data.
  - Land the new function-level analysis and script usage notes in `docs/` and history.
- Out of scope:
  - Do not modify `experiments/CursorMotion/`.
  - Do not push this round's scripts directly down into the main MCP runtime.
  - Do not claim to have 100% reconstructed every scoring / timing detail of the closed-source algorithm.

## Background

- Related docs:
  - `docs/references/codex-computer-use-reverse-engineering/software-cursor-motion-model.md`
  - `docs/references/codex-computer-use-reverse-engineering/software-cursor-overlay.md`
  - `docs/PLANS_GUIDE.md`
- Related code paths:
  - `scripts/`
  - `~/.codex/plugins/cache/openai-bundled/computer-use/1.0.750/Codex Computer Use.app`
- Known constraints:
  - Another session in this repo is continuously modifying `experiments/CursorMotion`; this task should avoid conflicting with it.
  - The official bundle is a closed-source binary; current analysis mainly relies on recovering it via `otool`, `llvm-objdump`, Swift metadata, and constant tables.
  - This round's demo should be built primarily as pure scripts / JSON output, with no GUI dependency.

## Risks

- Risk: conflating "behavior confirmed directly from function control flow" with "reconstruction based on coefficient tables."
- Mitigation: explicitly label `confirmed_from_binary` vs `reconstructed` in scripts, docs, and output.

- Risk: even though path generation has already been lifted to field level, the runtime-bounds discovery layer before the call and the actual timing binding could still get mis-written as "fully recovered."
- Mitigation: label the candidate geometry from `0x10005fd98`, the bounds preprocessing from `0x10005fa84`, and the duration / animation descriptor separately, as three distinct parts.

- Risk: touching the existing experiments directory or Package target could conflict with the other session.
- Mitigation: put all new code only under a new `scripts/` subdirectory and its corresponding docs.

## Milestones

1. Function-level reverse engineering converges.
2. Independent script implementation.
3. Verification, documentation, and wrap-up.

## Verification

- Commands:
  - `python3 scripts/cursor-motion-re/reconstruct_cursor_motion.py inspect`
  - `python3 scripts/cursor-motion-re/reconstruct_cursor_motion.py demo --start 100 120 --end 720 380 --bounds 0 0 1280 800 --pretty`
- Manual checks:
  - Cross-check the script's output type fields, coefficient tables, and constants against the current reverse-engineering conclusions.
  - Check that path sampling and measurement output match the function-level analysis of `CursorMotionPath` / `CursorMotionPathMeasurement`.
- Observation checks:
  - Confirm the script works directly against the default local bundled app path.
  - Confirm the docs clearly separate exact lifts from reconstructions.

## Progress Log

- [x] Milestone 1
- [x] Milestone 2
- [x] Milestone 3

## Decision Log

- 2026-04-19: This line of work will not continue modifying `CursorMotion`; instead it does a pure-script demo separately under `scripts/`, to avoid conflicting with the other session.
- 2026-04-19: Prioritize implementing the path sampling and measurement already confirmed at the function level from the binary, then build candidate-generation reconstruction on top of that, rather than guessing the whole parameter model directly the other way around.
- 2026-04-19: `0x100060da0` has confirmed the score formula as `320 * excessLengthRatio + 140 * angleEnergy + 180 * maxAngle + 18 * totalTurn + 45 * outOfBounds`, and confirmed the "prefer in-bounds first, then take the minimum score" strategy; duration is still left as not fully recovered.
- 2026-04-19: `0x10005fd98` has been further lifted to field level; the script can now generate the full `20` candidates per the bundled binary, including two base candidates, two cubic-segment arched candidates, the real `CursorMotionPath/Segment` layout, and guide vector `(-0.6946583704589973, 0.7193398003386512)`; runtime bounds discovery and timing remain separately marked as not fully recovered.
- 2026-04-19: The timing side has now been confirmed down to the real types and initialization chain: `ComputerUseCursor.CloseEnoughConfiguration(progressThreshold=1.0, distanceThreshold=0.01)`, `ComputerUseCursor.CursorNextInteractionTiming.closeEnough(...)`, `Animation.SpringParameters(response=1.4, dampingFraction=0.9)`, `Animation.AnimationDescriptor.spring(...)`, `Animation.SpringAnimation`, `Animation.VelocityVerletSimulation.Configuration(dt=1/240, idleVelocityThreshold=28800)`, and the `ComputerUseCursor.Window` animation state slots have been mapped back to `cursorMotionProgressAnimation / cursorMotionNextInteractionTimingHandler / cursorMotionCompletionHandler / cursorMotionDidSatisfyNextInteractionTiming`.
- 2026-04-19: `0x100593cfc` / `0x100593f18` / `0x100593404` / `0x100594110` have now had `VelocityVerlet`'s `stiffness`, `drag`, stale-time clamp, and single-step update order all directly translated out; the remaining uncertainty is no longer the math formulas themselves, but the upper-level scheduling of wall-clock duration.
- 2026-04-19: `0x1005761bc` / `0x1005934b0` have had `SpringAnimation`'s frame update / finished predicate split apart; the two hidden-self `0x68 / 0x70` buffers, the threshold-square gate, the `0.01` float-literal broadcast, and the exact-zero gate can now be confirmed, but the mapping of `0x68 / 0x70` to `_value / _targetValue` is still labeled as inference.
