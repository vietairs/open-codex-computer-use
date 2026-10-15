# macOS Background Window Visibility and Spaces

## Purpose

How `get_app_state`, `sky_click` and `sky_key` handle windows that are covered or on another Space, and why this is solved at the WindowServer (SkyLight) level instead of per app. The observations below come from upstream's controlled tests on macOS 27.0 (September 2026) with an isolated Chrome profile, Electron apps and the repository fixture, adapted to this fork. The live regressions are `OcclusionKeepAliveLiveTests` and `CrossSpaceLiveTests`, both opt-in.

## The problem from macOS's point of view

A computer-use agent that does not take the user's focus needs three things, and each has a macOS primitive:

| Need | macOS primitive | Use in this repository |
| --- | --- | --- |
| Read window state | Accessibility (per process, independent of Space) plus window capture by window id | `SnapshotBuilder`, `WindowCapture` |
| Whether a window is "visible" | WindowServer occlusion state, delivered to the app through notifications registered with `SLSPackagesEnableWindowOcclusionNotifications` and exposed by AppKit as `NSWindow.occlusionState` | `WindowOcclusionKeepAlive` |
| Input to a background process | `SLPSPostEventRecordTo` (activation and key-window records), `SLEventPostToPid` / `CGEventPostToPid` | `sky_click`, `sky_key` |
| Spaces | `SLSCopySpacesForWindows`, `SLSCopyManagedDisplaySpaces` | Read only; the runtime never moves a window or switches Space |

An app does not find out by itself that it is covered; it learns it only from WindowServer occlusion notifications. Chromium then marks the page hidden: the renderer stops producing frames and the `AXWebArea` subtree leaves the accessibility tree. Electron and WebKit behave the same way. Native AppKit windows are not affected. So "the tree of a window on another Space is empty" is caused by occlusion, not by the Space itself.

## Observed behavior

- A fully covered Chrome window: `document.visibilityState` becomes `hidden` and the accessibility tree keeps only the window chrome, with no `AXWebArea`. Window capture by id still works, and `sky_click` still triggers a DOM click.
- Calling `SLSPackagesEnableWindowOcclusionNotifications(cid, wid, false, &previous)` on the window (it works across processes and returns 0) and then covering it: the page stays `visible`, the `AXWebArea` stays, clicks and typing work, and the user's frontmost app is not affected. Turning notifications back on does not resend the current state until the next real change.
- Turning notifications off for a window that is already covered does not help: the app stays hidden. So the keep-alive pins a window only while it is not covered, judged by sampling a grid over the window against the layer-0 windows above it (`CGWindowListCopyWindowInfo` with `.optionOnScreenAboveWindow`).
- The fourth argument of `SLSPackagesEnableWindowOcclusionNotifications` is an optional `uint8_t *previous` output pointer. The signature was read from the function prologue; a wrong guess writes through a pointer the callee interprets differently. The fork therefore calls it only on verified macOS major versions, writes a sentinel into the byte first, and treats an untouched sentinel or any value other than 0 or 1 as "previous state unknown, assume enabled".
- Chromium-based apps (Chrome, Electron, CEF) build the web accessibility tree asynchronously after the first accessibility request; Chrome can need about two seconds. `AXManualAccessibility` succeeds for Electron but returns `attributeUnsupported` for Chrome, so it cannot be the only signal; the runtime also checks the bundle's `Contents/Frameworks` for Chromium, Electron or CEF frameworks.
- A Chrome window in a full-screen Space reports `visibilityState` `visible`, and `sky_click` / `sky_key` work, but full screen rebuilds the window structure, so it is not a stand-in for "another desktop Space".
- A real second Desktop (`CrossSpaceLiveTests`): with Chrome on Desktop 2 and the user on Desktop 1 with another app in front, `SnapshotBuilder` resolves the window and returns page content and a screenshot, `sky_click` and `sky_key` work, the active Space does not change and Chrome is not activated. Windows on another Desktop still report `kCGWindowIsOnscreen` as true, so the window's Space has to be read with `SLSCopySpacesForWindows(cid, 0x7, [wid])` and compared with the current Space of each display from `SLSCopyManagedDisplaySpaces`.
- On macOS 26 and later a third-party process cannot move another app's window to another Space: `SLSMoveWindowsToManagedSpace`, `SLSAddWindowsToSpaces` and `SLSSpaceCreate` check `SLSWindowManagementClientOperationsEnabled()` first and return silently. The runtime does not need to move windows.
- Window capture: `SLSHWCaptureWindowList(cid, &wid, 1, 0x800)` reads the window's backing store through WindowServer at backing resolution; option `0x800` ignores the global clip shape, so a covered window is captured whole. ScreenCaptureKit also captures windows on another Space when asked for all windows (`onScreenWindowsOnly: false`), and returns `-3811` for windows in an inactive full-screen Space, which the hardware capture still reads.

## Runtime behavior in this fork

1. Every snapshot build checks whether the walked window is visible to its own app: on screen, on the current Space, not minimized, not off stage under Stage Manager, app not hidden, the session known to be unlocked, finite non-empty bounds, and not covered. Any unknown answer means "not visible".
2. A visible window is pinned: its occlusion notifications are turned off, so the user can cover it or switch Space and the app still treats it as visible. Pins are owned per host session of the shared app agent and reference counted per window. A session releases its own pins when it ends; every pin is released at process exit (`atexit`, SIGTERM, SIGINT, SIGHUP, `applicationWillTerminate`) and on screen lock. A window whose notifications another process had already turned off is not pinned, and a release never turns them off.
3. Each pin is written to a per-process restore journal before the WindowServer call. The journal file is held under an exclusive `flock` for the process lifetime, so the next process (at app launch, or before its first pin) can tell which journals belong to ended processes and turn notifications back on for windows the same pid still owns.
4. Capture: an off-screen window (another Space) is captured only when it is the walked window, not minimized, its app not hidden, and the session known to be unlocked. The hardware capture is tried first only for windows that allow sharing, with Screen Recording granted, while strictly unlocked, and only when the image size matches the window bounds times the backing scale (within two pixels); otherwise ScreenCaptureKit is used.
5. For a Chromium-based app whose tree has no `AXWebArea`, `get_app_state` waits up to two seconds while the window is visible, polling a shallow, node-bounded probe with a short accessibility messaging timeout, and walks the window again once the web area appears. A window that used up its wait is remembered and not waited on again; action results never wait. When the window is hidden from its app, the result carries a note instead of waiting or activating anything.
6. `sky_click` and `sky_key` require only that the window still exists and belongs to the target process, the app is not hidden and the window not minimized; the window need not be on screen. `sky_key` always needs a strictly unlocked session. `sky_click` keeps its existing lock policy for an on-screen window on the current Space and needs a strictly unlocked session for any other window. Neither accepts a Stage Manager off-stage window.

The occlusion and hardware-capture calls run only on macOS major versions on which their argument layout was checked (`windowServerSPIVerifiedMajorVersions`, macOS 27 today). On any other version nothing is pinned and screenshots come from ScreenCaptureKit. The Space and capture declarations follow the MIT-licensed yabai project.

## Not covered

- A Chromium-based window that is already covered or on another Space when the agent first sees it cannot be made visible without showing it; the user has to bring it into view once. Upstream's virtual-display placement for this case is not part of this fork.
- `CrossSpaceLiveTests` needs a second Desktop created in Mission Control. Third-party processes cannot move windows between Spaces, so the test switches to Desktop 2, launches Chrome there and switches back.
- While pinned, a covered window keeps rendering until its session ends. After a SIGKILL or crash, pins stay until the next Open Computer Use process starts or the target app closes the window.

## Sources

- Chromium `content/app_shim_remote_cocoa/web_contents_occlusion_checker_mac.mm` and `web_contents_view_cocoa.mm` (`isWindowOccluded:` follows `NSWindow.occlusionState`).
- yabai `src/window_manager.c` (SkyLight declarations and event-record layout), Cua Driver (SkyLight bridge). See `THIRD_PARTY_NOTICES.md`.
