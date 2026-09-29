import Foundation

/// What type_text knows about the element that holds the target app's keyboard focus.
struct TypeTextFocus: Equatable {
    /// AXValue can be written directly, so text is appended without any keystrokes.
    let isValueSettable: Bool
    /// The element is a text-entry control that accepts pid-posted key events.
    let acceptsKeyboardText: Bool
}

/// How type_text delivers text. No route brings the target app to the front.
enum TypeTextRoute: Equatable {
    case setFocusedValue
    case postKeysToProcess
    case refuse
}

/// Pure. Chooses the delivery for the focus the snapshot (or a batch step's live read) found.
///
/// A settable value is written through accessibility. A text control that is not settable gets key events posted to
/// the app's process, which does not activate it. Without a confirmed text focus there is nowhere safe to send the
/// keys: they could land in whatever the app's first responder happens to be, such as a message list.
func typeTextRoute(focus: TypeTextFocus?) -> TypeTextRoute {
    guard let focus else {
        return .refuse
    }
    if focus.isValueSettable {
        return .setFocusedValue
    }
    return focus.acceptsKeyboardText ? .postKeysToProcess : .refuse
}

func typeTextNeedsTextFocusMessage(appName: String) -> String {
    "type_text found no focused text field in \(appName). Open Computer Use types without bringing the app to the "
        + "front, so the field must already hold focus: click the field by element_index (that focuses a text field "
        + "without bringing the app forward), check the focus line in the returned state, then retry. To fill a "
        + "field directly, use set_value on it."
}

/// Runs the chosen route. `setValue` returns false when the accessibility write is refused, in which case a text
/// control still receives the text as posted keys; anything else fails closed with `typeTextNeedsTextFocusMessage`.
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
        guard focus?.acceptsKeyboardText == true else {
            throw ComputerUseError.message(typeTextNeedsTextFocusMessage(appName: appName))
        }
        try postKeys()
        return .postKeysToProcess
    case .postKeysToProcess:
        try postKeys()
        return .postKeysToProcess
    case .refuse:
        throw ComputerUseError.message(typeTextNeedsTextFocusMessage(appName: appName))
    }
}
