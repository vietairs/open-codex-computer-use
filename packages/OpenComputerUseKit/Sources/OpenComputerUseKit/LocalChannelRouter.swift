import Foundation

/// Sits between the host's standard input and the forward path (the app-agent socket in the relay, the in-process
/// server in direct mode).
///
/// With the scripting flag unset the router is a byte-for-byte passthrough: no line is parsed. With it set, a
/// `tools/call` for one of the five local tools is answered here and never forwarded, `initialize` and `tools/list`
/// responses are patched, and everything else (notifications, batches, unknown or case-variant tool names) is
/// forwarded untouched. The flag is read once from the launch environment passed to `init`, never from a request.
public final class LocalChannelRouter {
    public typealias Forward = (String) throws -> String?

    public let isEnabled: Bool

    private let makeHandlers: () -> LocalChannelToolHandlers
    private var handlers: LocalChannelToolHandlers?

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        makeHandlers: (() -> LocalChannelToolHandlers)? = nil
    ) {
        self.isEnabled = LocalChannelPolicy.isEnabled(environment: environment)
        self.makeHandlers = makeHandlers ?? { LocalChannelToolHandlers(environment: environment) }
    }

    /// One line in, at most one line out. An error thrown by `forward` propagates unchanged; nothing on the local
    /// side throws.
    public func route(line: String, forward: Forward) throws -> String? {
        guard isEnabled else {
            return try forward(line)
        }
        guard let data = line.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return try forward(line)
        }

        let params = object["params"] as? [String: Any]
        switch object["method"] as? String {
        case "tools/call":
            if let name = params?["name"] as? String, LocalChannelToolNames.all.contains(name) {
                return callLocalTool(name: name, params: params ?? [:], id: object["id"])
            }
            return try forward(line)
        case "initialize":
            return patch(try forward(line)) { result in
                guard let instructions = result["instructions"] as? String else { return false }
                result["instructions"] = Self.swapGuide(in: instructions)
                return true
            }
        case "tools/list":
            return patch(try forward(line)) { result in
                guard var tools = result["tools"] as? [Any] else { return false }
                tools.append(contentsOf: LocalChannelToolDefinitions.all.map(\.asDictionary))
                result["tools"] = tools
                return true
            }
        default:
            return try forward(line)
        }
    }

    /// Reads lines until `input` returns nil, skipping whitespace-only lines and writing one line per response.
    public func run(input: () -> String?, output: (String) -> Void, forward: Forward) throws {
        while let line = input() {
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            if let response = try route(line: line, forward: forward) {
                output(response + "\n")
            }
        }
    }

    public func run(forward: Forward) throws {
        try run(
            input: { readLine(strippingNewline: true) },
            output: { FileHandle.standardOutput.write(Data($0.utf8)) },
            forward: forward
        )
    }

    // MARK: - Local tools

    private func callLocalTool(name: String, params: [String: Any], id: Any?) -> String? {
        // A request without an id is a notification: run nothing, answer nothing.
        guard let id else { return nil }
        let arguments = params["arguments"] as? [String: Any] ?? [:]
        let result = localHandlers().call(name: name, arguments: arguments)
        do {
            return try Self.encode(["jsonrpc": "2.0", "id": id, "result": result.asDictionary])
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            return try? Self.encode([
                "jsonrpc": "2.0",
                "id": id,
                "error": ["code": -32603, "message": message],
            ])
        }
    }

    /// Built on the first local call, so a router that never serves one never creates the log directory.
    private func localHandlers() -> LocalChannelToolHandlers {
        if let handlers { return handlers }
        let built = makeHandlers()
        handlers = built
        return built
    }

    // MARK: - Response patching

    /// Applies `mutate` to the response's `result`. The forwarded response is returned unchanged when it is nil,
    /// unparsable, an error response, or does not have the shape `mutate` needs.
    private func patch(_ response: String?, mutate: (inout [String: Any]) -> Bool) -> String? {
        guard let response,
              let data = response.data(using: .utf8),
              var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              object["error"] == nil,
              var result = object["result"] as? [String: Any],
              mutate(&result) else {
            return response
        }
        object["result"] = result
        return (try? Self.encode(object)) ?? response
    }

    private static func swapGuide(in instructions: String) -> String {
        guard instructions.contains(appleScriptAvoidanceInstructionLine) else {
            return instructions + "\n\n" + scriptFirstInstructionGuide
        }
        return instructions.replacingOccurrences(of: appleScriptAvoidanceInstructionLine, with: scriptFirstInstructionGuide)
    }

    private static func encode(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
        guard let text = String(data: data, encoding: .utf8) else {
            throw ComputerUseError.message("Failed to encode JSON-RPC response.")
        }
        return text
    }
}
