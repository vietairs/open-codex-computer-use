import Foundation

/// The opt-in switch for the relay-local script channels. It is read only from the relay's own launch environment:
/// `MacSessionLockPolicy.sanitizePeerEnvironment` drops it, so it never crosses the app-agent socket.
public enum LocalChannelPolicy {
    public static let environmentKey = "OPEN_COMPUTER_USE_ENABLE_SCRIPTING"

    public static func isEnabled(environment: [String: String]) -> Bool {
        guard let raw = environment[environmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }
        return ["1", "true", "yes", "on"].contains(raw)
    }
}

public enum LocalChannelToolNames {
    public static let runScript = "run_script"
    public static let getScriptingDictionary = "get_scripting_dictionary"
    public static let openURL = "open_url"
    public static let runShortcut = "run_shortcut"
    public static let listShortcuts = "list_shortcuts"
    public static let all: Set<String> = [runScript, getScriptingDictionary, openURL, runShortcut, listShortcuts]
}

/// Definitions for the tools the relay adds to `tools/list`. They are deliberately not part of `ToolDefinitions`:
/// the app agent must never list or dispatch them.
public enum LocalChannelToolDefinitions {
    private static let pluginSuffix = "This tool is part of plugin `Computer Use`."

    private static func sideEffectAnnotations() -> [String: Any] {
        ["destructiveHint": true, "openWorldHint": true]
    }

    private static func readOnlyAnnotations() -> [String: Any] {
        ["destructiveHint": false, "idempotentHint": true, "openWorldHint": false, "readOnlyHint": true]
    }

    public static let all: [ToolDefinition] = [
        ToolDefinition(
            name: LocalChannelToolNames.runScript,
            description: "Run an AppleScript or JavaScript for Automation script against a scriptable app through osascript, without moving the cursor or taking a screenshot. This tool is opt-in, and every script is logged. Shell, script-loading and framework-import verbs are rejected. Keep queries small (one mailbox, first N results): a script that times out keeps running inside the target app. \(pluginSuffix)",
            annotations: sideEffectAnnotations(),
            inputSchema: schema(
                properties: [
                    "app": property("string", "Name of the app the script talks to"),
                    "source": property("string", "Script source text"),
                    "language": [
                        "type": "string",
                        "description": "Script language. Defaults to applescript.",
                        "enum": ["applescript", "javascript"],
                    ],
                    "timeout_s": [
                        "type": "integer",
                        "minimum": 1,
                        "maximum": 60,
                        "description": "Timeout in seconds, 1 to 60. Defaults to 20; the first call to an app waits longer for a permission prompt.",
                    ],
                ],
                required: ["app", "source"]
            )
        ),
        ToolDefinition(
            name: LocalChannelToolNames.getScriptingDictionary,
            description: "Summarize an app's scripting dictionary (commands and classes) from its bundle, without launching the app. Pass term to narrow the summary. \(pluginSuffix)",
            annotations: readOnlyAnnotations(),
            inputSchema: schema(
                properties: [
                    "app": property("string", "App name or bundle identifier"),
                    "term": property("string", "Optional command or class name to narrow the summary"),
                ],
                required: ["app"]
            )
        ),
        ToolDefinition(
            name: LocalChannelToolNames.openURL,
            description: "Open a URL in the app registered for its scheme, in the background: the app is not brought to the front and the cursor does not move. Schemes and handlers that execute code or mount remote volumes are refused. \(pluginSuffix)",
            annotations: sideEffectAnnotations(),
            inputSchema: schema(
                properties: ["url": property("string", "URL to open")],
                required: ["url"]
            )
        ),
        ToolDefinition(
            name: LocalChannelToolNames.runShortcut,
            description: "Run a Shortcuts shortcut by name, optionally with text input. Use list_shortcuts to see the available names. \(pluginSuffix)",
            annotations: sideEffectAnnotations(),
            inputSchema: schema(
                properties: [
                    "name": property("string", "Shortcut name"),
                    "input": property("string", "Optional text input for the shortcut"),
                    "timeout_s": property("integer", "Timeout in seconds, 1 to 60. Defaults to 20."),
                ],
                required: ["name"]
            )
        ),
        ToolDefinition(
            name: LocalChannelToolNames.listShortcuts,
            description: "List the names of the available Shortcuts shortcuts. \(pluginSuffix)",
            annotations: readOnlyAnnotations(),
            inputSchema: schema(properties: [:], required: [])
        ),
    ]

    private static func property(_ type: String, _ description: String) -> [String: Any] {
        ["type": type, "description": description]
    }

    private static func schema(properties: [String: Any], required: [String]) -> [String: Any] {
        var value: [String: Any] = [
            "type": "object",
            "properties": properties,
            "additionalProperties": false,
        ]
        if !required.isEmpty {
            value["required"] = required
        }
        return value
    }
}
