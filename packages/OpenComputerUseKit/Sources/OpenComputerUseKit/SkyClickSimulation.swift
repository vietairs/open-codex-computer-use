import AppKit
import CoreGraphics
import Foundation

struct SkyClickTarget {
    let screenPoint: CGPoint
    let windowPoint: CGPoint
    let windowBounds: CGRect
    let windowID: CGWindowID
    let pid: pid_t
}

enum SkyClickEventKind: Equatable, Sendable {
    case moved
    case down
    case up

    var cgEventType: CGEventType {
        switch self {
        case .moved:
            return .mouseMoved
        case .down:
            return .leftMouseDown
        case .up:
            return .leftMouseUp
        }
    }
}

enum SkyClickPointKind: Equatable, Sendable {
    case target
    case primer
}

struct SkyClickEventStep: Equatable, Sendable {
    let kind: SkyClickEventKind
    let pointKind: SkyClickPointKind
    let clickState: Int64
    let phase: Int64
    let delayAfter: TimeInterval
}

func skyClickEventRecipe(clickCount: Int) throws -> [SkyClickEventStep] {
    guard (1...2).contains(clickCount) else {
        throw ComputerUseError.message(
            "click_method 'sky_click' supports click_count 1 or 2"
        )
    }

    var steps = [
        SkyClickEventStep(kind: .moved, pointKind: .target, clickState: 0, phase: 2, delayAfter: 0.015),
        SkyClickEventStep(kind: .down, pointKind: .primer, clickState: 1, phase: 1, delayAfter: 0.001),
        SkyClickEventStep(kind: .up, pointKind: .primer, clickState: 1, phase: 2, delayAfter: 0.100),
    ]

    for pairIndex in 1...clickCount {
        steps.append(
            SkyClickEventStep(
                kind: .down,
                pointKind: .target,
                clickState: Int64(pairIndex),
                phase: 3,
                delayAfter: 0.001
            )
        )
        steps.append(
            SkyClickEventStep(
                kind: .up,
                pointKind: .target,
                clickState: Int64(pairIndex),
                phase: 3,
                delayAfter: pairIndex < clickCount ? 0.080 : 0
            )
        )
    }

    return steps
}

/// Owner check for click targets, the same as for keyboard targets: a covered window or one on another Space is a
/// valid target as long as it still exists and belongs to the snapshot's process. Events are addressed to the pid and
/// carry the window number, so they reach the window wherever it is.
func skyClickWindowMatchesTarget(
    windowInfo: [[String: Any]],
    windowID: CGWindowID,
    pid: pid_t
) -> Bool {
    skyKeyWindowMatchesTarget(windowInfo: windowInfo, windowID: windowID, pid: pid)
}

/// Pure. A target that the window server does not report on screen (minimized, hidden app, Stage Manager strip) is
/// clicked only when accessibility positively reads it as not minimized: an unreadable or unlisted window could be
/// minimized, and nobody has verified whether the activation records restore a minimized window.
func skyClickTargetVisibilityAllowed(isOnscreen: Bool, isMinimized: Bool?) -> Bool {
    isMinimized != true && (isOnscreen || isMinimized == false)
}

/// Pure. When the target app is frontmost no synthetic focus is used, so a click reaches the window the way a real
/// one would: AppKit makes a non-key window key and orders it front, and ordering front a window on another Space
/// switches Space. The window must therefore already be the app's focused window and positively on the current
/// Space, as for `sky_key`.
func skyClickFrontmostTargetAllowed(focusedWindowID: CGWindowID?, targetWindowID: CGWindowID, isOnCurrentSpace: Bool?) -> Bool {
    focusedWindowID == targetWindowID && isOnCurrentSpace == true
}

/// The live reads `SkyClickDispatcher.validate` makes under the synthetic-focus lock. Production uses `.live`; unit
/// tests replace them to drive each refusal without posting events.
struct SkyClickValidationProbes {
    /// Throws when the target must not receive input: hidden app, missing or foreign window, minimized window.
    var targetWindow: (CGWindowID, pid_t) throws -> SkyLightTargetWindowState
    var session: () -> MacSessionSnapshot
    /// Nil when the window's Space or the current Space cannot be read.
    var isOnCurrentSpace: (CGWindowID) -> Bool?
    var frontmostPID: () -> pid_t?
    /// The window id the app's `AXFocusedWindow` maps to, or nil when it cannot be read.
    var focusedWindowID: (pid_t) -> CGWindowID?

    static func live(sessionState: MacSessionStateProvider) -> SkyClickValidationProbes {
        SkyClickValidationProbes(
            targetWindow: { try validateSkyLightTargetWindow(windowID: $0, pid: $1, methodName: "sky_click") },
            session: { sessionState.currentSnapshot() },
            isOnCurrentSpace: { SkyLightWindowServerSPI.shared.windowIsOnCurrentSpace($0) },
            frontmostPID: { NSWorkspace.shared.frontmostApplication?.processIdentifier },
            focusedWindowID: SkyKeyboardDispatcher.focusedWindowID(pid:)
        )
    }
}

enum SkyClickDispatcher {
    private static let primerScreenPoint = CGPoint(x: -1, y: -1)
    private static let primerWindowPoint = CGPoint(x: -1, y: -1)

    // Raw private event fields used by the Chromium-compatible Cua Driver path.
    private enum EventField {
        static let gesturePhase: UInt32 = 0
        static let clickState: UInt32 = 1
        static let buttonNumber: UInt32 = 3
        static let subtype: UInt32 = 7
        static let targetPID: UInt32 = 40
        static let windowNumber: UInt32 = 51
        static let clickGroupID: UInt32 = 58
        static let windowUnderPointer: UInt32 = 91
        static let handlingWindowUnderPointer: UInt32 = 92
    }

    static func click(
        target: SkyClickTarget,
        clickCount: Int,
        spi: SkyLightSPI = .shared,
        sessionState: MacSessionStateProvider = SystemMacSessionStateProvider()
    ) throws {
        guard spi.capability.isAvailable else {
            throw ComputerUseError.message(
                "click_method 'sky_click' is unavailable: \(spi.capability.unavailableReason)"
            )
        }

        SkyLightSPI.syntheticFocusLock.lock()
        defer {
            SkyLightSPI.syntheticFocusLock.unlock()
        }

        let usesSyntheticFocus = try validate(target: target, probes: .live(sessionState: sessionState))
        let recipe = try skyClickEventRecipe(clickCount: clickCount)
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw ComputerUseError.message("Failed to create SkyLight HID event source.")
        }

        // Cua uses the nanosecond component of wall-clock time here, which is
        // always below one billion. Keep the same narrow raw-field range;
        // WindowServer does not publish field 58's accepted width.
        let clickGroupID = Int64(DispatchTime.now().uptimeNanoseconds % 1_000_000_000)

        let focusContext: SkyLightSyntheticFocusContext?
        if usesSyntheticFocus {
            focusContext = try spi.beginSyntheticTargetFocus(
                targetPID: target.pid,
                targetWindowID: target.windowID
            )
        } else {
            focusContext = nil
        }

        do {
            for step in recipe {
                let screenPoint = step.pointKind == .target ? target.screenPoint : primerScreenPoint
                let windowPoint = step.pointKind == .target ? target.windowPoint : primerWindowPoint
                guard let event = CGEvent(
                    mouseEventSource: source,
                    mouseType: step.kind.cgEventType,
                    mouseCursorPosition: screenPoint,
                    mouseButton: .left
                ) else {
                    throw ComputerUseError.message(
                        "Failed to create sky_click mouse event \(step.kind.cgEventType.rawValue)."
                    )
                }

                try stamp(
                    event,
                    target: target,
                    windowPoint: windowPoint,
                    clickState: step.clickState,
                    phase: step.phase,
                    clickGroupID: clickGroupID,
                    spi: spi
                )

                // The current Cua Driver Chromium recipe deliberately posts through
                // both channels: SkyLight reaches Chromium/Catalyst while the public
                // path preserves AppKit compatibility. This is one dispatch policy,
                // not a retry after an observed failure.
                try spi.postToPid(event, pid: target.pid)
                event.postToPid(target.pid)

                if step.delayAfter > 0 {
                    Thread.sleep(forTimeInterval: step.delayAfter)
                }
            }
        } catch {
            if let focusContext {
                try? spi.endSyntheticTargetFocus(focusContext)
            }
            throw error
        }

        if let focusContext {
            // SkyLight delivery is asynchronous. Keep the target's AppKit
            // synthetic active state long enough for Chromium's renderer hop
            // to consume the final mouse-up before deactivating only the target.
            Thread.sleep(forTimeInterval: 0.100)
            try spi.endSyntheticTargetFocus(focusContext)
        }
    }

    /// Every check before an event is posted, read under the shared lock right before acting. Returns whether the
    /// click needs the target-only synthetic focus, which is the case unless the target app is frontmost.
    static func validate(target: SkyClickTarget, probes: SkyClickValidationProbes) throws -> Bool {
        guard
            target.screenPoint.x.isFinite,
            target.screenPoint.y.isFinite,
            target.windowPoint.x.isFinite,
            target.windowPoint.y.isFinite,
            target.windowBounds.width > 0,
            target.windowBounds.height > 0
        else {
            throw ComputerUseError.message("sky_click requires finite target coordinates and window bounds")
        }

        let localBounds = CGRect(origin: .zero, size: target.windowBounds.size)
        guard localBounds.contains(target.windowPoint) else {
            throw ComputerUseError.message("sky_click target is outside the snapshot window bounds")
        }

        // Hidden app, missing or foreign window, minimized window: refused before any event is posted.
        let window = try probes.targetWindow(target.windowID, target.pid)
        guard skyClickTargetVisibilityAllowed(isOnscreen: window.isOnscreen, isMinimized: window.isMinimized) else {
            throw ComputerUseError.stateUnavailable(
                "sky_click target window is not on screen and accessibility could not confirm that it is not minimized, "
                    + "so it sent nothing. Run get_app_state again; sky_click does not change window visibility."
            )
        }

        // The Space is read at most once, and only when an answer depends on it.
        var cachedSpace: Bool??
        func isOnCurrentSpace() -> Bool? {
            if let cachedSpace {
                return cachedSpace
            }
            let space = probes.isOnCurrentSpace(target.windowID)
            cachedSpace = .some(space)
            return space
        }

        let session = probes.session()
        if !sessionIsStrictlyUnlocked(session),
           skyClickRequiresStrictUnlock(isOnscreen: window.isOnscreen, isOnCurrentSpace: isOnCurrentSpace())
        {
            try requireStrictlyUnlocked(
                session,
                subject: "\(skyClickMethodLabel) on a window that is not on screen on the current Space"
            )
        }

        guard probes.frontmostPID() == target.pid else {
            return true
        }
        guard skyClickFrontmostTargetAllowed(
            focusedWindowID: probes.focusedWindowID(target.pid),
            targetWindowID: target.windowID,
            isOnCurrentSpace: isOnCurrentSpace()
        ) else {
            throw ComputerUseError.stateUnavailable(
                "sky_click target app is frontmost, but the snapshot's window is not its focused window on the current "
                    + "Space. Clicking it would make it key, raise it or switch Space, so sky_click sent nothing. "
                    + "Run get_app_state again, or use the default click method."
            )
        }
        return false
    }

    private static func stamp(
        _ event: CGEvent,
        target: SkyClickTarget,
        windowPoint: CGPoint,
        clickState: Int64,
        phase: Int64,
        clickGroupID: Int64,
        spi: SkyLightSPI
    ) throws {
        let windowID = Int64(target.windowID)
        try spi.setIntegerField(event, field: EventField.gesturePhase, value: phase)
        try spi.setIntegerField(event, field: EventField.clickState, value: clickState)
        try spi.setIntegerField(event, field: EventField.buttonNumber, value: 0)
        try spi.setIntegerField(event, field: EventField.subtype, value: 3)
        try spi.setIntegerField(event, field: EventField.targetPID, value: Int64(target.pid))
        try spi.setIntegerField(event, field: EventField.windowNumber, value: windowID)
        try spi.setIntegerField(event, field: EventField.clickGroupID, value: clickGroupID)
        try spi.setIntegerField(event, field: EventField.windowUnderPointer, value: windowID)
        try spi.setIntegerField(event, field: EventField.handlingWindowUnderPointer, value: windowID)
        try spi.setWindowLocation(event, point: windowPoint)
    }

}
