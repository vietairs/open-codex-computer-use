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

## Review follow-up

A code review of the branch found gaps between the code and its own docs. Changes:

- Capture is Space-aware. Windows on another Desktop also report `kCGWindowIsOnscreen`, so an on-screen window is captured under the lock-screen opt-in only when it is positively on the current Space; on another Space, or when the Space cannot be read, it needs a strictly unlocked session. ScreenCaptureKit lists every window only while strictly unlocked. `CrossSpaceLiveTests` now records the on-screen flag of the parked window.
- `sky_click` refuses a window reported off screen unless accessibility positively reads it as not minimized (the minimized read is now tri-state), and, when the target app is frontmost, refuses unless the snapshot's window is already the app's focused window on the current Space. Its checks run through `SkyClickValidationProbes`, so unit tests drive each refusal with an injected session state.
- `decide_next_action` and the one-shot CLI `snapshot` and `call` commands pin nothing, so `decide_next_action` keeps `readOnlyHint`.
- Screen lock: the observer is registered with `.deliverImmediately`, and a background lock-state check every two seconds while a pin exists covers the plain stdio server, whose main run loop never runs.
- Keep-alive robustness: a window-list read failure is "unknown", not "window gone", so the restore is kept and retried; restores that fail during recovery of an ended process's journal are adopted, journaled and retried.
- Journal: create-and-lock in one `open` (`O_EXLOCK`) with a check that the locked file was not just removed by a reader; a file left under the process's own pid by an ended process is replayed; a rewrite pads the old content and truncates after writing.
- Session end no longer resets the process-wide visual cursor, which may belong to another live session.
- The lazy-web framework listing refuses a bundle with a symbolic link below the trusted root, and the probe restores the window element's default AX messaging timeout.
- Docs corrected: lock release paths, the "never leaves notifications off" claim, rendering after release (until the next real occlusion change), and which processes replay journals.

## Live test follow-up

Request (condensed): diagnose and fix the two opt-in live tests that failed on macOS 27.2, without switching the user's Desktops. Findings and changes:

- The first `get_app_state` of a freshly launched Chrome sometimes missed the page: Chrome built its web area about 1.9 seconds after the first request, against a two-second wait, and once took longer. The wait is now three seconds (`LazyWebWaitLimits.standard`), with a unit test for a web area that appears after 2.5 seconds.
- The fixture window did not cover Chrome: its default frame depends on the screen, and under Stage Manager launching it moves Chrome off stage, where a snapshot has no screenshot by design. `OcclusionKeepAliveLiveTests` now moves the fixture over Chrome through accessibility, skips while Stage Manager is on, and asserts the covered window is not off stage.
- `SLSManagedDisplaySetCurrentSpace` from the test process did not switch Desktops. `CrossSpaceLiveTests` no longer switches: the user starts it on the Desktop where Chrome should open and switches to another Desktop when it beeps; the test waits for that switch.
- Both live tests fail up front when the runner lacks Accessibility or Screen Recording (without Screen Recording window names are empty and every window wait timed out). The procedures are in the window visibility reference note and `RELIABILITY.md`.

## Design notes

- The keep-alive is on by default but pins only what the app already sees as visible, so it never makes a hidden window look visible and never has to guess: every unknown answers "do not pin".
- The shared agent serves several host sessions at once, so pins are owned per session; ending one session must not unpin another session's windows.
- A killed process cannot run its exit hooks, so the journal is written before the WindowServer call; a replay can only turn notifications back on, the system default, so a planted journal gains nothing.
- The lock-screen opt-in covers accessibility and pid-posted input to on-screen windows. Nobody has verified WindowServer writes, hardware capture, or input to another Space while the login window owns the screen, so those paths require a strictly unlocked session.
- No timing environment knobs: a peer's per-call environment would otherwise set them in the shared agent process.

## Notes

- Verified live on macOS 27.2 with Stage Manager on: the visible snapshot of a fresh Chrome window holds the page and pins it, the page stays visible after another app takes the stage, and the hardware capture returns a size-matched image (600 x 420 points as 1200 x 840 pixels). Not yet run live: the covered path with Stage Manager off and `CrossSpaceLiveTests` with its manual Desktop switch. Upstream verified the occlusion and cross-Space behavior on macOS 27.0.
- Not ported: the agent display (`window_placement`), timing logs, benchmarks and the app matrix.
