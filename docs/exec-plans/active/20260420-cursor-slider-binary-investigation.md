# Cursor Slider Binary Investigation

## Goal

Continue a more focused round of reverse-engineering analysis around the official `Codex Computer Use.app`'s cursor motion, to answer whether direct evidence exists in the shipping binary for the 5 sliders (`start handle`, `end handle`, `arc size`, `arc flow`, `spring`); if not, produce a clearly-labeled mapping analysis between them and the path geometry / spring pipeline already binary-confirmed, and produce reproducible sensitivity analysis output.

## Scope

- Included:
  - Check whether the official shipping bundle contains slider copy, standalone parameter types, or obvious debug UI evidence.
  - Reuse the candidate geometry and spring constants already confirmed in `scripts/cursor-motion-re/official_cursor_motion.py`, and add a parameter sensitivity analysis.
  - Clearly separate "binary-confirmed evidence" from "slider mapping inference based on path geometry" when writing it back into the docs.
- Excluded:
  - Do not directly claim a new slider mapping as an official field-for-field correspondence.
  - Do not modify the `SoftwareCursorOverlay` behavior of the main MCP runtime.
  - Do not require restoring the full implementation source of the internal debug UI in this round.

## Background

- Related documents:
  - `docs/references/codex-computer-use-reverse-engineering/software-cursor-motion-model.md`
  - `docs/references/codex-computer-use-reverse-engineering/software-cursor-motion-reconstruction.md`
  - `docs/exec-plans/active/20260419-official-cursor-motion-reconstruction.md`
- Related code paths:
  - `scripts/cursor-motion-re/`
  - `experiments/CursorMotion/`
- Known constraints:
  - The currently available official binary on this machine is `~/.codex/plugins/cache/openai-bundled/computer-use/1.0.750/Codex Computer Use.app/Contents/MacOS/SkyComputerUseService`.
  - The sliders the user saw come from a video / debug build, and do not necessarily mean the shipping bundle retains the same UI copy.
  - The current repository already explicitly requires distinguishing `confirmed_from_binary` from `reconstructed`.

## Risks

- Risk: mistakenly writing slider copy that doesn't exist in the shipping bundle as "confirmed to exist in the official release."
  - Mitigation: do a full-bundle text scan first; if there's no hit, record it only as "debug-build evidence from video, not string-confirmed in release bundle."
- Risk: mistakenly writing the parameter sensitivity analysis as "the real tuning interface has been located."
  - Mitigation: the analysis output and documentation both explicitly distinguish "fields/constants directly hit in the binary" from "slider mapping inference based on these quantities."
- Risk: the analysis script only holds for a single start/end sample, and the conclusion overfits.
  - Mitigation: have the script accept arbitrary `start/end/bounds` input, and output the specific measurement / chosen-candidate change.

## Milestones

1. Converge on direct evidence in the shipping binary related to the sliders.
2. Implement a reproducible slider sensitivity / parameter mapping analysis.
3. Documentation, history, and verification.

## Verification Method

- Commands:
  - `python3 scripts/cursor-motion-re/reconstruct_cursor_motion.py inspect --pretty`
  - `python3 scripts/cursor-motion-re/reconstruct_cursor_motion.py slider-study --start 220 440 --end 860 260 --bounds 0 0 1120 760 --pretty`
- Manual checks:
  - Confirm the string scan of the shipping bundle did not misreport slider copy as existing.
  - Confirm each slider's analysis output can be traced back to a specific geometry field, measurement, or spring timeline change.
- Observation checks:
  - The documentation clearly marks out the two-layer boundary between "release bundle string evidence" and "geometry/timing inference."

## Progress Log

- [x] Milestone 1
- [x] Milestone 2
- [x] Milestone 3

## Decision Log

- 2026-04-20: This round does not continue chasing "how the slider UI in the video actually renders," and instead prioritizes answering whether corresponding evidence is retained in the shipping binary, and which already-confirmed geometry / spring quantities these knobs more closely map to.
- 2026-04-20: A full-bundle phrase scan did not hit `START HANDLE`, `END HANDLE`, `ARC SIZE`, or `ARC FLOW`, so the repository documentation was changed to "the video evidence still holds, but it looks more like an internal debug build than UI directly visible in the release bundle."
- 2026-04-20: Added a new `slider-study` CLI instead of continuing to stuff the parameter sensitivity analysis into `inspect` / `demo`; this keeps the three layers of output — "shipping phrase evidence," "binary-confirmed motion terms," and "slider mapping inference" — separate.
