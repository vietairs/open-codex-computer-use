import Foundation

/// What type_text knows about the element that holds the target app's keyboard focus.
struct TypeTextFocus: Equatable {
    /// AXValue can be written directly, so text is appended without any keystrokes.
    let isValueSettable: Bool
    /// The element is a text-entry control that accepts pid-posted key events.
    let acceptsKeyboardText: Bool
}

/// Pure. Builds the focus description from the focused element's attributes. Whether it accepts keyboard text comes
/// from its text-entry role, subrole or role description only, never from whether its value is settable.
func makeTypeTextFocus(role: String?, subrole: String?, roleDescription: String?, isValueSettable: Bool) -> TypeTextFocus {
    TypeTextFocus(
        isValueSettable: isValueSettable,
        acceptsKeyboardText: canUseKeyboardTextFallback(role: role, subrole: subrole, roleDescription: roleDescription)
    )
}

/// How type_text delivers text. No route brings the target app to the front.
enum TypeTextRoute: Equatable {
    case setFocusedValue
    case postKeysToProcess
    case refuse
}

/// Pure. Chooses the delivery for the focus the snapshot (or a batch step's live read) found.
///
/// Only a text-entry focus receives anything. Its value is written through accessibility when settable; otherwise key
/// events are posted to the app's process, which does not activate it. Any other focus is refused before any write or
/// keystroke, even when its value is settable (a slider, a list): keys could land in whatever the app's first responder
/// happens to be, such as a message list.
func typeTextRoute(focus: TypeTextFocus?) -> TypeTextRoute {
    guard let focus, focus.acceptsKeyboardText else {
        return .refuse
    }
    return focus.isValueSettable ? .setFocusedValue : .postKeysToProcess
}

func typeTextNeedsTextFocusMessage(appName: String) -> String {
    "type_text found no focused text field in \(appName). Open Computer Use types without bringing the app to the "
        + "front, so the field must already hold focus: click the field by element_index (that focuses a text field "
        + "without bringing the app forward), check the focus line in the returned state, then retry. To fill a "
        + "field directly, use set_value on it."
}

/// Runs the chosen route. `setValue` returns false when the accessibility write is refused, in which case the text
/// control still receives the text as posted keys; a non-text focus fails closed with `typeTextNeedsTextFocusMessage`.
func deliverTypedText(
    focus: TypeTextFocus?,
    appName: String,
    setValue: () throws -> Bool,
    postKeys: () throws -> Void
) throws -> TypeTextRoute {
    switch typeTextRoute(focus: focus) {
    case .setFocusedValue:
        if try setValue() {
            return .setFocusedValue
        }
        // The route already required a text-entry focus, so the refused write falls back to keys on that control.
        try postKeys()
        return .postKeysToProcess
    case .postKeysToProcess:
        try postKeys()
        return .postKeysToProcess
    case .refuse:
        throw ComputerUseError.message(typeTextNeedsTextFocusMessage(appName: appName))
    }
}
