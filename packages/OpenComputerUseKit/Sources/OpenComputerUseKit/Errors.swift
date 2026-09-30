import Foundation

let computerUseNoWindowFoundMessage = "Apple event error -10005: cgWindowNotFound"

/// The no-window error, plus why Open Computer Use did not bring a window back itself: showing one would mean
/// activating or raising the app over the one the user is working in.
func noBackgroundWindowMessage(appName: String) -> String {
    "\(computerUseNoWindowFoundMessage). \(appName) has no visible window to read, and Open Computer Use does not "
        + "activate, raise, or unminimize apps. Ask the user to open or restore a window of \(appName), then call "
        + "get_app_state again."
}

/// True for the error a snapshot rebuild raises when the app has no readable window.
func isNoBackgroundWindowError(_ error: Error) -> Bool {
    guard case ComputerUseError.stateUnavailable(let message) = error else {
        return false
    }
    return message.hasPrefix(computerUseNoWindowFoundMessage)
}

/// Replaces the no-window error raised by the snapshot rebuild that follows an action. That rebuild runs after the
/// input was already delivered, so the plain "no visible window" text would hide that the action took effect.
/// Every other error passes through unchanged.
func errorAfterPerformedAction(_ error: Error, appName: String) -> Error {
    guard isNoBackgroundWindowError(error) else {
        return error
    }
    return ComputerUseError.stateUnavailable(
        "\(computerUseNoWindowFoundMessage). The action was performed, but \(appName) has no readable window "
            + "afterwards: the window may have closed, been re-tabbed, or left the Stage Manager stage. Call "
            + "get_app_state to see the current state before acting again."
    )
}

public enum ComputerUseError: Error, LocalizedError {
    case message(String)
    case unsupportedTool(String)
    case invalidArguments(String)
    case appNotFound(String)
    case permissionDenied(String)
    case stateUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .message(let value):
            return value
        case .unsupportedTool(let name):
            return "unsupportedTool(\"\(name)\")"
        case .invalidArguments(let message):
            return "invalidArguments(\"\(message)\")"
        case .appNotFound(let app):
            return "appNotFound(\"\(app)\")"
        case .permissionDenied(let message):
            return message
        case .stateUnavailable(let message):
            return message
        }
    }

    var toolResultIsError: Bool {
        true
    }
}

extension ComputerUseError {
    static func missingArgument(_ name: String) -> ComputerUseError {
        .message("Missing required argument: \(name)")
    }
}
