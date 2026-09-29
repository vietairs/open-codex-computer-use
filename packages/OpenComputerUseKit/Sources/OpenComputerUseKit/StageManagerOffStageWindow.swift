import ApplicationServices
import CoreGraphics
import Foundation

/// Under Stage Manager a window outside the current stage is drawn as a small thumbnail in the left strip. It keeps
/// its window id and its full accessibility frame, but the window server reports (and every capture API returns)
/// only the thumbnail. Such a window is still fully drivable through accessibility actions; it just has no usable
/// screenshot and no screen position that pointer events could hit.
///
/// Detection only reads frames. It never activates the app, raises the window, switches stages, or moves the pointer.

/// A window is off stage when its window-server area is below this fraction of its accessibility area. A strip
/// thumbnail is about 1% of the real window; an on-stage window reports equal frames.
let offStageWindowAreaRatioThreshold: CGFloat = 0.5

let offStageWindowNote =
    "Window is off stage in Stage Manager; no screenshot is available. element_index actions still work; x/y coordinates cannot be used for this window."

let offStageCoordinateInputMessage =
    "x/y coordinates cannot target this window: it is off stage in Stage Manager, so there is no screenshot to read coordinates from and pointer events would miss the window. Use element_index actions instead."

/// An off-stage window, identified by its window id and located by its accessibility frame.
struct OffStageWindow: Equatable {
    let windowID: CGWindowID
    let accessibilityFrame: CGRect
}

/// Decides whether a window is off stage. A minimized window is never off stage (it has its own handling), and a
/// window the window server does not list cannot be compared, so both answer nil. `windowServerFrame` is read only
/// when the other inputs already allow an off-stage answer.
func offStageWindow(
    windowID: CGWindowID?,
    accessibilityFrame: CGRect?,
    isMinimized: Bool,
    windowServerFrame: (CGWindowID) -> CGRect?
) -> OffStageWindow? {
    guard !isMinimized, let windowID, let accessibilityFrame else {
        return nil
    }

    let axFrame = accessibilityFrame.standardized
    let axArea = axFrame.width * axFrame.height
    guard axArea.isFinite, axArea > 0, let serverFrame = windowServerFrame(windowID)?.standardized else {
        return nil
    }

    let serverArea = serverFrame.width * serverFrame.height
    guard serverArea.isFinite, serverArea / axArea < offStageWindowAreaRatioThreshold else {
        return nil
    }

    return OffStageWindow(windowID: windowID, accessibilityFrame: axFrame)
}

/// Fails an x/y (pointer-event) input on an off-stage window instead of posting events at a position the window does
/// not occupy.
func rejectCoordinateInputWhenOffStage(_ isOffStage: Bool) throws {
    if isOffStage {
        throw ComputerUseError.stateUnavailable(offStageCoordinateInputMessage)
    }
}

/// Live reads for `offStageWindow`: the AX window id, the AX frame and minimized flag, and the window-server frame
/// for the same id.
func liveOffStageWindow(for window: AXUIElement) -> OffStageWindow? {
    offStageWindow(
        windowID: accessibilityWindowID(of: window),
        accessibilityFrame: accessibilityWindowFrame(of: window),
        isMinimized: accessibilityWindowIsMinimized(window),
        windowServerFrame: windowServerFrame(forWindowID:)
    )
}

@_silgen_name("_AXUIElementGetWindow")
private func axUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

private func accessibilityWindowID(of window: AXUIElement) -> CGWindowID? {
    var windowID: CGWindowID = 0
    guard axUIElementGetWindow(window, &windowID) == .success, windowID != 0 else {
        return nil
    }
    return windowID
}

private func accessibilityWindowFrame(of window: AXUIElement) -> CGRect? {
    var positionRaw: CFTypeRef?
    var sizeRaw: CFTypeRef?
    guard
        AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRaw) == .success,
        AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRaw) == .success,
        let positionRaw, let sizeRaw,
        CFGetTypeID(positionRaw) == AXValueGetTypeID(),
        CFGetTypeID(sizeRaw) == AXValueGetTypeID()
    else {
        return nil
    }

    var position = CGPoint.zero
    var size = CGSize.zero
    guard
        AXValueGetValue(positionRaw as! AXValue, .cgPoint, &position),
        AXValueGetValue(sizeRaw as! AXValue, .cgSize, &size)
    else {
        return nil
    }
    return CGRect(origin: position, size: size)
}

private func accessibilityWindowIsMinimized(_ window: AXUIElement) -> Bool {
    var raw: CFTypeRef?
    guard AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &raw) == .success else {
        return false
    }
    return (raw as? Bool) == true
}

private func windowServerFrame(forWindowID windowID: CGWindowID) -> CGRect? {
    guard
        let windowInfo = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
        let entry = windowInfo.first(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowID }),
        let boundsDictionary = entry[kCGWindowBounds as String] as? NSDictionary
    else {
        return nil
    }
    return CGRect(dictionaryRepresentation: boundsDictionary)
}
