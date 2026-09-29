import ApplicationServices

/// Keyboard focus for a text field clicked in a background app.
///
/// A click delivered to an inactive app, whether as an accessibility press or as pid-posted mouse events, usually does
/// not move that app's keyboard focus: the window is not key, so its first responder stays where it was (for example
/// on a message list). type_text then correctly refuses, because it only types into a confirmed text focus. Writing
/// AXFocused = true on the clicked field makes it the app's focused element without activating or raising the app,
/// after which type_text and press_key reach the field while the user's frontmost app is left alone.

/// Subroles that mark a text-entry control even when the role alone would not.
private let clickFocusTextEntrySubroles: Set<String> = [
    "AXSearchField",
    "AXSecureTextField",
]

/// Roles treated as text entry for the click focus write: every role type_text can deliver to, plus a password field
/// that reports `AXSecureTextField` as its role rather than its subrole.
private let clickFocusTextEntryRoles: Set<String> = backgroundFocusTextEntryRoles.union(["AXSecureTextField"])

/// Pure. Whether the role or subrole describes a text-entry control.
func isClickFocusTextEntry(role: String?, subrole: String?) -> Bool {
    if let role, clickFocusTextEntryRoles.contains(role) {
        return true
    }
    if let subrole, clickFocusTextEntrySubroles.contains(subrole) {
        return true
    }
    return false
}

/// Pure. Whether a click on this element should be followed by an AXFocused = true write.
func shouldFocusTextEntryAfterClick(role: String?, subrole: String?, focusSettable: Bool) -> Bool {
    focusSettable && isClickFocusTextEntry(role: role, subrole: subrole)
}

/// Runs the focus write after a delivered click. Effects are injected so the decision is testable without a live app.
///
/// Reads are ordered cheapest first: the subrole is read only when the role alone is not text entry, and the settable
/// check only once the element is known to be text entry, so a click on a button costs at most one attribute read.
/// Returns true when the write succeeded. A refused write is not an error: the click already happened, and type_text
/// still fails closed if the field never took focus.
@discardableResult
func focusTextEntryAfterClick(
    role: String?,
    readSubrole: () -> String?,
    isFocusSettable: () -> Bool,
    setFocused: () -> Bool
) -> Bool {
    let subrole = isClickFocusTextEntry(role: role, subrole: nil) ? nil : readSubrole()
    guard isClickFocusTextEntry(role: role, subrole: subrole) else {
        return false
    }
    guard shouldFocusTextEntryAfterClick(role: role, subrole: subrole, focusSettable: isFocusSettable()) else {
        return false
    }
    return setFocused()
}
