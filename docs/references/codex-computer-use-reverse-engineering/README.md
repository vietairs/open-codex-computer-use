# Codex Computer Use Reverse Engineering

This directory is used to continuously accumulate reverse-engineering findings on the official closed-source `Codex Computer Use.app` and `SkyComputerUseClient`, with the goal of providing traceable input for the `open-computer-use` open-source implementation, rather than leaving key context in chat history.

## Current Documents

- `baseline-architecture.md`
  - Currently confirmed bundle structure, entry points, identifiers, transport, and module layering.
- `runtime-and-host-dependencies.md`
  - Currently observed runtime behavior, host dependencies, Inspector direct-connect failure symptoms, and shared-state clues.
- `packaging-and-lifecycle-integration.md`
  - Currently confirmed plugin packaging structure, main app distribution form, CLI surface, and `turn-ended` lifecycle integration approach.
- `internal-ipc-surface.md`
  - Currently confirmed client-service internal IPC types, sender authorization, skyshot model, and service lifecycle clues.
- `tool-call-samples-2026-04-17.md`
  - Actual request/response samples from testing 9 public `computer-use` tools on 2026-04-17.
- `background-click-free-tooling.md`
  - Methodology for using Ghidra, radare2, Apple CLI tools, and Swift prototypes as a substitute for IDA Pro to research the background-click path, for later agents to regenerate large-size analysis artifacts locally in the `research/` directory.
- `software-cursor-overlay.md`
  - Analysis of the yellow virtual mouse overlay's resources, strings, and runtime window evidence.
- `software-cursor-motion-model.md`
  - Inference of the cursor motion parameter model, combining video samples, official strings, and the current open-source implementation.
- `software-cursor-motion-reconstruction.md`
  - After drilling further down to the function level, a reconstruction write-up of `CursorMotionPath.sample(progress)`, `CursorMotionPathMeasurement`, the `CursorMotionPath/Segment` layout, 20 candidate geometries, the scoring formula, the in-bounds-priority selection strategy, and the `SpringAnimation -> VelocityVerletSimulation` timing chain, finished predicate, and endpoint-lock observations.
- `software-cursor-slider-parameter-investigation.md`
  - For the 5 sliders seen in the video, records whether the shipping bundle still carries the corresponding label phrase, their mapping to the currently binary-confirmed geometry/spring quantities, and a sensitivity analysis against the actual curves.
- `permission-onboarding.md`
  - Analysis of the Accessibility / Screen Recording permission onboarding flow and the System Settings accessory window.
- `state-rendering-1.0.770.md`
  - A compilation of the official `computer-use` 1.0.770 state renderer strings, AX fields, tree transform, and window-restoration clues, used to keep converging the Lark / Electron app state output.
- `assets/README.md`
  - An archive of visual assets exported directly from the official bundle, including `SoftwareCursor`, `HintArrow`, and cursor icon assets.

## Usage Conventions

- Write "observed facts" first, then "inferences."
- Cite the evidence source wherever possible, e.g. bundle file, analytics, crash report, `strings`/`otool`/`codesign`.
- If a later conclusion overturns an earlier judgment, edit the doc directly rather than keeping the stale claim.
