# Read and click covered and other-Space windows

## Summary

Port upstream's covered and other-Space window support into the fork, adapted to the shared app agent and the fork's lock-screen policy. Request (condensed): keep snapshot windows visible to their apps with a scoped, session-owned occlusion keep-alive, capture windows on another Space, wait for lazy Chromium web trees, and let `sky_click` target covered and other-Space windows, without the agent display, timing knobs or benchmark parts.

## Changes

- New `SkyLightWindowServerSPI`: runtime-resolved `SLSPackagesEnableWindowOcclusionNotifications`, `SLSCopySpacesForWindows`, `SLSCopyManagedDisplaySpaces` and `SLSHWCaptureWindowList`, kept apart from `SkyLightSPI` so a missing symbol never disables `sky_click` / `sky_key`. The occlusion and capture calls run only on verified macOS major versions (27). The previous-state byte starts at a sentinel; an unreported state counts as enabled. Capture results are type-checked.
- New `WindowOcclusionKeepAlive`: pins the walked window while its app sees it as visible (on screen, current Space, not minimized, not off stage, app not hidden, strictly unlocked, finite bounds, not covered by a sampled grid). Pins are reference counted per window and owned per `ComputerUseService`; release at `StdioMCPServer.endSession`, `atexit`, SIGTERM / SIGINT / SIGHUP, `applicationWillTerminate` and screen lock. A window someone else already pinned is left alone.
- New `WindowOcclusionRestoreJournal`: a per-process, `flock`-held journal written before each WindowServer call; the app runtimes replay ended processes' journals at launch, only for windows the same pid still owns.
- `SnapshotBuilder`: ScreenCaptureKit asks for all windows; an off-screen window is captured only when it is the walked window, not minimized, app not hidden and strictly unlocked. The hardware capture is tried first for shareable windows with Screen Recording granted, strictly unlocked and a matching image size.
- New `LazyWebAccessibility`: Chromium / Electron / CEF detection from `AXManualAccessibility` or bundle frameworks under the standard application folders, a bounded two-second wait with a shallow probe for `get_app_state` only, a per-window negative cache, and a note when the window is hidden from its app.
- `sky_click` uses the target validation it now shares with `sky_key` (`SkyLightTargetWindowValidation`): the window must exist and belong to the pid, the app must not be hidden and the window not minimized. A window that is not on screen on the current Space, or whose Space cannot be read, needs a strictly unlocked session even under `OPEN_COMPUTER_USE_ALLOW_LOCKED`.
- `get_app_state` drops `readOnlyHint` on macOS. The Linux and Windows runtimes write nothing and keep it.
- Unit tests with fakes for the keep-alive (owners, journal-before-call, failed restore retry, sentinel, version gate, session end), the journal, the SPI parsers, capture eligibility, the lazy-web decision and wait, and the `sky_click` lock rule. Opt-in live tests `OcclusionKeepAliveLiveTests` (`OPEN_COMPUTER_USE_RUN_OCCLUSION_LIVE_TEST=1`) and `CrossSpaceLiveTests` (`OPEN_COMPUTER_USE_RUN_CROSS_SPACE_LIVE_TEST=1`).
- Docs: README, usage, `ARCHITECTURE.md`, `SECURITY.md`, `RELIABILITY.md`, a new window visibility reference note and its index entry, the yabai section of `THIRD_PARTY_NOTICES.md` and a feature-release row.

## Design notes

- The keep-alive is on by default but pins only what the app already sees as visible, so it never makes a hidden window look visible and never has to guess: every unknown answers "do not pin".
- The shared agent serves several host sessions at once, so pins are owned per session; ending one session must not unpin another session's windows.
- A killed process cannot run its exit hooks, so the journal is written before the WindowServer call; a replay can only turn notifications back on, the system default, so a planted journal gains nothing.
- The lock-screen opt-in covers accessibility and pid-posted input to on-screen windows. Nobody has verified WindowServer writes, hardware capture, or input to another Space while the login window owns the screen, so those paths require a strictly unlocked session.
- No timing environment knobs: a peer's per-call environment would otherwise set them in the shared agent process.

## Notes

- Not verified live in this fork: the two opt-in live tests were not run here. Upstream verified the occlusion and cross-Space behavior on macOS 27.0.
- Not ported: the agent display (`window_placement`), timing logs, benchmarks and the app matrix.
