import Foundation

/// Hosts such as Claude Code cut server instructions at 2048 characters, and this text is the shortest part of what a
/// host receives: the relay may swap the AppleScript line for the longer script-first guide, and the advisory tool's
/// cascade guide may follow. The newest tools lead so their guidance is read first. Tool behavior already in a tool's
/// own description is not repeated here.
let baseComputerUseServerInstructions = """
Use `perform_actions` for any short sequence you can fully specify; put externally visible steps such as Send in their own call, after you confirm them.
To act on one control without reading the whole tree, call `find_elements` with a role, label or identifier; its indices work in actions and `perform_actions` until the next refresh.
The available tools are list_apps, get_app_state, find_elements, click, perform_secondary_action, scroll, drag, type_text, press_key, set_value, and perform_actions. If any are missing, surface them with tool_search, and load `perform_actions` together with `get_app_state`.

Call `get_app_state` at the start of each assistant turn that uses Computer Use; verify actions from their results, and do not call `get_app_state` after every action.
Results are text-only unless you pass `include_screenshot: true`; take x/y only from the latest screenshot, and prefer `element_index`.
Prefer an app's own plugin or skill when it can do the task.
Work in the background: never disrupt the user or overwrite the clipboard unless asked.
\(appleScriptAvoidanceInstructionLine)
Ask the user before destructive or externally visible actions such as sending, deleting, or purchasing, and when the request is unclear.
"""

/// The base instructions under their original name, for existing callers that compare against the unmodified text.
let computerUseServerInstructions = baseComputerUseServerInstructions

/// The base instructions byte-for-byte when the advisory tool is not listed; otherwise the base plus the cascade
/// guide, so the host only ever sees guidance for a tool it can actually call.
func computerUseServerInstructions(environment: [String: String]) -> String {
    guard ToolDefinitions.listed(environment: environment).count > ToolDefinitions.all.count else {
        return baseComputerUseServerInstructions
    }
    return baseComputerUseServerInstructions + "\n\n" + DecisionAdvisor.cascadeGuide
}

public final class StdioMCPServer {
    private let dispatcher: ComputerUseToolDispatcher
    /// Read per request: in the app agent each MCP line runs under the calling host's environment overrides.
    private let environment: @Sendable () -> [String: String]

    public init(
        service: ComputerUseService = ComputerUseService(),
        environment: @escaping @Sendable () -> [String: String] = { ProcessInfo.processInfo.environment }
    ) {
        self.environment = environment
        self.dispatcher = ComputerUseToolDispatcher(service: service, environment: environment)
    }

    public func run() throws {
        while let line = readLine(strippingNewline: true) {
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            if let response = handle(line: line) {
                FileHandle.standardOutput.write((response + "\n").data(using: .utf8)!)
            }
        }
    }

    /// True when `line` is a request whose whole configuration comes from the environment dictionary passed to
    /// `handle(line:environment:)`: today only `tools/call` for `decide_next_action`. Such a request blocks on the
    /// model for seconds, so the app agent runs it without taking its process-wide environment-override lock.
    public static func readsOnlyCallEnvironment(line: String) -> Bool {
        guard let payload = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              payload["method"] as? String == "tools/call",
              let params = payload["params"] as? [String: Any]
        else { return false }
        return params["name"] as? String == ToolDefinitions.decideNextAction.name
    }

    /// `environment`, when given, is the calling host's per-call environment: it decides whether the advisory tool is
    /// listed, whether `initialize` carries the cascade guide, and where `decide_next_action` sends its request. When
    /// nil, the injected environment closure is read instead.
    public func handle(line: String, environment callEnvironment: [String: String]? = nil) -> String? {
        let environment = { callEnvironment ?? self.environment() }
        do {
            guard let payload = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                return try encodeJSONRPCError(id: nil, code: -32700, message: "Invalid JSON-RPC payload")
            }

            let method = payload["method"] as? String
            let id = payload["id"]
            let params = payload["params"] as? [String: Any] ?? [:]

            switch method {
            case "initialize":
                return try encodeJSONRPCResult(
                    id: id,
                    result: [
                        "protocolVersion": "2025-03-26",
                        "serverInfo": [
                            "name": "open-computer-use",
                            "version": openComputerUseVersion,
                        ],
                        "capabilities": [
                            "tools": [
                                "listChanged": false,
                            ],
                        ],
                        "instructions": computerUseServerInstructions(environment: environment()),
                    ]
                )
            case "notifications/initialized":
                return nil
            case "notifications/turn-ended":
                VisualCursorSupport.performOnMain {
                    SoftwareCursorOverlay.reset()
                }
                Task { @MainActor in
                    ControlActivityStore.shared.markTurnEnded(connectionID: nil)
                }
                return nil
            case "ping":
                return try encodeJSONRPCResult(id: id, result: [:])
            case "tools/list":
                return try encodeJSONRPCResult(
                    id: id,
                    result: [
                        "tools": ToolDefinitions.listed(environment: environment()).map(\.asDictionary),
                    ]
                )
            case "tools/call":
                let name = params["name"] as? String ?? ""
                let arguments = params["arguments"] as? [String: Any] ?? [:]
                let result = try dispatcher.callTool(name: name, arguments: arguments, environment: callEnvironment)
                return try encodeJSONRPCResult(
                    id: id,
                    result: result.asDictionary
                )
            default:
                if method == nil {
                    return nil
                }

                return try encodeJSONRPCError(id: id, code: -32601, message: "Method not found: \(method ?? "")")
            }
        } catch let error as ComputerUseError {
            let payload = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            let id = payload?["id"]
            let result = ToolCallResult.text(error.errorDescription ?? String(describing: error), isError: error.toolResultIsError)
            return try? encodeJSONRPCResult(id: id, result: result.asDictionary)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            let payload = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            let id = payload?["id"]
            return try? encodeJSONRPCResult(
                id: id,
                result: [
                    "content": [
                        [
                            "type": "text",
                            "text": message,
                        ],
                    ],
                    "isError": true,
                ]
            )
        }
    }

    private func encodeJSONRPCResult(id: Any?, result: [String: Any]) throws -> String {
        try encode([
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "result": result,
        ])
    }

    private func encodeJSONRPCError(id: Any?, code: Int, message: String) throws -> String {
        try encode([
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "error": [
                "code": code,
                "message": message,
            ],
        ])
    }

    private func encode(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
        guard let text = String(data: data, encoding: .utf8) else {
            throw ComputerUseError.message("Failed to encode JSON-RPC response.")
        }

        return text
    }
}
