import Foundation

/// Builds the JSON-RPC reply an MCP proxy gives its host when the shared app agent went away
/// while a request was in flight, so the host sees a failed call instead of a closed pipe.
public enum AppAgentLossResponse {
    /// The text a caller reads when the agent died mid-call. The call is never replayed, because
    /// it may be what crashed the agent and actions are not idempotent.
    public static let restartedMessage =
        "The Open Computer Use app agent stopped while handling this call and is being restarted. "
        + "The call was NOT retried, so it may or may not have taken effect. "
        + "Re-check the app state with get_app_state before acting again."

    /// The text a caller reads when the agent was already gone before the call could be written.
    /// Nothing reached the agent, so the call did not take effect and is safe to repeat.
    public static let notDeliveredMessage =
        "The Open Computer Use app agent was not reachable. The call was NOT sent, so it did not take effect; try again."

    /// The text a caller reads when the user quit Open Computer Use from its status menu. The proxy
    /// does not relaunch the agent until the host starts a new session.
    public static let quitMessage =
        "Open Computer Use was quit from its menu; restart your MCP host/session to start it again."

    /// Whether `requestLine` carries a non-null id, i.e. the host waits for an answer. A line
    /// without one is a notification and is never answered.
    public static func expectsReply(requestLine: String) -> Bool {
        requestID(in: requestLine) != nil
    }

    private static func requestID(in requestLine: String) -> (id: Any, object: [String: Any])? {
        guard let data = requestLine.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let id = object["id"],
              !(id is NSNull)
        else {
            return nil
        }
        return (id, object)
    }

    /// Reply for `requestLine`, or nil when the line carries no id (a notification expects no answer).
    /// A `tools/call` gets a tool result flagged `isError`; any other method gets a JSON-RPC error.
    public static func response(forRequestLine requestLine: String, message: String = restartedMessage) -> String? {
        guard let (id, object) = requestID(in: requestLine) else {
            return nil
        }

        let reply: [String: Any]
        if object["method"] as? String == "tools/call" {
            reply = ["jsonrpc": "2.0", "id": id, "result": ToolCallResult.text(message, isError: true).asDictionary]
        } else {
            reply = ["jsonrpc": "2.0", "id": id, "error": ["code": -32603, "message": message]]
        }

        guard let encoded = try? JSONSerialization.data(withJSONObject: reply, options: [.withoutEscapingSlashes]) else {
            return nil
        }
        return String(data: encoded, encoding: .utf8)
    }
}
