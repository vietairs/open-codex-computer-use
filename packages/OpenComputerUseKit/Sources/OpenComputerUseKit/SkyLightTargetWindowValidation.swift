import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// True only when the session is known to be unlocked. An unknown lock state counts as locked.
func sessionIsStrictlyUnlocked(_ snapshot: MacSessionSnapshot) -> Bool {
    !snapshot.isLocked && !snapshot.isUnknown
}

/// Refuses `subject` whenever the screen is locked or its lock state is unknown. `OPEN_COMPUTER_USE_ALLOW_LOCKED` does
/// not change this: the opt-in covers accessibility and pid-posted input to on-screen windows only, and nobody has
/// verified what synthetic activation records, or input to a window on another Space, do while the login window owns
/// the screen.
func requireStrictlyUnlocked(_ snapshot: MacSessionSnapshot, subject: String) throws {
    guard !sessionIsStrictlyUnlocked(snapshot) else {
        return
    }
    throw ComputerUseError.stateUnavailable(
        "\(subject) cannot run while macOS is locked or its lock state is unknown, even when "
            + "\(MacSessionLockPolicy.environmentKey) is set. Unlock the Mac and retry."
    )
}

/// Pure. `sky_click` keeps the lock policy it always had for an on-screen window on the current Space. Any other
/// window (another Space, or a Space that cannot be read) needs a strictly unlocked session.
func skyClickRequiresStrictUnlock(isOnscreen: Bool, isOnCurrentSpace: Bool?) -> Bool {
    !(isOnscreen && isOnCurrentSpace == true)
}

/// The window-list entry for `windowID` when `pid` owns it, from a list read with `.optionAll`.
func skyLightTargetWindowEntry(
    windowInfo: [[String: Any]],
    windowID: CGWindowID,
    pid: pid_t
) -> [String: Any]? {
    windowInfo.first { info in
        guard
            let number = info[kCGWindowNumber as String] as? NSNumber,
            number.uint32Value == windowID,
            let ownerPID = info[kCGWindowOwnerPID as String] as? NSNumber
        else {
            return false
        }
        return ownerPID.int32Value == pid
    }
}

/// The checks `sky_click` and `sky_key` share before any record is posted: the app is not hidden, the window still
/// exists and belongs to the snapshot's process, and it is not minimized. Returns whether the window server reports
/// the window on screen. `methodName` (`sky_click`, `sky_key`) names the method in the error text.
@discardableResult
func validateSkyLightTargetWindow(windowID: CGWindowID, pid: pid_t, methodName: String) throws -> Bool {
    // A hidden app never makes its windows key or handles their events, so input would be silently dropped. Fail
    // closed instead of unhiding on the user's behalf.
    if NSRunningApplication(processIdentifier: pid)?.isHidden == true {
        throw ComputerUseError.stateUnavailable(
            "\(methodName) target app is hidden. Unhide it first; \(methodName) does not change window visibility."
        )
    }

    // `.optionAll`, not `.optionIncludingWindow`: the latter omits windows that are off-screen (hidden app,
    // minimized, or on another Space).
    let windowInfo = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    guard let entry = skyLightTargetWindowEntry(windowInfo: windowInfo, windowID: windowID, pid: pid) else {
        throw ComputerUseError.stateUnavailable(
            "\(methodName) target window no longer exists or is no longer owned by the target app. Run get_app_state again."
        )
    }

    // Checked before any record is posted: nobody has verified whether the activation or key-window records would
    // restore a minimized window, which would be a visible change.
    let windows = (skyLightCopyValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AnyObject] ?? [])
        .compactMap { skyLightAccessibilityElement($0) }
    let isMinimized = skyKeyWindowIsMinimized(
        windows: windows,
        windowID: windowID,
        windowIDOf: accessibilityWindowID(of:),
        isMinimized: { window in
            AXUIElementSetMessagingTimeout(window, SkyKeyboardDispatcher.accessibilityMessagingTimeout)
            return accessibilityWindowIsMinimized(window)
        }
    )
    if isMinimized {
        throw ComputerUseError.stateUnavailable(
            "\(methodName) target window is minimized, so it sent nothing. Restore the window first; \(methodName) does not change window visibility."
        )
    }

    return (entry[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
}

/// The value as an `AXUIElement`, or nil when the target app returned anything else. The CF type is checked first,
/// because the value comes from another process and a wrong type must not crash the shared agent.
func skyLightAccessibilityElement(_ value: CFTypeRef?) -> AXUIElement? {
    guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
        return nil
    }
    return unsafeDowncast(value, to: AXUIElement.self)
}

/// One attribute read with the short per-element messaging timeout, so a busy target cannot hold the shared synthetic
/// focus lock for the default AX timeout.
func skyLightCopyValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    AXUIElementSetMessagingTimeout(element, SkyKeyboardDispatcher.accessibilityMessagingTimeout)
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
        return nil
    }
    return value
}
