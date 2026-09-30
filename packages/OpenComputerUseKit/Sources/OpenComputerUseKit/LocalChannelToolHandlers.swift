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

/// Executes the relay-local tools. `call` never throws: every failure is an `isError` tool result.
///
/// Every script-carrying call (`run_script`, `open_url`, `run_shortcut`) writes its `request` audit entry before any
/// check that could reject it, so rejected calls are logged too, and a call whose log cannot be written is refused.
public final class LocalChannelToolHandlers {
    private let macSessionGuard: MacSessionGuard
    private let auditLog: ScriptAuditLog
    private let scriptRunner: OsascriptChildRunner
    private let dictionaryLookup: ScriptingDictionaryLookup
    private let launcher: ShortcutAndUrlLauncher
    private let locateAppBundle: (String) -> URL?
    private let firstContactMinimumTimeout: TimeInterval

    private let contactLock = NSLock()
    private var contactedTargets: Set<String> = []

    private static let listShortcutsTimeout: TimeInterval = 20
    private static let timeoutRange = 1...60

    public init(
        environment: [String: String],
        guard macSessionGuard: MacSessionGuard = MacSessionGuard(),
        auditLog: ScriptAuditLog = ScriptAuditLog(),
        scriptRunner: OsascriptChildRunner? = nil,
        dictionaryLookup: ScriptingDictionaryLookup = ScriptingDictionaryLookup(),
        launcher: ShortcutAndUrlLauncher? = nil,
        locateAppBundle: @escaping (String) -> URL? = ScriptingDictionaryLookup.locateAppBundle,
        firstContactMinimumTimeout: TimeInterval = OsascriptChildRunner.firstContactMinimumTimeout
    ) {
        self.macSessionGuard = macSessionGuard
        self.auditLog = auditLog
        self.scriptRunner = scriptRunner ?? OsascriptChildRunner(baseEnvironment: environment)
        self.dictionaryLookup = dictionaryLookup
        self.launcher = launcher ?? ShortcutAndUrlLauncher(baseEnvironment: environment)
        self.locateAppBundle = locateAppBundle
        self.firstContactMinimumTimeout = firstContactMinimumTimeout
    }

    public func call(name: String, arguments: [String: Any]) -> ToolCallResult {
        switch name {
        case LocalChannelToolNames.runScript:
            return runScript(arguments)
        case LocalChannelToolNames.openURL:
            return openURL(arguments)
        case LocalChannelToolNames.runShortcut:
            return runShortcut(arguments)
        case LocalChannelToolNames.getScriptingDictionary:
            return getScriptingDictionary(arguments)
        case LocalChannelToolNames.listShortcuts:
            return listShortcuts()
        default:
            do {
                try macSessionGuard.requireUnlocked(for: name)
            } catch {
                return Self.errorResult(Self.describe(error))
            }
            return Self.errorResult("unsupported local tool")
        }
    }

    // MARK: - run_script

    private func runScript(_ arguments: [String: Any]) -> ToolCallResult {
        let name = LocalChannelToolNames.runScript
        guard let source = arguments["source"] as? String, !source.isEmpty else {
            return Self.errorResult("run_script requires a non-empty string `source`.")
        }
        let app = arguments["app"] as? String ?? ""
        let digest = ScriptAuditLog.sha256Hex(source)

        if let refusal = recordRequest(kind: .runScript, targetApp: app, payload: source, digest: digest) {
            return refusal
        }
        func finish(_ outcome: String, exit: Int32? = nil, duration: Int? = nil) {
            recordResult(kind: .runScript, targetApp: app, digest: digest, exit: exit, duration: duration, outcome: outcome)
        }

        do {
            try macSessionGuard.requireUnlocked(for: name)
        } catch {
            finish("rejected:locked")
            return Self.errorResult(Self.describe(error))
        }

        guard !app.isEmpty else {
            finish("rejected:invalid-arguments")
            return Self.errorResult("run_script requires a non-empty string `app`.")
        }
        var language = ScriptLanguage.applescript
        if let value = arguments["language"] {
            guard let text = value as? String, let parsed = ScriptLanguage(rawValue: text) else {
                finish("rejected:invalid-arguments")
                return Self.errorResult("run_script `language` must be \"applescript\" or \"javascript\".")
            }
            language = parsed
        }
        let requestedTimeout: Int?
        switch Self.optionalTimeout(arguments["timeout_s"]) {
        case .success(let value):
            requestedTimeout = value
        case .failure:
            finish("rejected:invalid-arguments")
            return Self.errorResult("run_script `timeout_s` must be an integer from 1 to 60.")
        }

        if case .rejected(let pattern) = ScriptPolicyFilter.evaluate(source: source, language: language) {
            finish("rejected:filter:\(pattern)")
            return Self.errorResult(
                "run_script rejected by the script policy filter (matched \"\(pattern)\"). "
                    + "The filter is best-effort friction, not a security boundary."
            )
        }

        let key = app.lowercased()
        let timeout = OsascriptChildRunner.effectiveTimeout(
            requested: requestedTimeout.map(TimeInterval.init),
            isFirstContactWithTarget: !hasContacted(key),
            firstContactFloor: firstContactMinimumTimeout
        )

        let outcome: ScriptRunOutcome
        do {
            outcome = try scriptRunner.run(source: source, language: language, timeout: timeout)
        } catch {
            finish("error")
            return Self.errorResult("run_script failed to run: \(Self.describe(error))")
        }

        let succeeded = !outcome.timedOut && outcome.exitStatus == 0
        let label: String
        if outcome.timedOut {
            label = "timeout"
        } else if succeeded {
            label = "ok"
        } else {
            label = "error \(outcome.errorNumber ?? outcome.exitStatus.map { Int($0) } ?? -1)"
        }
        finish(label, exit: outcome.exitStatus, duration: outcome.durationMilliseconds)
        if !outcome.timedOut, outcome.errorNumber != -1743 {
            markContacted(key)
        }

        let bracket = "[run_script exit=\(outcome.exitStatus.map(String.init) ?? "signal") "
            + "duration_ms=\(outcome.durationMilliseconds) truncated=\(outcome.outputTruncated)]"
        if outcome.timedOut {
            return Self.errorResult(
                "run_script timed out after \(Int(timeout))s and was stopped. A timed-out script keeps running inside "
                    + "\(app); keep queries small (one mailbox, first N results).\n\n\(bracket)"
            )
        }
        if succeeded {
            return .text(outcome.resultText + "\n\n" + bracket)
        }
        let message = outcome.errorNumber.flatMap { OsascriptChildRunner.userFacingMessage(errorNumber: $0, app: app) }
            ?? outcome.errorMessage
            ?? "script failed"
        return Self.errorResult(message + "\n\n" + bracket)
    }

    // MARK: - open_url and run_shortcut

    private func openURL(_ arguments: [String: Any]) -> ToolCallResult {
        guard let url = arguments["url"] as? String, !url.isEmpty else {
            return Self.errorResult("open_url requires a non-empty string `url`.")
        }
        let digest = ScriptAuditLog.sha256Hex(url)
        if let refusal = recordRequest(kind: .openURL, targetApp: nil, payload: url, digest: digest) {
            return refusal
        }
        func finish(_ outcome: String, duration: Int? = nil) {
            recordResult(kind: .openURL, targetApp: nil, digest: digest, exit: nil, duration: duration, outcome: outcome)
        }
        do {
            try macSessionGuard.requireUnlocked(for: LocalChannelToolNames.openURL)
        } catch {
            finish("rejected:locked")
            return Self.errorResult(Self.describe(error))
        }

        let started = Date()
        do {
            let text = try launcher.openURL(url)
            finish("ok", duration: Self.milliseconds(since: started))
            return .text(text)
        } catch ShortcutAndUrlLauncherError.rejected(let reason) {
            finish("rejected:\(reason)")
            return Self.errorResult("open_url refused: \(reason)")
        } catch ShortcutAndUrlLauncherError.invalidURL {
            finish("rejected:invalid-url")
            return Self.errorResult("open_url refused: not a valid URL.")
        } catch {
            finish("error", duration: Self.milliseconds(since: started))
            return Self.errorResult("open_url failed: \(Self.describe(error))")
        }
    }

    private func runShortcut(_ arguments: [String: Any]) -> ToolCallResult {
        guard let shortcutName = arguments["name"] as? String, !shortcutName.isEmpty else {
            return Self.errorResult("run_shortcut requires a non-empty string `name`.")
        }
        let input = arguments["input"] as? String
        let payload = shortcutName + "\n" + (input ?? "")
        let digest = ScriptAuditLog.sha256Hex(payload)
        if let refusal = recordRequest(kind: .runShortcut, targetApp: nil, payload: payload, digest: digest) {
            return refusal
        }
        func finish(_ outcome: String, exit: Int32? = nil, duration: Int? = nil) {
            recordResult(kind: .runShortcut, targetApp: nil, digest: digest, exit: exit, duration: duration, outcome: outcome)
        }
        do {
            try macSessionGuard.requireUnlocked(for: LocalChannelToolNames.runShortcut)
        } catch {
            finish("rejected:locked")
            return Self.errorResult(Self.describe(error))
        }

        if arguments["input"] != nil, input == nil {
            finish("rejected:invalid-arguments")
            return Self.errorResult("run_shortcut `input` must be a string.")
        }
        let requestedTimeout: Int?
        switch Self.optionalTimeout(arguments["timeout_s"]) {
        case .success(let value):
            requestedTimeout = value
        case .failure:
            finish("rejected:invalid-arguments")
            return Self.errorResult("run_shortcut `timeout_s` must be an integer from 1 to 60.")
        }
        let timeout = OsascriptChildRunner.effectiveTimeout(
            requested: requestedTimeout.map(TimeInterval.init),
            isFirstContactWithTarget: false
        )

        let started = Date()
        let outcome: ScriptRunOutcome
        do {
            outcome = try launcher.runShortcut(name: shortcutName, input: input, timeout: timeout)
        } catch ShortcutAndUrlLauncherError.invalidShortcutName {
            finish("rejected:invalid-shortcut-name")
            return Self.errorResult("run_shortcut refused: not a valid shortcut name.")
        } catch {
            finish("error", duration: Self.milliseconds(since: started))
            return Self.errorResult("run_shortcut failed to run: \(Self.describe(error))")
        }

        let succeeded = !outcome.timedOut && outcome.exitStatus == 0
        finish(
            outcome.timedOut ? "timeout" : (succeeded ? "ok" : "error \(outcome.exitStatus.map { Int($0) } ?? -1)"),
            exit: outcome.exitStatus,
            duration: outcome.durationMilliseconds
        )
        let bracket = "[run_shortcut exit=\(outcome.exitStatus.map(String.init) ?? "signal") "
            + "duration_ms=\(outcome.durationMilliseconds) truncated=\(outcome.outputTruncated)]"
        if outcome.timedOut {
            return Self.errorResult("run_shortcut timed out after \(Int(timeout))s and was stopped.\n\n\(bracket)")
        }
        if succeeded {
            return .text(outcome.resultText + "\n\n" + bracket)
        }
        return Self.errorResult((outcome.errorMessage ?? "shortcut failed") + "\n\n" + bracket)
    }

    // MARK: - Read-only tools

    private func getScriptingDictionary(_ arguments: [String: Any]) -> ToolCallResult {
        do {
            try macSessionGuard.requireUnlocked(for: LocalChannelToolNames.getScriptingDictionary)
        } catch {
            return Self.errorResult(Self.describe(error))
        }
        guard let app = arguments["app"] as? String, !app.isEmpty else {
            return Self.errorResult("get_scripting_dictionary requires a non-empty string `app`.")
        }
        guard let bundle = locateAppBundle(app) else {
            return Self.errorResult("app not found: \(app)")
        }
        do {
            return .text(try dictionaryLookup.summary(appBundleURL: bundle, term: arguments["term"] as? String))
        } catch {
            return Self.errorResult(Self.describe(error))
        }
    }

    private func listShortcuts() -> ToolCallResult {
        do {
            try macSessionGuard.requireUnlocked(for: LocalChannelToolNames.listShortcuts)
        } catch {
            return Self.errorResult(Self.describe(error))
        }
        do {
            let listing = try launcher.listShortcuts(timeout: Self.listShortcutsTimeout)
            return .text(listing.isEmpty ? "No shortcuts found." : listing)
        } catch {
            return Self.errorResult("list_shortcuts failed: \(Self.describe(error))")
        }
    }

    // MARK: - Audit

    /// Writes the request entry. Returns the refusal result when the log cannot be written, nil when the call may go on.
    private func recordRequest(
        kind: ScriptAuditEntry.Kind, targetApp: String?, payload: String, digest: String
    ) -> ToolCallResult? {
        do {
            try auditLog.record(
                ScriptAuditEntry(kind: kind, phase: .request, targetApp: targetApp, payload: payload, payloadSHA256: digest)
            )
            return nil
        } catch {
            let subject = kind == .runScript ? "scripts" : "calls"
            return Self.errorResult(
                "script audit log unavailable: \(Self.describe(error)); refusing to run unlogged \(subject)."
            )
        }
    }

    /// A failed result entry is reported on standard error but never changes what the caller gets back.
    private func recordResult(
        kind: ScriptAuditEntry.Kind, targetApp: String?, digest: String, exit: Int32?, duration: Int?, outcome: String
    ) {
        do {
            try auditLog.record(
                ScriptAuditEntry(
                    kind: kind, phase: .result, targetApp: targetApp, payload: nil, payloadSHA256: digest,
                    exitStatus: exit, durationMilliseconds: duration, outcome: outcome
                )
            )
        } catch {
            FileHandle.standardError.write(
                Data("[open-computer-use] \(kind.rawValue) result audit failed: \(Self.describe(error))\n".utf8)
            )
        }
    }

    // MARK: - Helpers

    private func hasContacted(_ key: String) -> Bool {
        contactLock.lock()
        defer { contactLock.unlock() }
        return contactedTargets.contains(key)
    }

    private func markContacted(_ key: String) {
        contactLock.lock()
        defer { contactLock.unlock() }
        contactedTargets.insert(key)
    }

    private struct InvalidTimeout: Error {}

    /// Absent means "use the default"; anything present must be a real integer in 1...60 (a JSON boolean is not one).
    private static func optionalTimeout(_ value: Any?) -> Result<Int?, InvalidTimeout> {
        guard let value else { return .success(nil) }
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
            return .failure(InvalidTimeout())
        }
        guard let seconds = value as? Int, timeoutRange.contains(seconds) else {
            return .failure(InvalidTimeout())
        }
        return .success(seconds)
    }

    private static func milliseconds(since start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }

    private static func errorResult(_ text: String) -> ToolCallResult {
        .text(text, isError: true)
    }

    /// One readable line for the errors this channel can meet, without echoing script text.
    private static func describe(_ error: Error) -> String {
        switch error {
        case let error as ComputerUseError:
            return error.errorDescription ?? String(describing: error)
        case ScriptAuditLogError.directoryUnsafe(let message),
             ScriptAuditLogError.fileUnsafe(let message),
             ScriptAuditLogError.writeFailed(let message):
            return message
        case ScriptingDictionaryLookupError.appNotFound(let message),
             ScriptingDictionaryLookupError.noScriptingDefinition(let message),
             ScriptingDictionaryLookupError.definitionOutsideBundle(let message),
             ScriptingDictionaryLookupError.definitionNotRegularFile(let message),
             ScriptingDictionaryLookupError.malformedDefinition(let message):
            return message
        case OsascriptChildRunnerError.sourceTooLarge(let byteCount):
            return "script source is \(byteCount) bytes, over the \(OsascriptChildRunner.maximumSourceBytes) byte limit"
        default:
            return String(describing: error)
        }
    }
}
