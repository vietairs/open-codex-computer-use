# Codebase Gap Analysis: Stage Manager Background Control

**Repo:** https://github.com/iFurySt/open-codex-computer-use  
**Reviewed against:** v0.1.51 (2026-05-20) — latest as of 2026-05-21  
**Goal:** Identify exactly where to add "virtual mouse in background app, no focus steal" for Stage Manager.

---

## Quick Verdict

The repo has already done the hard research. The background click technique using `CGEventSetWindowLocation` + CGEvent fields 91/92 + `postToPid` is **documented but not yet implemented** in the actual Swift code. There are **4 open gaps** (original Gap 4 — drag — was wrong; `dragTargeted` already exists).

See `docs/references/codex-computer-use-reverse-engineering/background-click-free-tooling.md` for the reverse-engineering that proves this technique works.

---

## Current Architecture (relevant layers)

```
MCP tool call
    ↓
ComputerUseToolDispatcher.swift   — routes tool name → ComputerUseService
    ↓
ComputerUseService.swift          — orchestrates snapshot + action
    ↓
InputSimulation.swift             — CGEvent / AX action dispatch
AccessibilitySnapshot.swift       — window discovery, AX tree, screenshot
```

### Full dispatch map (v0.1.51 verified)

| Function | File: Lines | Background-safe? |
|---|---|---|
| `clickGlobally` | `InputSimulation.swift:58–68` | ❌ Global HID, moves real cursor |
| `clickTargeted` | `InputSimulation.swift:70–80` | ✅ `postToPid`, no cursor move |
| `postMouseEvent` | `InputSimulation.swift:224–232` | ❌ Global HID tap |
| `postMouseEventToPid` | `InputSimulation.swift:234–242` | ✅ `postToPid` |
| `dragGlobally` | `InputSimulation.swift:122–140` | ❌ Global HID, visible cursor path |
| `dragTargeted` | `InputSimulation.swift:102–120` | ✅ `postToPid` — already exists |
| `scrollGlobally` | `InputSimulation.swift:92–100` | ❌ Global HID |
| `scrollTargeted` | `InputSimulation.swift:82–90` | ✅ `postToPid` |
| `typeText` | `InputSimulation.swift:142–162` | ✅ `postToPid` + unicode chunking |
| `pressKey` | `InputSimulation.swift:187–222` | ✅ `postToPid` |
| `prepareAppForGlobalPointerInput` | `InputSimulation.swift:48–56` | ❌ Calls `runningApplication.activate()` |

---

## Gap 1 — `get_app_state` forces focus steal for Stage Manager apps

**File:** `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`  
**Lines:** 359 (window query), 192–193 (recovery path)

```swift
// Line 359 — only queries onscreen windows
guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { ... }
```

**Problem:** Stage Manager background strip apps are NOT returned by `optionOnScreenOnly`. When the window isn't found, recovery at lines 192–193 activates the app:

```swift
recovered = runningApplication.unhide() || recovered                              // line 192
recovered = runningApplication.activate(options: [.activateAllWindows]) || recovered  // line 193 ← FOCUS STEAL
```

The layer/area filter at line 443 (`.filter { $0.layer == 0 && $0.area >= 20_000 }`) correctly targets app windows but never sees them because the upstream query already excludes off-screen windows.

**Fix:** Query all windows, then skip `activate()` when target window is found off-screen:

```swift
// PROPOSED — line 359
let options: CGWindowListOption = [.excludeDesktopElements]
guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { ... }
// Keep existing layer == 0 && area >= 20_000 filter
// Add: if window found but kCGWindowIsOnscreen == false → skip activate() recovery path
```

**Caveat:** AX tree traversal works on off-screen windows (operates on process state, not visual state). Screenshots will still be unavailable — see Gap 3.

---

## Gap 2 — `clickTargeted` / `postMouseEventToPid` missing window targeting fields

**File:** `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/InputSimulation.swift`  
**Lines:** 70–80 (`clickTargeted`), 234–242 (`postMouseEventToPid`)

**Current `postMouseEventToPid` (lines 234–242):**
```swift
private static func postMouseEventToPid(type: CGEventType, source: CGEventSource,
                                         point: CGPoint, button: CGMouseButton,
                                         clickState: Int, pid: pid_t) throws {
    guard let event = CGEvent(mouseEventSource: source, mouseType: type,
                               mouseCursorPosition: point, mouseButton: button) else { ... }
    event.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
    event.postToPid(pid)      // ← no window targeting fields, no CGEventSetWindowLocation
}
```

**Coordinate click wire-up in `ComputerUseService.swift` (lines 1668–1673):**
```swift
InputSimulation.clickTargeted(at: eventPoint, button: button, clickCount: clickCount, pid: snapshot.app.pid)
// ← no windowID or windowBounds passed — cannot do background window targeting
```

**Problem:** Without CGEvent fields 91 (window-under-pointer) and 92 (event-target-window) set to the `CGWindowID`, and without calling private `CGEventSetWindowLocation(event, localPoint)`, the background window does NOT reliably receive `mouseDown/mouseUp`. The repo's own `background-click-free-tooling.md` proves this is the critical difference.

No `dlsym` or `CGEventSetWindowLocation` exists anywhere in `InputSimulation.swift`.

**Fix — new `clickBackgrounded` in `InputSimulation.swift`:**

```swift
typealias CGEventSetWindowLocationFn = @convention(c) (CGEvent, CGPoint) -> Void

static func clickBackgrounded(
    at screenPoint: CGPoint,
    windowID: CGWindowID,
    windowBounds: CGRect,
    button: MouseButtonKind,
    clickCount: Int,
    pid: pid_t
) throws {
    guard let sym = dlsym(RTLD_DEFAULT, "CGEventSetWindowLocation"),
          let setWindowLocation = unsafeBitCast(sym, to: CGEventSetWindowLocationFn?.self) else {
        // Private symbol unavailable (future macOS) — fall back gracefully
        try clickTargeted(at: screenPoint, button: button, clickCount: clickCount, pid: pid)
        return
    }

    let localPoint = CGPoint(
        x: screenPoint.x - windowBounds.origin.x,
        y: screenPoint.y - windowBounds.origin.y
    )
    let windowIDValue = Int64(windowID)

    for _ in 0..<max(clickCount, 1) {
        guard let nsDown = NSEvent.mouseEvent(
            with: button.nsDownType, location: screenPoint, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: Int(windowID),
            context: nil, eventNumber: 0, clickCount: clickCount,
            pressure: button == .left ? 1.0 : 0.0
        ), let down = nsDown.cgEvent,
        let nsUp = NSEvent.mouseEvent(
            with: button.nsUpType, location: screenPoint, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: Int(windowID),
            context: nil, eventNumber: 0, clickCount: clickCount, pressure: 0.0
        ), let up = nsUp.cgEvent else {
            throw ComputerUseError.message("Failed to create background mouse events.")
        }

        // field 91 = window under pointer, 92 = event target window
        down.setIntegerValueField(CGEventField(rawValue: 91)!, value: windowIDValue)
        down.setIntegerValueField(CGEventField(rawValue: 92)!, value: windowIDValue)
        up.setIntegerValueField(CGEventField(rawValue: 91)!, value: windowIDValue)
        up.setIntegerValueField(CGEventField(rawValue: 92)!, value: windowIDValue)

        down.location = screenPoint
        up.location = screenPoint

        // Critical: window-local point is required for reliable off-screen delivery
        setWindowLocation(down, localPoint)
        setWindowLocation(up, localPoint)

        down.postToPid(pid)
        Thread.sleep(forTimeInterval: 0.03)
        up.postToPid(pid)
        Thread.sleep(forTimeInterval: 0.03)
    }
}
```

**Wire-up in `ComputerUseService.swift` (coordinate click path ~line 1668):** When `snapshot.targetWindowID != nil && snapshot.windowBounds != nil`, call `clickBackgrounded` instead of `clickTargeted`.

---

## Gap 3 — Screenshot unavailable for Stage Manager background windows

**File:** `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`  
**Lines:** 396–414 (`captureImage(windowID:bounds:)`)

**Current implementation uses ScreenCaptureKit (updated from CGWindowListCreateImage in an earlier release):**
```swift
private static func captureImage(windowID: CGWindowID, bounds: CGRect) -> CGImage? {
    try? BlockingAsyncBridge.run(timeout: screenshotCaptureTimeout) {
        let shareableContent = try await SCShareableContent.current
        guard let window = shareableContent.windows.first(where: { $0.windowID == windowID }) else {
            return nil   // ← Stage Manager background windows NOT in SCShareableContent
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}
```

**Problem:** `SCShareableContent.current` only returns onscreen windows. Stage Manager background windows are not in the list, so `shareableContent.windows.first(where:)` returns `nil` and the function returns `nil`. The switch from `CGWindowListCreateImage` to ScreenCaptureKit did NOT fix this — both APIs have the same limitation for Stage Manager background windows.

**Fix options (best → worst):**
1. **Return AX-only result with a note** — when `captureImage` returns `nil` for a found-but-off-screen window, omit the `image` block and add `"screenshot_unavailable": "app is in Stage Manager background"` to the result. Honest, doesn't block AX-tree path.
2. **Switch Stage temporarily** — bring app to front (`open -b bundleID`), screenshot, restore. ~300ms round-trip, brief flicker.

**Recommended:** Option 1. AX tree is the useful part for background automation; screenshot is bonus.

---

## Gap 4 — ~~`drag` has no background path~~ ✅ ALREADY FIXED (was wrong in original analysis)

`dragTargeted` exists at `InputSimulation.swift:102–120`. It uses `postToPid` with a 10-step interpolation, identical to `dragGlobally` but targeted. Background-safe. No action needed.

---

## Gap 5 — `type_text` gated on foreground focused element

**File:** `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`  
**Lines:** 572–591 (`typeText`), 1235–1249 (`canTypeTextUsingKeyboardFallback`)

**Current flow (lines 572–591):**
```swift
public func typeText(app query: String, text: String) throws -> ToolCallResult {
    let snapshot = try currentSnapshot(for: query)

    // Step 1: try AXValue direct set (background-safe)
    if try typeTextBySettingFocusedValueIfAvailable(text, in: snapshot) { ... }

    // Step 2: guard — BLOCKS for Stage Manager background apps
    guard try canTypeTextUsingKeyboardFallback(in: snapshot) else {
        throw ComputerUseError.stateUnavailable("type_text requires a focused editable text element...")
    }

    // Step 3: postToPid keyboard dispatch (already background-safe if guard passes)
    try InputSimulation.typeText(text, pid: snapshot.app.pid)
}
```

**`canTypeTextUsingKeyboardFallback` (lines 1235–1249):** Returns `false` when `snapshot.focusedElement == nil` — which is always the case for Stage Manager background apps that haven't been interacted with.

**The keyboard dispatch itself (`InputSimulation.typeText`) is already background-safe** — it uses `postToPid`. The only obstacle is this guard.

**Fix — add activate-temporarily path after Step 1:**
```swift
// After typeTextBySettingFocusedValueIfAvailable check, before throwing:
if !(try canTypeTextUsingKeyboardFallback(in: snapshot)) {
    let originalPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
    NSRunningApplication(processIdentifier: snapshot.app.pid)?.activate(options: [])
    Thread.sleep(forTimeInterval: 0.08)
    try InputSimulation.typeText(text, pid: snapshot.app.pid)
    if let orig = originalPID {
        NSRunningApplication(processIdentifier: orig)?.activate(options: [])
    }
    return snapshotResult(for: try refreshSnapshot(for: query), style: .actionResult)
}
```

---

## What Already Works (no changes needed)

| Tool | File: Lines | Background-safe? | Mechanism |
|---|---|---|---|
| `press_key` | `InputSimulation.swift:187–222` | ✅ | `CGEvent.postToPid` |
| `type_text` (AXValue path) | `ComputerUseService.swift:572` | ✅ | `AXUIElementSetAttributeValue` |
| `click` AX element path | `ComputerUseService.swift:805–889` | ✅ if AX accessible | `AXPress` / `AXConfirm` |
| `scroll` targeted | `InputSimulation.swift:82–90` | ✅ | `scrollTargeted` → `postToPid` |
| `drag` targeted | `InputSimulation.swift:102–120` | ✅ | `dragTargeted` → `postToPid` |
| `set_value` | `ComputerUseService.swift` | ✅ | `AXUIElementSetAttributeValue` |

---

## Priority Order for Implementation

| # | Change | File: Line | Effort | Value |
|---|---|---|---|---|
| 1 | Drop `optionOnScreenOnly`, skip `activate()` for off-screen windows | `AccessibilitySnapshot.swift:359,192` | Small | **High** — unblocks everything |
| 2 | Add `clickBackgrounded` with `CGEventSetWindowLocation` + fields 91/92 | `InputSimulation.swift` (new func) | Medium | **High** — true virtual click |
| 3 | Wire `clickBackgrounded` into coordinate click path when windowID available | `ComputerUseService.swift:1668` | Small | **High** — connects 1+2 |
| 4 | Return AX-only result with note when window is off-screen | `AccessibilitySnapshot.swift:396` | Tiny | Medium — honest fallback |
| 5 | `type_text` activate-temporarily fallback | `ComputerUseService.swift:572` | Small | Medium — needed for text input |

---

## Key Risk: `CGEventSetWindowLocation` is private API

Resolved at runtime via `dlsym(RTLD_DEFAULT, "CGEventSetWindowLocation")`. If the symbol is missing on a future macOS, graceful fallback to `clickTargeted`. Binary stays distributable without linking against private frameworks.

The repo's own `background-click-free-tooling.md` notes this limitation — treat as implementation detail, not architectural dependency.

---

## Unresolved Questions

1. Does the AX tree remain accessible for Stage Manager background apps (layer 0, off-screen)? Needs live testing on Sequoia 15.4+.
2. Do CGEvent fields 91/92 accept raw `Int64(CGWindowID)` directly, or must they originate from `NSEvent.mouseEvent(windowNumber:)`? Reverse-engineering doc implies both work but NSEvent-backed path is more reliable.
3. Has Sequoia 15.4+ tightened `CGEventSetWindowLocation` behavior or off-screen CGWindowList query behavior?
