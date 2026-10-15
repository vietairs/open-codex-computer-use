import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

struct SkyKeyboardTarget: Equatable {
    let windowID: CGWindowID
    let pid: pid_t
}

/// What a finished `sky_key` delivery reports. The keys were delivered; `releaseWarning` is set when the target's
/// synthetic key-window state could not be released afterwards. That is not an action failure: reporting it as one
/// would invite a retry that types the text or presses the key a second time.
struct SkyKeyboardDelivery: Equatable {
    let releaseWarning: String?
}

func skyKeyReleaseWarningNote(_ reason: String) -> String {
    "Note: sky_key delivered the keys, but could not release the target app's background key-window state (\(reason)). "
        + "Do not send the keys again. The app may behave as if it were active until it is next activated or deactivated."
}

/// `sky_key` refuses whenever the screen is locked or its lock state is unknown. `OPEN_COMPUTER_USE_ALLOW_LOCKED`
/// does not change this: the opt-in covers accessibility and pid-posted input only, and nobody has verified what
/// synthetic activation and key-window records do while the login window owns the screen.
func requireUnlockedForSkyKey(_ snapshot: MacSessionSnapshot) throws {
    guard snapshot.isLocked || snapshot.isUnknown else {
        return
    }
    throw ComputerUseError.stateUnavailable(
        "key_method 'sky_key' cannot run while macOS is locked or its lock state is unknown, even when "
            + "\(MacSessionLockPolicy.environmentKey) is set. Unlock the Mac and retry."
    )
}

/// A command chord expressed the way AppKit menus advertise their key equivalents: `AXMenuItemCmdChar` plus the
/// `AXMenuItemCmdModifiers` bitmask (1 = shift, 2 = option, 4 = control; 8 marks a non-command equivalent).
struct SkyMenuKeyEquivalent: Equatable, Sendable {
    let character: String
    let modifiers: Int
}

/// AppKit dispatches menu key equivalents (`cmd+a`, `cmd+c`, `cmd+t`, ...) through `NSMenu`, which only fires for
/// the active app, so a background target needs the menu item pressed directly: the item the user's keypress would
/// have triggered. Only a single-character key with a command modifier maps to a menu equivalent; everything else
/// (arrows, return, plain characters, non-command chords) is delivered as key events.
func skyMenuKeyEquivalent(for parsed: ParsedKeyPress) -> SkyMenuKeyEquivalent? {
    guard parsed.modifiers.contains(where: { $0.flag == .maskCommand }),
          parsed.displayValue.count == 1
    else {
        return nil
    }

    var modifiers = 0
    for modifier in parsed.modifiers {
        switch modifier.flag {
        case .maskShift:
            modifiers |= 1
        case .maskAlternate:
            modifiers |= 2
        case .maskControl:
            modifiers |= 4
        default:
            break
        }
    }
    return SkyMenuKeyEquivalent(character: parsed.displayValue.uppercased(), modifiers: modifiers)
}

/// A menu item matches only when it reports itself enabled. An unknown enabled state counts as disabled: `AXPress`
/// does not re-validate the item, so pressing one whose state is unknown could run a command the app would refuse.
func skyMenuItemMatches(cmdChar: String?, cmdModifiers: Int?, enabled: Bool?, equivalent: SkyMenuKeyEquivalent) -> Bool {
    guard let cmdChar, enabled == true else {
        return false
    }
    return cmdChar.uppercased() == equivalent.character && (cmdModifiers ?? 0) == equivalent.modifiers
}

/// Bounds for one menu-bar walk. The walk runs while the target is synthetic-active and while the shared synthetic
/// focus lock is held, so a huge or unresponsive menu must not stall every other session.
struct SkyMenuWalkLimits: Equatable {
    var maxNodes: Int
    /// Node depth below a menu-bar item: its menu is 1, that menu's items 2, a submenu 3, the submenu's items 4.
    var maxDepth: Int
    var timeBudget: TimeInterval

    static let standard = SkyMenuWalkLimits(maxNodes: 1_500, maxDepth: 4, timeBudget: 1.0)
}

enum SkyMenuSearchResult<Element> {
    case noMatch
    case match(Element)
    /// More than one enabled item matches; pressing either would be a guess.
    case ambiguous
    /// The walk ran out of nodes or time before it could rule out a second match.
    case budgetExhausted
}

extension SkyMenuSearchResult: Equatable where Element: Equatable {}

/// Pure. Walks the menu-bar items depth-first and returns the single matching item.
///
/// The first menu-bar item is the Apple menu, whose items act on the whole login session (Log Out, Lock Screen,
/// Force Quit), not on the target app, so it is never searched. The second is the application menu; only its own
/// items are searched, not its submenus, which keeps the system-provided Services menu out of reach.
func skyFindMenuItem<Element>(
    menuBarItems: [Element],
    limits: SkyMenuWalkLimits = .standard,
    now: () -> TimeInterval,
    children: (Element) -> [Element],
    matches: (Element) -> Bool
) -> SkyMenuSearchResult<Element> {
    let applicationMenuMaxDepth = 2
    let deadline = now() + limits.timeBudget
    var visited = 0
    var found: Element?

    for (index, barItem) in menuBarItems.enumerated() where index > 0 {
        let maxDepth = index == 1 ? min(applicationMenuMaxDepth, limits.maxDepth) : limits.maxDepth
        var stack: [(element: Element, depth: Int)] = [(barItem, 0)]
        while case let (element, depth)? = stack.popLast() {
            visited += 1
            guard visited <= limits.maxNodes, now() <= deadline else {
                return .budgetExhausted
            }

            if depth > 0, matches(element) {
                if found != nil {
                    return .ambiguous
                }
                found = element
            }

            if depth < maxDepth {
                stack.append(contentsOf: children(element).reversed().map { ($0, depth + 1) })
            }
        }
    }

    guard let found else {
        return .noMatch
    }
    return .match(found)
}

/// Owner check for keyboard targets. Unlike `sky_click`, the window does not need to be on-screen: keyboard
/// delivery is process-addressed, so a window on another Space is a valid target as long as it still exists and
/// belongs to the snapshot's process.
func skyKeyWindowMatchesTarget(
    windowInfo: [[String: Any]],
    windowID: CGWindowID,
    pid: pid_t
) -> Bool {
    windowInfo.contains { info in
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

/// `sky_key`: deliver keyboard input to a background window without changing the real foreground app.
///
/// Keyboard events posted to a pid reach any AppKit window, but Chromium and Electron only insert text while their
/// NSWindow is key. The sequence therefore reuses the `sky_click` target-only synthetic-active state, posts the
/// key-window record pair so the target app makes the window key internally, confirms through accessibility that
/// it did, delivers the ordinary `CGEvent.postToPid` keyboard events (or presses the matching menu item for a
/// command chord), and releases the synthetic state again. The real frontmost app keeps its active, key and
/// first-responder state throughout; the target is never raised and the pointer never moves.
enum SkyKeyboardDispatcher {
    /// The records and key events are ordered, but the target processes them asynchronously; live testing dropped
    /// occasional keys with no delay at all, so a small fixed margin stays on both sides of the delivery.
    static let keyWindowSettle: TimeInterval = 0.010
    static let releaseSettle: TimeInterval = 0.010
    /// How long the target's AX focused window may take to report the target after the key-window records.
    static let keyWindowConfirmTimeout: TimeInterval = 0.250
    static let keyWindowPollInterval: TimeInterval = 0.010
    /// Matches the settle `InputSimulation.pressKey` keeps after a key press.
    static let menuPressSettle: TimeInterval = 0.100
    /// Per-element AX messaging timeout, so a busy target cannot hold the shared lock for the default AX timeout.
    static let accessibilityMessagingTimeout: Float = 0.5

    @discardableResult
    static func typeText(
        target: SkyKeyboardTarget,
        text: String,
        spi: SkyLightSPI = .shared,
        sessionState: MacSessionStateProvider = SystemMacSessionStateProvider()
    ) throws -> SkyKeyboardDelivery {
        try deliver(to: target, spi: spi, sessionState: sessionState) {
            try InputSimulation.typeText(text, pid: target.pid)
        }
    }

    @discardableResult
    static func pressKey(
        target: SkyKeyboardTarget,
        key: String,
        spi: SkyLightSPI = .shared,
        sessionState: MacSessionStateProvider = SystemMacSessionStateProvider()
    ) throws -> SkyKeyboardDelivery {
        // Reject a bad key spec before touching the target's focus state.
        let parsed = try KeyPressParser.parse(key)
        let equivalent = skyMenuKeyEquivalent(for: parsed)
        return try deliver(to: target, spi: spi, sessionState: sessionState) {
            if let equivalent {
                switch menuItem(matching: equivalent, pid: target.pid) {
                case let .match(item):
                    let result = AXUIElementPerformAction(item, kAXPressAction as CFString)
                    guard result == .success else {
                        throw ComputerUseError.message(
                            "sky_key could not press the menu item for '\(key)' (AXError \(result.rawValue))"
                        )
                    }
                    Thread.sleep(forTimeInterval: menuPressSettle)
                    return
                case .ambiguous:
                    throw ComputerUseError.message(
                        "sky_key found more than one enabled menu item for '\(key)' in the target app and pressed none of them."
                    )
                case .budgetExhausted:
                    throw ComputerUseError.message(
                        "sky_key could not finish reading the target app's menu bar in time and pressed nothing for '\(key)'."
                    )
                case .noMatch:
                    break
                }
            }

            try InputSimulation.pressKey(key, pid: target.pid)
        }
    }

    private static func deliver(
        to target: SkyKeyboardTarget,
        spi: SkyLightSPI,
        sessionState: MacSessionStateProvider,
        _ body: () throws -> Void
    ) throws -> SkyKeyboardDelivery {
        SkyLightSPI.syntheticFocusLock.lock()
        defer {
            SkyLightSPI.syntheticFocusLock.unlock()
        }

        // Read under the lock, right before acting: waiting for another session's sequence can take a while.
        try requireUnlockedForSkyKey(sessionState.currentSnapshot())

        guard spi.capability.isAvailable else {
            throw ComputerUseError.message(
                "\(skyKeyMethodLabel) is unavailable: \(spi.capability.unavailableReason)"
            )
        }

        try validate(target: target)

        if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid {
            // Making a window key here would change the user's own key window, so the snapshot's window must
            // already be key.
            try requireTargetWindowIsKey(target, timeout: 0)
            try body()
            return SkyKeyboardDelivery(releaseWarning: nil)
        }

        let focusContext = try spi.beginSyntheticTargetFocus(
            targetPID: target.pid,
            targetWindowID: target.windowID,
            methodLabel: skyKeyMethodLabel
        )
        do {
            try spi.makeSyntheticTargetWindowKey(focusContext)
            Thread.sleep(forTimeInterval: keyWindowSettle)
            try requireTargetWindowIsKey(target, timeout: keyWindowConfirmTimeout)
            try body()
            Thread.sleep(forTimeInterval: releaseSettle)
        } catch {
            try? spi.endSyntheticTargetFocus(focusContext, methodLabel: skyKeyMethodLabel)
            throw error
        }

        do {
            try spi.endSyntheticTargetFocus(focusContext, methodLabel: skyKeyMethodLabel)
        } catch {
            let reason = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            fputs("[open-computer-use] sky_key delivered the keys but could not release pid \(target.pid): \(reason)\n", stderr)
            return SkyKeyboardDelivery(releaseWarning: reason)
        }
        return SkyKeyboardDelivery(releaseWarning: nil)
    }

    private static func validate(target: SkyKeyboardTarget) throws {
        // A hidden app never makes its windows key, so keys would be silently dropped. Fail closed instead of
        // unhiding on the user's behalf.
        if NSRunningApplication(processIdentifier: target.pid)?.isHidden == true {
            throw ComputerUseError.stateUnavailable(
                "sky_key target app is hidden. Unhide it first; sky_key does not change window visibility."
            )
        }

        // `.optionAll`, not `.optionIncludingWindow`: the latter omits windows that are off-screen (hidden app,
        // minimized, or on another Space).
        let windowInfo = CGWindowListCopyWindowInfo(
            [.optionAll],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []
        guard skyKeyWindowMatchesTarget(
            windowInfo: windowInfo,
            windowID: target.windowID,
            pid: target.pid
        ) else {
            throw ComputerUseError.stateUnavailable(
                "sky_key target window no longer exists or is no longer owned by the target app. Run get_app_state again."
            )
        }
    }

    /// Fails closed unless the target app's focused window is the snapshot's window. A window that cannot become
    /// key (a minimized window, one behind a modal sheet) would otherwise send the keys to whichever window of the
    /// app is key, such as another document or a login sheet.
    private static func requireTargetWindowIsKey(_ target: SkyKeyboardTarget, timeout: TimeInterval) throws {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while true {
            if focusedWindowID(pid: target.pid) == target.windowID {
                return
            }
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                throw ComputerUseError.stateUnavailable(
                    "sky_key could not make the snapshot's window the key window of the target app, so it sent no keys. "
                        + "The window may be minimized or blocked by a sheet or dialog. Run get_app_state again."
                )
            }
            Thread.sleep(forTimeInterval: keyWindowPollInterval)
        }
    }

    private static func focusedWindowID(pid: pid_t) -> CGWindowID? {
        let application = AXUIElementCreateApplication(pid)
        guard let window = accessibilityElement(copyValue(application, kAXFocusedWindowAttribute)) else {
            return nil
        }
        return accessibilityWindowID(of: window)
    }

    // MARK: - Menu-bar key equivalents

    private static func menuItem(matching equivalent: SkyMenuKeyEquivalent, pid: pid_t) -> SkyMenuSearchResult<AXUIElement> {
        let application = AXUIElementCreateApplication(pid)
        guard let menuBar = accessibilityElement(copyValue(application, kAXMenuBarAttribute)) else {
            return .noMatch
        }

        return skyFindMenuItem(
            menuBarItems: children(of: menuBar),
            now: { ProcessInfo.processInfo.systemUptime },
            children: children(of:),
            matches: { element in
                guard copyValue(element, kAXRoleAttribute) as? String == kAXMenuItemRole as String else {
                    return false
                }
                // Read the remaining attributes only for an item whose character already matches.
                guard let cmdChar = copyValue(element, "AXMenuItemCmdChar") as? String,
                      cmdChar.uppercased() == equivalent.character
                else {
                    return false
                }
                return skyMenuItemMatches(
                    cmdChar: cmdChar,
                    cmdModifiers: (copyValue(element, "AXMenuItemCmdModifiers") as? NSNumber)?.intValue,
                    enabled: (copyValue(element, kAXEnabledAttribute) as? NSNumber)?.boolValue,
                    equivalent: equivalent
                )
            }
        )
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        (copyValue(element, kAXChildrenAttribute) as? [AnyObject] ?? []).compactMap { accessibilityElement($0) }
    }

    /// The value as an `AXUIElement`, or nil when the target app returned anything else. The CF type is checked
    /// first, because the value comes from another process and a wrong type must not crash the shared agent.
    private static func accessibilityElement(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func copyValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(element, accessibilityMessagingTimeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }
}
