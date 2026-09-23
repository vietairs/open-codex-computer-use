# Implement a New StandaloneCursor Based on the Python Reconstruction Script

## Goal

Add an independent Swift demo pipeline that does not depend on the existing `CursorMotion`, porting the candidate paths, scoring, selection policy, and raw spring timeline already converged in `scripts/cursor-motion-re/official_cursor_motion.py` directly into a runnable `swift run StandaloneCursor` app.

## Scope

- Included:
  - Add a new `StandaloneCursor` executable target.
  - Add a new, independent support module carrying the Swift data models, candidate generation, scoring, and timeline corresponding to the Python script.
  - Add a minimal interactive app UI for dragging start/end points, selecting a candidate, and replaying the path.
  - Add a README, architecture docs, and a history entry.
- Excluded:
  - Do not modify the existing `CursorMotion` code or UI logic.
  - Do not wire this demo directly back into the main `SoftwareCursorOverlay`.
  - Do not claim to have restored the official wall-clock duration mapping.

## Background

- Related docs:
  - `docs/ARCHITECTURE.md`
  - `docs/REPO_COLLAB_GUIDE.md`
  - `scripts/cursor-motion-re/README.md`
- Related code paths:
  - `scripts/cursor-motion-re/official_cursor_motion.py`
  - `experiments/StandaloneCursor/`
  - `Package.swift`
- Known constraints:
  - Files related to `CursorMotion` in the current worktree are already in a dirty state; further work should avoid that line.
  - The goal this time is "an independent viewer closer to the Python script," not another tunable-parameter lab.

## Risks

- Risk: conflating the "confirmed core" of the Python script with the "duration mapping not yet restored."
- Mitigation: the UI and docs explicitly state that only the raw spring timeline is reused, without pretending the wall-clock duration has been restored.

- Risk: conflicts with current local changes to `CursorMotion`.
- Mitigation: create a fully independent target, source directory, and test directory.

## Milestones

1. Converge the boundaries of the new target and support model.
2. Implement the Swift app and interactive views.
3. Verification, documentation, and history wrap-up.

## Verification

- Commands:
  - `swift build --product StandaloneCursor`
  - `swift test --filter StandaloneCursorSupportTests`
  - `swift run StandaloneCursor`
- Manual checks:
  - Drag `START` / `END` and confirm the candidate paths and selected candidate update.
  - Click a candidate on the right and confirm it switches to manual lock and replays.
- Observation checks:
  - The UI shows endpoint lock / close-enough time and raw progress.
  - The docs clearly distinguish the responsibilities of `StandaloneCursor` vs. `CursorMotion`.

## Progress Log

- [x] Milestone 1
- [x] Milestone 2
- [x] Milestone 3

## Decision Log

- 2026-04-19: Do not continue modifying the current `CursorMotion`; instead add a new `StandaloneCursor` target to avoid conflicting with the current dirty worktree.
- 2026-04-19: The support model is translated directly from the Python script's naming and structure, prioritizing comparability of candidate paths, scoring, and timeline.
- 2026-04-19: The new app deliberately skips speculative visual pose dynamics, only showing the binary-guided path pool and raw spring playback.
