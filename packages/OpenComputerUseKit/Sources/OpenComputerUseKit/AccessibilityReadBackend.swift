import ApplicationServices

/// The accessibility calls a snapshot's tree walk makes, behind one seam. Production always uses `live`; tests bind a
/// fake tree for the duration of a closure with `AccessibilityReads.$backend.withValue(_:operation:)`, so they can
/// render a tree without Accessibility permission and count round trips. Nothing global is mutated.
struct AccessibilityReadBackend: Sendable {
    var copyAttributeValue: @Sendable (AXUIElement, String) -> (AXError, CFTypeRef?)
    var copyMultipleAttributeValues: @Sendable (AXUIElement, [String]) -> (AXError, CFArray?)
    var copyActionNames: @Sendable (AXUIElement) -> (AXError, CFArray?)
    var isAttributeSettable: @Sendable (AXUIElement, String) -> (AXError, Bool)

    static let live = AccessibilityReadBackend(
        copyAttributeValue: { element, attribute in
            var value: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
            return (error, value)
        },
        copyMultipleAttributeValues: { element, attributes in
            var values: CFArray?
            // Options 0: one failed attribute does not stop the call; it yields an error sentinel in its slot.
            let error = AXUIElementCopyMultipleAttributeValues(
                element,
                attributes as CFArray,
                AXCopyMultipleAttributeOptions(rawValue: 0),
                &values
            )
            return (error, values)
        },
        copyActionNames: { element in
            var actions: CFArray?
            let error = AXUIElementCopyActionNames(element, &actions)
            return (error, actions)
        },
        isAttributeSettable: { element, attribute in
            var settable = DarwinBoolean(false)
            let error = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
            return (error, settable.boolValue)
        }
    )
}

enum AccessibilityReads {
    @TaskLocal static var backend: AccessibilityReadBackend = .live
}
