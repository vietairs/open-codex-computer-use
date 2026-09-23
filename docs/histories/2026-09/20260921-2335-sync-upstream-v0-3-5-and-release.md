# 2026-09-21 23:35 Sync upstream v0.3.5 and release fork version 0.3.6-vietairs.1

## Background

The fork had been stuck at `v0.2.1`, while upstream had already released up to `v0.3.5`, accumulating changes in the interim such as SkyLight background clicking, App Agent socket namespace isolation, real windowserver drag, secondary-action mapping fixes, and app-resolution ranking. The fork itself also carries a batch of capabilities upstream doesn't have: the lock-screen work guard with an opt-in unattended policy, app-screen session validation, the menu-bar status item, code-signing peer authentication for the app-agent socket, and a Stage Manager background-click fallback.

This round's goal was to merge upstream `v0.3.5` in without losing a single fork capability, then cut a version for the fork itself.

## Changes

Merged `v0.3.5`: 77 files, 3627 lines added. Auto-merge handled the vast majority; only two conflicts occurred, both cases where each side had added something new with non-overlapping semantics, so both sides were kept:

- `InputSimulation.swift`: the fork's `clickBackgrounded` (resolves `CGEventSetWindowLocation` at runtime, serving the non-AX fallback path) and upstream's `clickWithSkyLight` (serving the explicit `click_method: sky_click`) each have their own call sites in `ComputerUseService`, and both functions remain reachable. The conflict block had the two functions' closing braces merged together, so besides removing the conflict markers, an extra `}` was added back.
- `AccessibilitySnapshot.swift`: the fork's added `firstAnyWindow` fallback sits before upstream's `recoveryPolicy` gate, and is **not** subject to `recoveryPolicy` — reading a background window's AX tree doesn't steal focus, so it should still apply under `.denyActivation`; upstream's activation-based `recoverVisibleWindow` recovery still only runs under `.allowActivation`.

The version jumped from `0.2.1` to `0.3.6-vietairs.1`, synced across all seven version sources listed in `docs/releases/RELEASE_GUIDE.md`.

## Why `0.3.6-vietairs.1` instead of `0.3.5`

The fork's content is "upstream 0.3.5 plus the fork's own capabilities," so directly reusing `v0.3.5` would conflict with the same-named tag already fetched from upstream. `0.3.6-vietairs.1` has three benefits: by semver it is greater than `0.3.5` and less than a future upstream `0.3.6`, which is semantically correct; the `-vietairs` prefix segment will never collide with an upstream tag name; and `scripts/validate-github-release-notes.mjs`'s tag regex already accepts a prerelease suffix, so no change to release validation is needed.

## Verification

- `swift build`: passed.
- `swift test`: 221 tests passed, 0 failed (2 skipped by design, of which `SkyClickLiveTests` requires `OPEN_COMPUTER_USE_RUN_SKY_CLICK_LIVE_TEST=1`). The fork's own tests are still present among these: `MacSessionGuard` 6, `AppScreenSession` 11, `ControlActivity` 5, peer auth 5.
- `scripts/check-docs.sh`, `scripts/check-action-pinning.sh`, all shell and mjs syntax checks, the Linux Python regression, Windows and Linux `go test`: all passed.

## Known Remaining Items

`scripts/check-repo-hygiene.sh` reports missing `.editorconfig`, `.markdownlint.json`, and several `.github/` templates and workflows. This was already failing on `main` before the merge; upstream never checked these files into version control, so it isn't an issue introduced by this round, and this round did not address it either.
