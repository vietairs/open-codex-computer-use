import Foundation

let computerUseNoWindowFoundMessage = "Apple event error -10005: cgWindowNotFound"

/// The no-window error, plus why Open Computer Use did not bring a window back itself: showing one would mean
/// activating or raising the app over the one the user is working in.
func noBackgroundWindowMessage(appName: String) -> String {
    "\(computerUseNoWindowFoundMessage). \(appName) has no visible window to read, and Open Computer Use does not "
        + "activate, raise, or unminimize apps. Ask the user to open or restore a window of \(appName), then call "
        + "get_app_state again."
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
