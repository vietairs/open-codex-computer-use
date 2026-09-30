import ApplicationServices

/// Focus detection that works while the target app is in the background.
///
/// An inactive app usually answers nil for its app-level AXFocusedUIElement, yet the element that will receive its
/// keyboard input (the first responder of its window) can still report AXFocused == true on itself. These helpers pick
/// that element without ever activating the app.

/// Roles that describe a container of focus rather than the focused control itself. A window reports AXFocused when it
/// is the app's key window, which says nothing about where typed text would land.
private let backgroundFocusContainerRoles: Set<String> = [
    kAXApplicationRole as String,
    kAXWindowRole as String,
    kAXSheetRole as String,
    kAXDrawerRole as String,
    kAXMenuBarRole as String,
]

/// Pure. Chooses the focused element among rendered nodes that report AXFocused == true.
///
/// Container roles (application, window, sheet, drawer, menu bar) are skipped. When more than one control reports
/// focus, which happens when a focused group also flags its focused child, the deepest one wins because it is the one
/// that owns the keyboard; ties keep tree order.
func selectBackgroundFocus<Candidate>(
    _ candidates: [Candidate],
    role: (Candidate) -> String?,
    depth: (Candidate) -> Int
) -> Candidate? {
    var chosen: Candidate?
    var chosenDepth = Int.min
    for candidate in candidates {
        if let candidateRole = role(candidate), backgroundFocusContainerRoles.contains(candidateRole) {
            continue
        }
        let candidateDepth = depth(candidate)
        if candidateDepth > chosenDepth {
            chosen = candidate
            chosenDepth = candidateDepth
        }
    }
    return chosen
}

/// Pure. The order in which a batch step re-reads AXFocused live when the app-level focus is nil.
///
/// Walking the live tree again for every type_text step would cost a full snapshot. Instead the step probes the
/// elements it already holds: the element the pinned snapshot saw as focused first, then every text-entry element of
/// the pinned snapshot in index order. Text entry is judged by `canUseKeyboardTextFallback`, the same role, subrole and
/// role description test type_text applies to the focus it finds, because type_text delivers nothing to any other
/// focus. A field that appeared after the snapshot was taken is not found, and type_text then fails closed.
func backgroundFocusProbeOrder(pinnedFocus: AXUIElement?, records: [ElementRecord]) -> [AXUIElement] {
    var ordered: [AXUIElement] = []
    if let pinnedFocus {
        ordered.append(pinnedFocus)
    }

    let textEntries = records
        .filter { record in
            !record.isSyntheticText && record.element != nil
                && canUseKeyboardTextFallback(
                    role: record.role, subrole: record.subrole, roleDescription: record.roleDescription
                )
        }
        .sorted { $0.index < $1.index }

    for record in textEntries {
        guard let element = record.element else {
            continue
        }
        if ordered.contains(where: { CFEqual($0, element) }) {
            continue
        }
        ordered.append(element)
    }
    return ordered
}
