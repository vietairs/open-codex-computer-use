import ApplicationServices

/// Attribute values for one element, fetched in a single multi-attribute accessibility round trip.
struct AXAttributePrefetch {
    /// The attributes TreeRenderer.render reads for every node. AXFocused rides along so a background app, whose
    /// app-level AXFocusedUIElement is nil, still reveals its focused element without an extra round trip. The
    /// placeholder, title, role description and child-list attributes follow, so reading them costs no round trip of
    /// their own.
    static let renderAttributes: [String] = [
        kAXRoleAttribute, kAXSubroleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXValueAttribute,
        kAXIdentifierAttribute, kAXSelectedAttribute, kAXExpandedAttribute, kAXEnabledAttribute,
        kAXPositionAttribute, kAXSizeAttribute, kAXFocusedAttribute,
        "AXPlaceholderValue", "AXPlaceholder", kAXTitleAttribute, kAXRoleDescriptionAttribute,
        kAXChildrenAttribute, kAXRowsAttribute, "AXContents", "AXVisibleChildren",
    ]

    /// What listing a node's children reads: its role, every child list, and its frame (to keep only visible rows).
    static let childListAttributes: [String] = [
        kAXRoleAttribute, kAXChildrenAttribute, kAXRowsAttribute, "AXContents", "AXVisibleChildren",
        kAXPositionAttribute, kAXSizeAttribute,
    ]

    /// What flattening row text and summarizing a text container read per node.
    static let textWalkAttributes: [String] = [
        kAXRoleAttribute, kAXValueAttribute, kAXTitleAttribute, kAXChildrenAttribute,
    ]

    /// A row's frame, to test whether it is visible.
    static let frameAttributes: [String] = [kAXPositionAttribute, kAXSizeAttribute]

    private let requested: Set<String>
    private let values: [String: CFTypeRef]

    init(requested: [String], values: [String: CFTypeRef]) {
        self.requested = Set(requested)
        self.values = values
    }

    /// nil when the multi-attribute call itself fails or returns a different count: callers then fall back to single reads.
    static func fetch(_ element: AXUIElement, attributes: [String] = renderAttributes) -> AXAttributePrefetch? {
        let (error, rawArray) = AccessibilityReads.backend.copyMultipleAttributeValues(element, attributes)
        guard error == .success, let rawArray, CFArrayGetCount(rawArray) == attributes.count else {
            return nil
        }

        var rawValues: [CFTypeRef] = []
        rawValues.reserveCapacity(attributes.count)
        for slot in 0..<attributes.count {
            guard let pointer = CFArrayGetValueAtIndex(rawArray, slot) else {
                return nil
            }
            rawValues.append(Unmanaged<CFTypeRef>.fromOpaque(pointer).takeUnretainedValue())
        }

        return AXAttributePrefetch(
            requested: attributes,
            values: normalize(attributes: attributes, rawValues: rawValues)
        )
    }

    /// Pure. Maps raw values to a dictionary, dropping AXValue error sentinels (AXValueGetType == .axError) and kCFNull.
    /// Returns [:] when attributes.count != rawValues.count.
    static func normalize(attributes: [String], rawValues: [CFTypeRef]) -> [String: CFTypeRef] {
        guard attributes.count == rawValues.count else {
            return [:]
        }

        var normalized: [String: CFTypeRef] = [:]
        for (attribute, raw) in zip(attributes, rawValues) {
            let typeID = CFGetTypeID(raw)
            if typeID == CFNullGetTypeID() {
                continue
            }
            if typeID == AXValueGetTypeID(), AXValueGetType(raw as! AXValue) == .axError {
                continue
            }
            normalized[attribute] = raw
        }
        return normalized
    }

    /// The attribute was requested, so this prefetch is authoritative for it even when its value is absent.
    func covers(_ attribute: String) -> Bool {
        requested.contains(attribute)
    }

    /// nil = requested but absent (error/null), same as a failed single read.
    func value(_ attribute: String) -> CFTypeRef? {
        values[attribute]
    }
}

/// Pure routing: a covered attribute comes from the prefetch (live is NOT called); otherwise live() is called.
func prefetchedOrLive(_ prefetch: AXAttributePrefetch?, _ attribute: String, live: () -> CFTypeRef?) -> CFTypeRef? {
    if let prefetch, prefetch.covers(attribute) {
        return prefetch.value(attribute)
    }
    return live()
}
