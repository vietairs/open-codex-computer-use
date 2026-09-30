# Action Path Performance Scout

## 1. ComputerUseService Lifetime

**Finding:** ONE instance reused across MCP calls.

- **MCPServer.swift:38** `StdioMCPServer.init()` creates `ComputerUseService()` once, stored in `self.service`
- **MCPServer.swift:42** `ComputerUseToolDispatcher` created once with same service
- **MCPServer.swift:71-122** `handle(line:)` called per MCP request; dispatcher reused
- **MCPServer.swift:405-423** Each MCP call: `dispatcher.callTool()` → same dispatcher, same service
- **ComputerUseService.swift:961-967** `snapshotsByApp` cache map persists between calls via private ivar
- **ComputerUseService.swift:990-991** Cache populated with multiple keys (query, app.name, bundleIdentifier)

**CLI path** (MacOSAppAgentProxy):
- **MacOSAppAgentProxy.swift:481** listApps: `ComputerUseService()` created per CLI call
- **MacOSAppAgentProxy.swift:485** snapshot: `ComputerUseService()` created per CLI call
- **MacOSAppAgentProxy.swift:489** call: `ComputerUseService()` created per CLI call
(But these are different codepaths from MCP)

## 2. Snapshot Builds, Thread.sleep, Cursor Moves — Action Path

### Click (click/x,y)
| Phase | Type | Location | Value |
|-------|------|----------|-------|
| Initial snapshot | `currentSnapshot()` | ComputerUseService.swift:615 | cached or fresh |
| Fixture cursor move | `moveVisualCursor()` | ComputerUseService.swift:631 | SoftwareCursorOverlay.moveCursor() |
| Fixture sleep | `Thread.sleep` | ComputerUseService.swift:642 | 0.15s |
| Fixture pulse | `pulseVisualCursor()` | ComputerUseService.swift:643 | pulseClick() |
| **Non-fixture path** |
| Cursor move (element or x/y) | `moveVisualCursor()` | ComputerUseService.swift:659, 720 | SoftwareCursorOverlay.moveCursor() |
| Cursor settle (on error) | `settleVisualCursor()` | ComputerUseService.swift:705, 764 | SoftwareCursorOverlay.settle() |
| Cursor pulse | `pulseVisualCursor()` | ComputerUseService.swift:709, 768 | pulseClick() |
| Final refresh | `refreshSnapshot()` | ComputerUseService.swift:774-777 | builds new snapshot + pngDataIfAvailable() |
| Final result | `snapshotResult()` | ComputerUseService.swift:773-779 | style: .actionResult |

### PerformSecondaryAction
| Phase | Type | Location | Value |
|-------|------|----------|-------|
| Initial snapshot | `currentSnapshot()` | ComputerUseService.swift:783 | cached or fresh |
| Fixture check | | ComputerUseService.swift:786 | refreshSnapshot path if fixture |
| AX perform | `AXUIElementPerformAction()` | ComputerUseService.swift:802 | accessibility action |
| Sleep | `Thread.sleep` | ComputerUseService.swift:807 | 0.15s |
| Refresh | `refreshSnapshot()` | ComputerUseService.swift:808 | builds new snapshot |
| Result | `snapshotResult()` | ComputerUseService.swift:808 | style: .actionResult |

### Scroll
| Phase | Type | Location | Value |
|-------|------|----------|-------|
| Initial snapshot | `currentSnapshot()` | ComputerUseService.swift:820 | cached or fresh |
| Fixture sleep | `Thread.sleep` | ComputerUseService.swift:828 | 0.15s |
| AX scroll loop | `AXUIElementPerformAction()` loop | ComputerUseService.swift:835-838 | per page iteration |
| Scroll loop sleep | `Thread.sleep` | ComputerUseService.swift:837 | 0.05s **per page** |
| Global point scroll | `performScrollEvent()` | ComputerUseService.swift:840-844 | mouse event fallback |
| Final refresh | `refreshSnapshot()` | ComputerUseService.swift:846-850 | builds new snapshot |
| Result | `snapshotResult()` | ComputerUseService.swift:846-851 | style: .actionResult |

### TypeText
| Phase | Type | Location | Value |
|-------|------|----------|-------|
| Initial snapshot | `currentSnapshot()` | ComputerUseService.swift:877 | cached or fresh |
| Fixture sleep | `Thread.sleep` | ComputerUseService.swift:880 | 0.15s |
| Value-based input sleep | `Thread.sleep` | ComputerUseService.swift:885 | 0.1s (if setFocusedValue worked) |
| App activation sleep | `Thread.sleep` | ComputerUseService.swift:893 | 0.08s (if app must be activated) |
| Final refresh | `refreshSnapshot()` | ComputerUseService.swift:881, 886, 898, 902 | builds new snapshot |
| Result | `snapshotResult()` | ComputerUseService.swift:881, 886, 898, 902 | style: .actionResult |

### PressKey
| Phase | Type | Location | Value |
|-------|------|----------|-------|
| Initial snapshot | `currentSnapshot()` | ComputerUseService.swift:906 | cached or fresh |
| Fixture sleep | `Thread.sleep` | ComputerUseService.swift:909 | 0.15s |
| Final refresh | `refreshSnapshot()` | ComputerUseService.swift:910, 914 | builds new snapshot |
| Result | `snapshotResult()` | ComputerUseService.swift:910, 914 | style: .actionResult |

### SetValue
| Phase | Type | Location | Value |
|-------|------|----------|-------|
| Initial snapshot | `currentSnapshot()` | ComputerUseService.swift:918 | cached or fresh |
| Cursor move (fixture) | `moveVisualCursor()` | ComputerUseService.swift:927 | SoftwareCursorOverlay.moveCursor() |
| Fixture sleep | `Thread.sleep` | ComputerUseService.swift:929 | 0.15s |
| Cursor settle (fixture) | `settleVisualCursor()` | ComputerUseService.swift:930 | SoftwareCursorOverlay.settle() |
| Cursor move (non-fixture) | `moveVisualCursor()` | ComputerUseService.swift:943 | SoftwareCursorOverlay.moveCursor() |
| AX set value | `AXUIElementSetAttributeValue()` | ComputerUseService.swift:946 | set kAXValueAttribute |
| Value set sleep | `Thread.sleep` | ComputerUseService.swift:951 | 0.1s |
| Cursor settle | `settleVisualCursor()` | ComputerUseService.swift:957 | SoftwareCursorOverlay.settle() |
| Final refresh | `refreshSnapshot()` | ComputerUseService.swift:958 | builds new snapshot |
| Result | `snapshotResult()` | ComputerUseService.swift:958 | style: .actionResult |

## 3. Screenshot PNG Capture & Style Filtering

**PNG capture timing:**
- **AccessibilitySnapshot.swift:393** `let screenshotPNGData = windowCapture.pngDataIfAvailable()` — called in `buildAccessibilitySnapshot()`
- **AccessibilitySnapshot.swift:643-661** `captureImage()` runs `SCScreenshotManager.captureImage()` with 5s timeout
- **AccessibilitySnapshot.swift:94** `screenshotCaptureTimeout: TimeInterval = 5` — hardcoded, no env override
- **AccessibilitySnapshot.swift:638** PNG capture skipped for off-screen windows (Stage Manager background)

**Style filtering (attachment decision):**
- **ComputerUseService.swift:2066-2073** `snapshotResult(for snapshot, style)`
- **ComputerUseService.swift:2069** `if style != .compactActionable, let screenshotPNGData = snapshot.screenshotPNGData`
- **AccessibilitySnapshot.swift:304-310** SnapshotTextStyle enum: `.fullState`, `.actionResult`, `.compactActionable`
- **ComputerUseService.swift:2069** PNG attached for `.fullState` and `.actionResult`, **NOT** for `.compactActionable`
- Action methods (click, typeText, etc.) all use `.actionResult` → PNG **always attached** for actions
- No environment variable found to skip screenshot capture during build; capture runs regardless of later attachment decision

## 4. Cursor Motion Timing

**Visual cursor enable/disable:**
- **SoftwareCursorOverlay.swift:28-32** `visualCursorEnabled()` reads `OPEN_COMPUTER_USE_VISUAL_CURSOR` env var
- **SoftwareCursorOverlay.swift:32** Returns false if env = `"0"`, `"false"`, `"no"`, `"off"` (case-insensitive); else true

**Cursor animation duration:**
- **SoftwareCursorOverlay.swift:354-358** `animateMove()` calculates duration via `OfficialCursorMotionModel.calibratedTravelDuration()`
- **CursorMotionModel.swift:657-658** `calibratedTravelDuration()` delegates to `OfficialCursorMotionModel.calibratedTravelDuration()`
- **CursorMotionModel.swift:493-494** `DebugCursorMotionModel.calibratedTravelDuration()` always returns `closeEnoughTime`
- **CursorMotionModel.swift:333** `OfficialCursorMotionModel.closeEnoughTime = CursorMotionProgressAnimator.closeEnoughTime()`
- **CursorMotionModel.swift:301-325** `closeEnoughTime()` is spring-based: runs simulation until progress >= `isCloseEnough()` threshold, returns ~1.43s if max iterations hit (line 324)
- **SoftwareCursorOverlay.swift:358** `springTargetDuration = OfficialCursorMotionModel.closeEnoughTime` — used as time-scaling factor for spring animation

**Cursor settle timeout:**
- **SoftwareCursorOverlay.swift:71-72** `visualCursorPostInteractionIdleTimeout()` = 30 seconds (no env override)

**Frame pump:**
- **SoftwareCursorOverlay.swift:388** `pumpFrame()` runs per animation loop iteration
- **SoftwareCursorOverlay.swift:796** `RunLoop.current.run(mode: .default, before: ...)` throttled to ~120 FPS (1/120 interval)

**No environment variable found to disable cursor animation duration or adjust timing.**

## Unresolved Questions

1. Is SnapshotBuilder.build ever skipped if cache hit? Or is PNG always captured fresh per call?
   → Recommend: grep for snapshotsByApp usage and verify if refreshSnapshot is mandatory per action or only when cache misses
2. Can screenshotCaptureTimeout be made configurable? Currently hardcoded 5s, no env override found
   → Recommend: search for SCREENSHOT or TIMEOUT env patterns more broadly
