import ApplicationServices
import CoreGraphics
import Foundation

/// Reads accessibility nodes for `find_elements` with one batched attribute call per node, which is what makes the
/// early-stopping walk cheaper than rendering the whole tree.
struct AccessibilityElementSearchSource: ElementSearchNodeSource {
    typealias Node = AXUIElement

    /// Order matters: `read` decodes by position.
    static let batchedAttributes: [String] = [
        kAXRoleAttribute as String,
        kAXSubroleAttribute as String,
        kAXTitleAttribute as String,
        kAXDescriptionAttribute as String,
        kAXIdentifierAttribute as String,
        kAXEnabledAttribute as String,
        kAXChildrenAttribute as String,
        kAXRowsAttribute as String,
        "AXContents",
        "AXVisibleChildren",
    ]

    /// Table-like nodes can have thousands of rows. Only the first rows are followed, without the visibility filter
    /// the full snapshot applies; a row scrolled out of view is made unclickable when it becomes a hit.
    static let rowCap = 20

    private enum Slot {
        static let role = 0
        static let subrole = 1
        static let title = 2
        static let description = 3
        static let identifier = 4
        static let enabled = 5
        static let children = 6
        static let rows = 7
        static let contents = 8
        static let visibleChildren = 9
    }

    func read(_ node: AXUIElement) -> (attributes: ElementSearchNodeAttributes, children: [AXUIElement]) {
        let values = elementSearchCopyBatchedValues(of: node, attributes: Self.batchedAttributes)
        let role = elementSearchString(values[Slot.role])
        let attributes = ElementSearchNodeAttributes(
            role: role,
            subrole: elementSearchString(values[Slot.subrole]),
            title: elementSearchString(values[Slot.title]),
            description: elementSearchString(values[Slot.description]),
            identifier: elementSearchString(values[Slot.identifier]),
            enabled: values[Slot.enabled] as? Bool
        )

        let childrenValues = elementSearchElements(values[Slot.children])
        let rows = Array(elementSearchElements(values[Slot.rows]).prefix(Self.rowCap))
        let contents = elementSearchElements(values[Slot.contents])
        let visibleChildren = elementSearchElements(values[Slot.visibleChildren])

        var children: [AXUIElement] = []
        let traversal = childTraversalAttributes(
            role: role,
            hasRows: !rows.isEmpty,
            hasVisibleChildren: !visibleChildren.isEmpty
        )
        for attribute in traversal {
            let source: [AXUIElement]
            switch attribute {
            case kAXChildrenAttribute: source = childrenValues
            case kAXRowsAttribute: source = rows
            case "AXContents": source = contents
            case "AXVisibleChildren": source = visibleChildren
            default: source = []
            }
            for child in source where !children.contains(where: { CFEqual($0, child) }) {
                children.append(child)
            }
        }

        return (attributes, children)
    }

    func isSameNode(_ lhs: AXUIElement, _ rhs: AXUIElement) -> Bool {
        CFEqual(lhs, rhs)
    }
}

// MARK: - Batched attribute decoding

/// One `AXUIElementCopyMultipleAttributeValues` call, through the snapshot walk's `AXAttributePrefetch`. The result
/// has one entry per requested attribute, in order; an attribute that could not be read (and any call-level failure)
/// is `nil`.
private func elementSearchCopyBatchedValues(of element: AXUIElement, attributes: [String]) -> [CFTypeRef?] {
    let prefetch = AXAttributePrefetch.fetch(element, attributes: attributes)
    return attributes.map { prefetch?.value($0) }
}

private func elementSearchString(_ value: CFTypeRef?) -> String? {
    guard let value, CFGetTypeID(value) == CFStringGetTypeID(), let string = value as? String else {
        return nil
    }
    return string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : string
}

private func elementSearchElements(_ value: CFTypeRef?) -> [AXUIElement] {
    guard let value, CFGetTypeID(value) == CFArrayGetTypeID() else {
        return []
    }
    return value as? [AXUIElement] ?? []
}

private func elementSearchElement(_ value: CFTypeRef?) -> AXUIElement? {
    guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
        return nil
    }
    return (value as! AXUIElement)
}

private func elementSearchCopyElement(_ element: AXUIElement, attribute: String) -> AXUIElement? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
        return nil
    }
    return elementSearchElement(value)
}

// MARK: - Window resolution

struct ElementSearchWindowContext {
    let root: AXUIElement
    let windowID: CGWindowID
    let layer: Int
    let bounds: CGRect
    let title: String?
    let focusedElement: AXUIElement?
    /// Stage Manager holds the window off stage: `bounds` is its accessibility frame and pointer input is refused.
    let isOffStage: Bool
}

/// The window `find_elements` searches, chosen by the same rule a snapshot uses for its starting window
/// (`SnapshotBuilder.initialWindow`), so hits normally describe the window `get_app_state` shows. It is not an exact
/// match: the snapshot first enables the best-effort accessibility modes (such as `AXManualAccessibility` for Electron
/// apps), which can change which windows exist, and it can unhide a hidden app to find its window; this search does
/// neither. `systemWide` is a parameter only so tests can serve it from a fake accessibility tree.
func elementSearchWindowRoot(
    appElement: AXUIElement,
    appPID: pid_t,
    systemWide: AXUIElement = AXUIElementCreateSystemWide()
) -> AXUIElement? {
    SnapshotBuilder.initialWindow(
        appElement: appElement,
        appPID: appPID,
        focusedApplication: SnapshotBuilder.frontmostApplication(systemWide: systemWide),
        systemWide: systemWide
    )
}

/// The window `find_elements` searches (see `elementSearchWindowRoot`). It never activates the app, recovers a hidden
/// window or captures the screen. Window identity and bounds follow the same rules as a full snapshot: an off-stage
/// window is located by its own id and accessibility frame, and otherwise the window-server entry of the AX window's
/// own id is preferred, so hits merge into the snapshot of the same window.
func resolveElementSearchWindow(for app: RunningAppDescriptor) throws -> ElementSearchWindowContext {
    let appElement = AXUIElementCreateApplication(app.pid)

    guard let windowRoot = elementSearchWindowRoot(appElement: appElement, appPID: app.pid) else {
        throw ComputerUseError.stateUnavailable(computerUseNoWindowFoundMessage)
    }

    let title = elementSearchString(
        elementSearchCopyBatchedValues(of: windowRoot, attributes: [kAXTitleAttribute as String])[0]
    )
    let focusedElement = elementSearchCopyElement(appElement, attribute: kAXFocusedUIElementAttribute as String)

    if let offStage = liveOffStageWindow(for: windowRoot) {
        return ElementSearchWindowContext(
            root: windowRoot,
            windowID: offStage.windowID,
            layer: 0,
            bounds: offStage.accessibilityFrame,
            title: title,
            focusedElement: focusedElement,
            isOffStage: true
        )
    }

    guard let candidate = elementSearchWindowCandidate(
        pid: app.pid,
        titleHint: title,
        accessibilityWindowID: accessibilityWindowID(of: windowRoot)
    ) else {
        throw ComputerUseError.stateUnavailable(computerUseNoWindowFoundMessage)
    }

    return ElementSearchWindowContext(
        root: windowRoot,
        windowID: candidate.windowID,
        layer: candidate.layer,
        bounds: candidate.bounds,
        title: title,
        focusedElement: focusedElement,
        isOffStage: false
    )
}

/// Window id, layer and bounds from the window list, without capturing an image.
private func elementSearchWindowCandidate(
    pid: pid_t,
    titleHint: String?,
    accessibilityWindowID: CGWindowID?
) -> WindowCaptureCandidate? {
    guard let infoList = CGWindowListCopyWindowInfo([], kCGNullWindowID) as? [[String: Any]] else {
        return nil
    }

    let candidates = infoList.enumerated().compactMap { offset, info -> WindowCaptureCandidate? in
        guard
            let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
            ownerPID == pid,
            let number = info[kCGWindowNumber as String] as? NSNumber,
            let layer = info[kCGWindowLayer as String] as? Int,
            let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
            let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
        else {
            return nil
        }

        return WindowCaptureCandidate(
            windowID: CGWindowID(number.uint32Value),
            layer: layer,
            bounds: bounds,
            title: info[kCGWindowName as String] as? String,
            area: Int(bounds.width * bounds.height),
            frontToBackIndex: offset,
            isOnscreen: info[kCGWindowIsOnscreen as String] as? Bool ?? false
        )
    }

    // Read lazily, as the snapshot path does: only a window in front of the chosen one needs its modal flag.
    var nonModalWindowIDs: Set<CGWindowID>?
    return preferredWindowCaptureCandidate(
        candidates,
        titleHint: titleHint,
        preferredWindowID: accessibilityWindowID,
        isNonModalAccessibilityWindow: { windowID in
            if nonModalWindowIDs == nil {
                nonModalWindowIDs = elementSearchNonModalWindowIDs(pid: pid)
            }
            return nonModalWindowIDs?.contains(windowID) ?? false
        }
    )
}

/// The app's accessibility windows that report `AXModal == false`, by window-server id; the same input the snapshot
/// path gives `preferredWindowCaptureCandidate`, so a non-modal overlay such as Mail's search suggestions does not
/// replace the searched window.
private func elementSearchNonModalWindowIDs(pid: pid_t) -> Set<CGWindowID> {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &value) == .success else {
        return []
    }
    return nonModalAccessibilityWindowIDs(elementSearchElements(value).map { window in
        let modal = elementSearchCopyBatchedValues(of: window, attributes: [kAXModalAttribute as String])[0]
        return (windowID: accessibilityWindowID(of: window), isModal: modal.flatMap { $0 as? Bool })
    })
}

// MARK: - Hit details

/// Frame and actions for a hit. The frame is `nil` when the element sits outside the window, so `click` refuses it
/// instead of clicking a point outside the window.
func readElementSearchHitDetails(
    _ element: AXUIElement,
    windowBounds: CGRect
) -> (localFrame: CGRect?, rawActions: [String]) {
    let values = elementSearchCopyBatchedValues(
        of: element,
        attributes: [kAXPositionAttribute as String, kAXSizeAttribute as String]
    )

    var localFrame: CGRect?
    if let positionValue = values[0], let sizeValue = values[1],
       CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID()
    {
        var position = CGPoint.zero
        var size = CGSize.zero
        if AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
           AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        {
            localFrame = elementSearchClickableLocalFrame(
                elementFrame: CGRect(origin: position, size: size),
                windowBounds: windowBounds
            )
        }
    }

    var actions: CFArray?
    let rawActions: [String]
    if AXUIElementCopyActionNames(element, &actions) == .success {
        rawActions = actions as? [String] ?? []
    } else {
        rawActions = []
    }

    return (localFrame, rawActions)
}

/// Window-relative frame, or `nil` when the frame's midpoint lies outside the window (a table row scrolled out of
/// view, a control clipped away).
func elementSearchClickableLocalFrame(elementFrame: CGRect, windowBounds: CGRect) -> CGRect? {
    let local = windowRelativeFrame(elementFrame: elementFrame, windowBounds: windowBounds)
    let windowLocalBounds = CGRect(origin: .zero, size: windowBounds.size)
    let midpoint = CGPoint(x: local.midX, y: local.midY)
    return windowLocalBounds.contains(midpoint) ? local : nil
}
