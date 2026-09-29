import Foundation
import XCTest
@testable import OpenComputerUseKit

/// The router sits between the host and a code-execution surface, so these tests pin both directions: with the flag
/// unset it must be a byte-for-byte passthrough, and with the flag set no local tool may ever reach the forward path.
///
/// Every test drives `route` / `run(input:output:forward:)` with in-memory closures, so nothing reads or writes the
/// test process's standard streams. Audit logs live in a per-test temporary directory. The only real child processes
/// are `/usr/bin/osascript` running scripts that send no Apple Event, and throwaway executable scripts.
final class LocalChannelRouterTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-channel-router-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    // MARK: - Fixtures

    private static let flag = LocalChannelPolicy.environmentKey
    private static let enabledEnvironment = [LocalChannelPolicy.environmentKey: "1"]
    private static let allLocalToolNames = [
        "run_script", "get_scripting_dictionary", "open_url", "run_shortcut", "list_shortcuts",
    ]

    private struct UnlockedSessionProvider: MacSessionStateProvider {
        func currentSnapshot() -> MacSessionSnapshot {
            MacSessionSnapshot(isLocked: false, isUnknown: false, rawKeysSeen: ["CGSSessionScreenIsLocked"])
        }
    }

    private struct LockedSessionProvider: MacSessionStateProvider {
        func currentSnapshot() -> MacSessionSnapshot {
            MacSessionSnapshot(isLocked: true, isUnknown: false, rawKeysSeen: ["CGSSessionScreenIsLocked"])
        }
    }

    private var unlockedGuard: MacSessionGuard {
        MacSessionGuard(provider: UnlockedSessionProvider(), policy: .blockWhileLocked)
    }

    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var strings: [String] = []
        private var openings: [(url: URL, handler: URL)] = []

        var values: [String] {
            lock.lock()
            defer { lock.unlock() }
            return strings
        }

        var openCalls: [(url: URL, handler: URL)] {
            lock.lock()
            defer { lock.unlock() }
            return openings
        }

        func append(_ value: String) {
            lock.lock()
            defer { lock.unlock() }
            strings.append(value)
        }

        func recordOpen(_ url: URL, _ handler: URL) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            openings.append((url, handler))
            return true
        }
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        func increment() {
            lock.lock()
            defer { lock.unlock() }
            value += 1
        }
    }

    /// Everything a handler test needs: a temp-dir audit log, a marker runner and a marker launcher.
    private struct Rig {
        let handlers: LocalChannelToolHandlers
        let auditDirectory: URL
        let stderr: Recorder
        let opener: Recorder
        let scriptMarker: URL
        let shortcutMarker: URL
    }

    private func writeExecutable(named name: String, body: String) throws -> String {
        let url = root.appendingPathComponent(name)
        try "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url.path
    }

    /// A real audit directory, or a symlink to one (which the audit log must refuse).
    private func makeAuditDirectory(symlinked: Bool) throws -> URL {
        let real = root.appendingPathComponent("audit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: real,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        guard symlinked else { return real }
        let link = root.appendingPathComponent("audit-link-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        return link
    }

    /// `markerRunner` replaces `/usr/bin/osascript` with a script that only creates a marker file, so a test can
    /// prove a call never spawned a child. `nil` keeps the real osascript.
    private func makeRig(
        guardOverride: MacSessionGuard? = nil,
        symlinkedAuditDirectory: Bool = false,
        markerRunner: Bool = true,
        firstContactMinimumTimeout: TimeInterval = OsascriptChildRunner.firstContactMinimumTimeout
    ) throws -> Rig {
        let auditDirectory = try makeAuditDirectory(symlinked: symlinkedAuditDirectory)
        let stderr = Recorder()
        let opener = Recorder()
        let scriptMarker = root.appendingPathComponent("script-ran-\(UUID().uuidString)")
        let shortcutMarker = root.appendingPathComponent("shortcut-ran-\(UUID().uuidString)")

        let runner: OsascriptChildRunner? = markerRunner
            ? OsascriptChildRunner(
                executablePath: try writeExecutable(
                    named: "marker-osascript-\(UUID().uuidString)",
                    body: "/usr/bin/touch '\(scriptMarker.path)'\ncat > /dev/null\nexit 0"
                ),
                baseEnvironment: [:]
            )
            : nil
        let shortcutsPath = try writeExecutable(
            named: "marker-shortcuts-\(UUID().uuidString)",
            body: "/usr/bin/touch '\(shortcutMarker.path)'\necho listing\nexit 0"
        )
        let safari = URL(fileURLWithPath: "/Applications/Safari.app")
        let launcher = ShortcutAndUrlLauncher(
            handlerResolver: { _ in safari },
            bundleIdentifierResolver: { _ in "com.apple.Safari" },
            opener: { url, handler in opener.recordOpen(url, handler) },
            shortcutsExecutablePath: shortcutsPath,
            temporaryRoot: root,
            baseEnvironment: [:]
        )
        let handlers = LocalChannelToolHandlers(
            environment: [:],
            guard: guardOverride ?? unlockedGuard,
            auditLog: ScriptAuditLog(directory: auditDirectory, standardErrorWriter: { stderr.append($0) }),
            scriptRunner: runner,
            launcher: launcher,
            locateAppBundle: { _ in nil },
            firstContactMinimumTimeout: firstContactMinimumTimeout
        )
        return Rig(
            handlers: handlers,
            auditDirectory: auditDirectory,
            stderr: stderr,
            opener: opener,
            scriptMarker: scriptMarker,
            shortcutMarker: shortcutMarker
        )
    }

    private func auditEntries(in directory: URL) throws -> [[String: Any]] {
        let path = directory.appendingPathComponent(ScriptAuditLog.fileName)
        guard let text = try? String(contentsOf: path, encoding: .utf8) else { return [] }
        return try text.split(separator: "\n").map { line in
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        }
    }

    private func jsonLine(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes, .sortedKeys])
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    private func parse(_ response: String?, file: StaticString = #filePath, line: UInt = #line) throws -> [String: Any] {
        let text = try XCTUnwrap(response, "expected a response line", file: file, line: line)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
            "response is not a JSON object: \(text)",
            file: file,
            line: line
        )
    }

    private func initializeLine(id: Int = 1) throws -> String {
        try jsonLine(["jsonrpc": "2.0", "id": id, "method": "initialize", "params": [String: Any]()])
    }

    private func toolsListLine(id: Int = 2) throws -> String {
        try jsonLine(["jsonrpc": "2.0", "id": id, "method": "tools/list"])
    }

    private func toolCallLine(name: String, arguments: Any? = [String: Any](), id: Int? = 3) throws -> String {
        var params: [String: Any] = ["name": name]
        if let arguments { params["arguments"] = arguments }
        var object: [String: Any] = ["jsonrpc": "2.0", "method": "tools/call", "params": params]
        if let id { object["id"] = id }
        return try jsonLine(object)
    }

    private func initializeResponse(instructions: String, id: Int = 1) throws -> String {
        try jsonLine([
            "jsonrpc": "2.0", "id": id,
            "result": ["protocolVersion": "2025-03-26", "instructions": instructions],
        ])
    }

    private func toolsListResponse(names: [String], id: Int = 2) throws -> String {
        let tools = names.map { name -> [String: Any] in
            ["name": name, "description": "d", "inputSchema": ["type": "object"]]
        }
        return try jsonLine(["jsonrpc": "2.0", "id": id, "result": ["tools": tools]])
    }

    private func resultObject(of response: [String: Any]) throws -> [String: Any] {
        try XCTUnwrap(response["result"] as? [String: Any], "response has no result: \(response)")
    }

    private func toolText(of result: ToolCallResult) -> String {
        result.primaryText ?? ""
    }

    // MARK: - Flag unset

    func testFlagUnsetRouterIsBytePassthrough() throws {
        let router = LocalChannelRouter(
            environment: [:],
            makeHandlers: {
                XCTFail("a disabled router must never build handlers")
                return LocalChannelToolHandlers(environment: [:])
            }
        )
        XCTAssertFalse(router.isEnabled)

        let lines = [
            try initializeLine(),
            try toolsListLine(),
            try toolCallLine(name: "run_script", arguments: ["app": "Mail", "source": "return 1"]),
            #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
            #"[{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"run_script","arguments":{}}}]"#,
        ]
        for (index, line) in lines.enumerated() {
            let received = Recorder()
            // The stand-in response is deliberately not JSON, so any parse-and-reencode would change it.
            let canned: String? = index == 3 ? nil : "  raw response \(index) {not json}  "
            let output = try router.route(line: line) { forwarded in
                received.append(forwarded)
                return canned
            }
            XCTAssertEqual(output, canned, "line \(index)")
            XCTAssertEqual(received.values, [line], "line \(index) must be forwarded once and unchanged")
        }
    }

    func testFlagUnsetInitializeKeepsAppleScriptLine() throws {
        XCTAssertTrue(baseComputerUseServerInstructions.contains(appleScriptAvoidanceInstructionLine))
        XCTAssertEqual(
            appleScriptAvoidanceInstructionLine,
            "Avoid falling back to AppleScript during a computer use session. "
                + "Prefer Computer Use tools as much as possible to complete tasks."
        )

        // The agent-side server never patches, even when the flag reaches it.
        let server = StdioMCPServer(service: ComputerUseService(), environment: { Self.enabledEnvironment })
        let response = try parse(server.handle(line: try initializeLine()))
        let instructions = try XCTUnwrap(try resultObject(of: response)["instructions"] as? String)
        XCTAssertTrue(instructions.contains(appleScriptAvoidanceInstructionLine))
    }

    func testFlagValuesParse() {
        for value in ["1", "true", " YES ", "on", "True", "ON"] {
            XCTAssertTrue(LocalChannelPolicy.isEnabled(environment: [Self.flag: value]), "\(value.debugDescription)")
        }
        for value in ["0", "false", "", "nonsense", "no", "off"] {
            XCTAssertFalse(LocalChannelPolicy.isEnabled(environment: [Self.flag: value]), "\(value.debugDescription)")
        }
        XCTAssertFalse(LocalChannelPolicy.isEnabled(environment: [:]))
        XCTAssertEqual(LocalChannelPolicy.environmentKey, "OPEN_COMPUTER_USE_ENABLE_SCRIPTING")
    }

    // MARK: - Flag set: patching

    func testToolsListAppendsFiveLocalTools() throws {
        let router = LocalChannelRouter(environment: Self.enabledEnvironment, makeHandlers: { try! self.makeRig().handlers })
        XCTAssertTrue(router.isEnabled)

        let output = try router.route(line: try toolsListLine(id: 9)) { _ in
            try self.toolsListResponse(names: ["alpha", "beta"], id: 9)
        }
        let response = try parse(output)
        XCTAssertEqual(response["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(response["id"] as? Int, 9)
        let tools = try XCTUnwrap(try resultObject(of: response)["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 7)
        XCTAssertEqual(tools.compactMap { $0["name"] as? String }.prefix(2), ["alpha", "beta"])
        XCTAssertEqual(tools.suffix(5).compactMap { $0["name"] as? String }, Self.allLocalToolNames)
    }

    func testInitializeSwapsAppleScriptLineForGuide() throws {
        let router = LocalChannelRouter(environment: Self.enabledEnvironment, makeHandlers: { try! self.makeRig().handlers })
        let base = baseComputerUseServerInstructions

        let output = try router.route(line: try initializeLine()) { _ in
            try self.initializeResponse(instructions: base)
        }
        let response = try parse(output)
        XCTAssertEqual(response["id"] as? Int, 1)
        let result = try resultObject(of: response)
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-03-26")
        let patched = try XCTUnwrap(result["instructions"] as? String)

        XCTAssertFalse(patched.contains(appleScriptAvoidanceInstructionLine))
        XCTAssertTrue(patched.contains(scriptFirstInstructionGuide))
        XCTAssertEqual(
            patched,
            base.replacingOccurrences(of: appleScriptAvoidanceInstructionLine, with: scriptFirstInstructionGuide),
            "only the AppleScript line may change"
        )
    }

    func testInitializeAppendsGuideWhenAppleScriptLineIsAbsent() throws {
        let router = LocalChannelRouter(environment: Self.enabledEnvironment, makeHandlers: { try! self.makeRig().handlers })
        let output = try router.route(line: try initializeLine()) { _ in
            try self.initializeResponse(instructions: "Some other instructions.")
        }
        let patched = try XCTUnwrap(try resultObject(of: try parse(output))["instructions"] as? String)
        XCTAssertEqual(patched, "Some other instructions.\n\n" + scriptFirstInstructionGuide)
    }

    func testScriptFirstGuideNamesTheScriptChannelAndItsLimits() {
        let guide = scriptFirstInstructionGuide
        for phrase in [
            "run_script", "get_scripting_dictionary", "find_elements", "get_app_state",
            "not a security boundary",
        ] {
            XCTAssertTrue(guide.contains(phrase), "guide should mention \(phrase)")
        }
        XCTAssertFalse(guide.contains(appleScriptAvoidanceInstructionLine))
    }

    func testForwardedErrorResponsesPassThroughUntouched() throws {
        let router = LocalChannelRouter(environment: Self.enabledEnvironment, makeHandlers: { try! self.makeRig().handlers })
        let requests = [try initializeLine(), try toolsListLine()]
        let responses: [String?] = [
            #"{"jsonrpc":"2.0","id":1,"error":{"code":-32603,"message":"agent unavailable"}}"#,
            #"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-03-26"}}"#,
            #"{"jsonrpc":"2.0","id":1,"result":{"other":[1,2]}}"#,
            #"{"jsonrpc":"2.0","id":1,"result":{"instructions":5,"tools":"x"}}"#,
            "not json at all",
            nil,
        ]
        for request in requests {
            for response in responses {
                let output = try router.route(line: request) { _ in response }
                XCTAssertEqual(output, response, "request \(request) response \(String(describing: response))")
            }
        }
    }

    // MARK: - Flag set: local tools

    func testLocalToolsAreNeverForwarded() throws {
        let rig = try makeRig()
        let built = Counter()
        let router = LocalChannelRouter(
            environment: Self.enabledEnvironment,
            makeHandlers: {
                built.increment()
                return rig.handlers
            }
        )
        let arguments: [String: [String: Any]] = [
            "run_script": ["app": "Mail", "source": "return 1"],
            "get_scripting_dictionary": ["app": "NoSuchApplicationForRouterTests"],
            "open_url": ["url": "https://example.com"],
            "run_shortcut": ["name": "Demo"],
            "list_shortcuts": [:],
        ]
        for (index, name) in Self.allLocalToolNames.enumerated() {
            let requestID = 100 + index
            let output = try router.route(line: try toolCallLine(name: name, arguments: arguments[name], id: requestID)) { _ in
                XCTFail("local tool \(name) must never be forwarded")
                return nil
            }
            let response = try parse(output)
            XCTAssertEqual(response["id"] as? Int, requestID, name)
            XCTAssertEqual(response["jsonrpc"] as? String, "2.0", name)
            let result = try resultObject(of: response)
            XCTAssertNotNil(result["content"], name)
            XCTAssertNotNil(result["isError"], name)
        }
        XCTAssertEqual(built.count, 1, "handlers are built once, lazily")
    }

    func testCaseVariantToolNameIsForwarded() throws {
        let built = Counter()
        let router = LocalChannelRouter(
            environment: Self.enabledEnvironment,
            makeHandlers: {
                built.increment()
                return try! self.makeRig().handlers
            }
        )
        let line = try toolCallLine(name: "Run_Script", arguments: ["app": "Mail", "source": "return 1"])
        let received = Recorder()
        let output = try router.route(line: line) { forwarded in
            received.append(forwarded)
            return "forwarded response"
        }
        XCTAssertEqual(output, "forwarded response")
        XCTAssertEqual(received.values, [line])
        XCTAssertEqual(built.count, 0)
    }

    func testMalformedLocalCallBecomesToolError() throws {
        let rig = try makeRig()
        let router = LocalChannelRouter(environment: Self.enabledEnvironment, makeHandlers: { rig.handlers })

        for (index, arguments) in [Optional<Any>("x"), nil].enumerated() {
            let output = try router.route(line: try toolCallLine(name: "run_script", arguments: arguments, id: 40 + index)) { _ in
                XCTFail("must not forward a local tool call")
                return nil
            }
            let response = try parse(output)
            XCTAssertEqual(response["id"] as? Int, 40 + index)
            XCTAssertEqual(try resultObject(of: response)["isError"] as? Bool, true, "case \(index)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: rig.scriptMarker.path))
    }

    func testLocalCallWithoutIdProducesNoOutput() throws {
        let rig = try makeRig()
        let router = LocalChannelRouter(environment: Self.enabledEnvironment, makeHandlers: { rig.handlers })
        var pending = [try toolCallLine(name: "list_shortcuts", arguments: [String: Any](), id: nil)]
        var written: [String] = []

        try router.run(
            input: { pending.isEmpty ? nil : pending.removeFirst() },
            output: { written.append($0) },
            forward: { _ in
                XCTFail("must not forward a local tool call")
                return nil
            }
        )
        XCTAssertTrue(written.isEmpty)
    }

    func testBatchArrayIsForwardedUntouched() throws {
        let router = LocalChannelRouter(
            environment: Self.enabledEnvironment,
            makeHandlers: {
                XCTFail("a batch must never reach the local handlers")
                return LocalChannelToolHandlers(environment: [:])
            }
        )
        let batch = #"[{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"run_script","arguments":{"app":"Mail","source":"return 1"}}},{"jsonrpc":"2.0","id":2,"method":"tools/list"}]"#
        let received = Recorder()
        let output = try router.route(line: batch) { forwarded in
            received.append(forwarded)
            return "  batch response  "
        }
        XCTAssertEqual(output, "  batch response  ")
        XCTAssertEqual(received.values, [batch])
    }

    func testNotificationProducesNoOutput() throws {
        let router = LocalChannelRouter(
            environment: Self.enabledEnvironment,
            makeHandlers: {
                XCTFail("a notification must never build handlers")
                return LocalChannelToolHandlers(environment: [:])
            }
        )
        var pending = ["", "   \t ", #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#]
        var written: [String] = []
        let received = Recorder()

        try router.run(
            input: { pending.isEmpty ? nil : pending.removeFirst() },
            output: { written.append($0) },
            forward: { forwarded in
                received.append(forwarded)
                return nil
            }
        )
        XCTAssertTrue(written.isEmpty)
        XCTAssertEqual(received.values, [#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#], "blank lines are skipped")
    }

    func testRunWritesEachResponseAsOneLine() throws {
        let router = LocalChannelRouter(environment: [:])
        var pending = [try toolsListLine(id: 1), "", try toolsListLine(id: 2)]
        var written: [String] = []
        try router.run(
            input: { pending.isEmpty ? nil : pending.removeFirst() },
            output: { written.append($0) },
            forward: { "response for \($0.count)" }
        )
        XCTAssertEqual(written.count, 2)
        XCTAssertTrue(written.allSatisfy { $0.hasSuffix("\n") })
    }

    func testForwardErrorPropagatesUnchanged() throws {
        struct RelayDown: Error, Equatable {}
        let router = LocalChannelRouter(environment: Self.enabledEnvironment, makeHandlers: { try! self.makeRig().handlers })
        XCTAssertThrowsError(try router.route(line: try toolsListLine()) { _ in throw RelayDown() }) { error in
            XCTAssertEqual(error as? RelayDown, RelayDown())
        }
    }

    // MARK: - run_script handler

    func testFilterRejectionIsLoggedAndNeverSpawns() throws {
        let rig = try makeRig()
        let source = #"do shell script "id""#

        let result = rig.handlers.call(name: "run_script", arguments: ["app": "Mail", "source": source])

        XCTAssertTrue(result.isError)
        XCTAssertTrue(toolText(of: result).contains("script policy filter"), toolText(of: result))
        XCTAssertTrue(toolText(of: result).contains("not a security boundary"), toolText(of: result))
        XCTAssertFalse(FileManager.default.fileExists(atPath: rig.scriptMarker.path), "the runner must not be spawned")

        let entries = try auditEntries(in: rig.auditDirectory)
        let request = try XCTUnwrap(entries.first { $0["phase"] as? String == "request" })
        XCTAssertEqual(request["kind"] as? String, "run_script")
        XCTAssertEqual(request["payload"] as? String, source)
        XCTAssertEqual(request["target_app"] as? String, "Mail")
        let resultEntry = try XCTUnwrap(entries.first { $0["phase"] as? String == "result" })
        XCTAssertTrue((resultEntry["outcome"] as? String ?? "").hasPrefix("rejected:filter"), "\(resultEntry)")
        XCTAssertNil(resultEntry["payload"])
    }

    func testAuditFailureRefusesScript() throws {
        let rig = try makeRig(symlinkedAuditDirectory: true)

        for source in ["return 1", #"do shell script "id""#] {
            let result = rig.handlers.call(name: "run_script", arguments: ["app": "Mail", "source": source])
            XCTAssertTrue(result.isError, source)
            XCTAssertTrue(toolText(of: result).contains("audit log"), toolText(of: result))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: rig.scriptMarker.path), "nothing may run unlogged")
    }

    func testRunScriptWithoutSourceIsAnErrorWithNothingToLog() throws {
        let rig = try makeRig()
        for arguments: [String: Any] in [[:], ["app": "Mail"], ["app": "Mail", "source": ""], ["app": "Mail", "source": 5]] {
            let result = rig.handlers.call(name: "run_script", arguments: arguments)
            XCTAssertTrue(result.isError, "\(arguments)")
        }
        XCTAssertTrue(try auditEntries(in: rig.auditDirectory).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: rig.scriptMarker.path))
    }

    func testInvalidArgumentsAreLoggedAndNeverSpawn() throws {
        let rig = try makeRig()
        let missingApp = rig.handlers.call(name: "run_script", arguments: ["source": "return 1"])
        let emptyApp = rig.handlers.call(name: "run_script", arguments: ["app": "", "source": "return 1"])
        let badLanguage = rig.handlers.call(name: "run_script", arguments: ["app": "Mail", "source": "return 1", "language": "perl"])
        let badTimeout = rig.handlers.call(name: "run_script", arguments: ["app": "Mail", "source": "return 1", "timeout_s": 0])
        let hugeTimeout = rig.handlers.call(name: "run_script", arguments: ["app": "Mail", "source": "return 1", "timeout_s": 61])

        for result in [missingApp, emptyApp, badLanguage, badTimeout, hugeTimeout] {
            XCTAssertTrue(result.isError, toolText(of: result))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: rig.scriptMarker.path))
        let entries = try auditEntries(in: rig.auditDirectory)
        XCTAssertEqual(entries.filter { $0["phase"] as? String == "request" }.count, 5, "every payload is logged first")
        let outcomes = entries.compactMap { $0["outcome"] as? String }
        XCTAssertEqual(outcomes.count, 5)
        XCTAssertTrue(outcomes.allSatisfy { $0 == "rejected:invalid-arguments" }, "\(outcomes)")
    }

    func testOpenUrlAndShortcutAreAuditedAndRefusedWhenLogUnsafe() throws {
        let safe = try makeRig()
        let openResult = safe.handlers.call(name: "open_url", arguments: ["url": "https://example.com"])
        let shortcutResult = safe.handlers.call(name: "run_shortcut", arguments: ["name": "Demo", "input": "hello"])
        XCTAssertFalse(openResult.isError, toolText(of: openResult))
        XCTAssertFalse(shortcutResult.isError, toolText(of: shortcutResult))
        XCTAssertEqual(safe.opener.openCalls.count, 1)

        let entries = try auditEntries(in: safe.auditDirectory)
        for kind in ["open_url", "run_shortcut"] {
            let ofKind = entries.filter { $0["kind"] as? String == kind }
            XCTAssertEqual(ofKind.filter { $0["phase"] as? String == "request" }.count, 1, kind)
            XCTAssertEqual(ofKind.filter { $0["phase"] as? String == "result" }.count, 1, kind)
        }
        let openRequest = try XCTUnwrap(entries.first { $0["kind"] as? String == "open_url" && $0["phase"] as? String == "request" })
        XCTAssertEqual(openRequest["payload"] as? String, "https://example.com")
        let shortcutRequest = try XCTUnwrap(entries.first { $0["kind"] as? String == "run_shortcut" && $0["phase"] as? String == "request" })
        XCTAssertEqual(shortcutRequest["payload"] as? String, "Demo\nhello")

        let unsafe = try makeRig(symlinkedAuditDirectory: true)
        let refusedOpen = unsafe.handlers.call(name: "open_url", arguments: ["url": "https://example.com"])
        let refusedShortcut = unsafe.handlers.call(name: "run_shortcut", arguments: ["name": "Demo"])
        for result in [refusedOpen, refusedShortcut] {
            XCTAssertTrue(result.isError)
            XCTAssertTrue(toolText(of: result).contains("audit log"), toolText(of: result))
        }
        XCTAssertTrue(unsafe.opener.openCalls.isEmpty, "the URL must not be opened when the log is unsafe")
        XCTAssertFalse(FileManager.default.fileExists(atPath: unsafe.shortcutMarker.path))
    }

    func testOpenUrlPolicyRejectionIsLoggedAsRejected() throws {
        let rig = try makeRig()
        let result = rig.handlers.call(name: "open_url", arguments: ["url": "file:///etc/hosts"])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(rig.opener.openCalls.isEmpty)
        let entries = try auditEntries(in: rig.auditDirectory)
        XCTAssertEqual(entries.filter { $0["phase"] as? String == "request" }.first?["payload"] as? String, "file:///etc/hosts")
        let outcome = entries.first { $0["phase"] as? String == "result" }?["outcome"] as? String ?? ""
        XCTAssertTrue(outcome.hasPrefix("rejected:"), outcome)
    }

    func testUnknownAndUnavailableAppsReturnToolErrors() throws {
        let rig = try makeRig()
        let unknownTool = rig.handlers.call(name: "definitely_not_local", arguments: [:])
        XCTAssertTrue(unknownTool.isError)
        XCTAssertTrue(toolText(of: unknownTool).contains("unsupported local tool"), toolText(of: unknownTool))

        let dictionary = rig.handlers.call(name: "get_scripting_dictionary", arguments: ["app": "NoSuchApplicationForRouterTests"])
        XCTAssertTrue(dictionary.isError)
        XCTAssertTrue(toolText(of: dictionary).contains("app not found"), toolText(of: dictionary))

        let listing = rig.handlers.call(name: "list_shortcuts", arguments: [:])
        XCTAssertFalse(listing.isError, toolText(of: listing))
        XCTAssertTrue(toolText(of: listing).contains("listing"))
    }

    func testRunScriptEndToEnd() throws {
        let rig = try makeRig(markerRunner: false)
        let appleScriptSource = "return 1 + 1 -- distinctive-end-to-end-token"

        let appleScript = rig.handlers.call(name: "run_script", arguments: ["app": "Finder", "source": appleScriptSource])
        XCTAssertFalse(appleScript.isError, toolText(of: appleScript))
        XCTAssertTrue(toolText(of: appleScript).hasPrefix("2"), toolText(of: appleScript))
        XCTAssertTrue(toolText(of: appleScript).contains("exit=0"), toolText(of: appleScript))

        let javaScript = rig.handlers.call(
            name: "run_script",
            arguments: ["app": "Finder", "source": "1 + 1", "language": "javascript"]
        )
        XCTAssertFalse(javaScript.isError, toolText(of: javaScript))
        XCTAssertTrue(toolText(of: javaScript).hasPrefix("2"), toolText(of: javaScript))

        let entries = try auditEntries(in: rig.auditDirectory)
        XCTAssertTrue(entries.contains { $0["payload"] as? String == appleScriptSource })
        let outcomes = entries.filter { $0["phase"] as? String == "result" }.compactMap { $0["outcome"] as? String }
        XCTAssertEqual(outcomes, ["ok", "ok"])
        XCTAssertFalse(rig.stderr.values.isEmpty, "a metadata line is written for every entry")
        XCTAssertFalse(rig.stderr.values.contains { $0.contains("distinctive-end-to-end-token") }, "stderr carries no script text")
    }

    func testFirstContactFloorAppliesOnce() throws {
        let rig = try makeRig(markerRunner: false, firstContactMinimumTimeout: 3)
        let slow: [String: Any] = ["app": "FloorTestApp", "source": "delay 30", "timeout_s": 1]

        let firstStart = Date()
        let first = rig.handlers.call(name: "run_script", arguments: slow)
        let firstDuration = Date().timeIntervalSince(firstStart)
        XCTAssertTrue(first.isError)
        XCTAssertTrue(
            ["timeout", "timed out"].contains { toolText(of: first).lowercased().contains($0) },
            toolText(of: first)
        )
        XCTAssertTrue(toolText(of: first).contains("keeps running"), toolText(of: first))
        XCTAssertGreaterThanOrEqual(firstDuration, 2.5, "the first contact floor raises a 1s request to 3s")
        XCTAssertLessThan(firstDuration, 10)

        let warm = rig.handlers.call(name: "run_script", arguments: ["app": "FloorTestApp", "source": "return 1"])
        XCTAssertFalse(warm.isError, toolText(of: warm))

        let secondStart = Date()
        let second = rig.handlers.call(name: "run_script", arguments: slow)
        let secondDuration = Date().timeIntervalSince(secondStart)
        XCTAssertTrue(second.isError)
        XCTAssertLessThan(secondDuration, 10)
        XCTAssertLessThanOrEqual(secondDuration, firstDuration - 1.0, "the floor must not apply to a contacted app")
    }

    // MARK: - Locked session

    func testLockedGuardBlocksLocalTools() throws {
        let locked = MacSessionGuard(provider: LockedSessionProvider(), policy: .blockWhileLocked)
        let rig = try makeRig(guardOverride: locked)
        let arguments: [String: [String: Any]] = [
            "run_script": ["app": "Mail", "source": "return 1"],
            "get_scripting_dictionary": ["app": "Mail"],
            "open_url": ["url": "https://example.com"],
            "run_shortcut": ["name": "Demo"],
            "list_shortcuts": [:],
        ]
        for name in Self.allLocalToolNames {
            let result = rig.handlers.call(name: name, arguments: arguments[name] ?? [:])
            XCTAssertTrue(result.isError, name)
            XCTAssertTrue(toolText(of: result).contains("macOS is locked"), "\(name): \(toolText(of: result))")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: rig.scriptMarker.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: rig.shortcutMarker.path))
        XCTAssertTrue(rig.opener.openCalls.isEmpty)

        let entries = try auditEntries(in: rig.auditDirectory)
        let lockedOutcomes = entries.compactMap { $0["outcome"] as? String }
        XCTAssertEqual(lockedOutcomes.filter { $0 == "rejected:locked" }.count, 3, "\(lockedOutcomes)")
    }

    // MARK: - Tool definitions

    func testToolDefinitionsMatchSpecification() throws {
        let definitions = LocalChannelToolDefinitions.all
        XCTAssertEqual(definitions.map(\.name), Self.allLocalToolNames)
        XCTAssertEqual(LocalChannelToolNames.all, Set(Self.allLocalToolNames))
        XCTAssertEqual(LocalChannelToolNames.runScript, "run_script")
        XCTAssertEqual(LocalChannelToolNames.getScriptingDictionary, "get_scripting_dictionary")
        XCTAssertEqual(LocalChannelToolNames.openURL, "open_url")
        XCTAssertEqual(LocalChannelToolNames.runShortcut, "run_shortcut")
        XCTAssertEqual(LocalChannelToolNames.listShortcuts, "list_shortcuts")

        for definition in definitions {
            XCTAssertTrue(definition.description.hasSuffix("This tool is part of plugin `Computer Use`."), definition.name)
            XCTAssertEqual(definition.inputSchema["additionalProperties"] as? Bool, false, definition.name)
            XCTAssertEqual(definition.inputSchema["type"] as? String, "object", definition.name)
        }
        let byName = Dictionary(uniqueKeysWithValues: definitions.map { ($0.name, $0) })
        XCTAssertEqual(byName["run_script"]?.inputSchema["required"] as? [String], ["app", "source"])
        XCTAssertEqual(byName["get_scripting_dictionary"]?.inputSchema["required"] as? [String], ["app"])
        XCTAssertEqual(byName["open_url"]?.inputSchema["required"] as? [String], ["url"])
        XCTAssertEqual(byName["run_shortcut"]?.inputSchema["required"] as? [String], ["name"])
        XCTAssertNil(byName["list_shortcuts"]?.inputSchema["required"])
        XCTAssertTrue(byName["run_script"]?.description.contains("opt-in") ?? false)

        let runScriptProperties = try XCTUnwrap(byName["run_script"]?.inputSchema["properties"] as? [String: Any])
        let language = try XCTUnwrap(runScriptProperties["language"] as? [String: Any])
        XCTAssertEqual(language["enum"] as? [String], ["applescript", "javascript"])
        let timeout = try XCTUnwrap(runScriptProperties["timeout_s"] as? [String: Any])
        XCTAssertEqual(timeout["type"] as? String, "integer")

        for name in ["run_script", "open_url", "run_shortcut"] {
            let annotations = try XCTUnwrap(byName[name]?.annotations)
            XCTAssertEqual(annotations["destructiveHint"] as? Bool, true, name)
            XCTAssertEqual(annotations["openWorldHint"] as? Bool, true, name)
        }
        for name in ["get_scripting_dictionary", "list_shortcuts"] {
            let annotations = try XCTUnwrap(byName[name]?.annotations)
            XCTAssertEqual(annotations["readOnlyHint"] as? Bool, true, name)
            XCTAssertEqual(annotations["idempotentHint"] as? Bool, true, name)
            XCTAssertEqual(annotations["destructiveHint"] as? Bool, false, name)
            XCTAssertEqual(annotations["openWorldHint"] as? Bool, false, name)
        }
    }

    // MARK: - Fail-closed agent paths

    func testAgentDispatcherRefusesEveryLocalToolWhenUnlocked() {
        let dispatcher = ComputerUseToolDispatcher(service: ComputerUseService(), guard: unlockedGuard)
        for name in Self.allLocalToolNames {
            let result = dispatcher.callToolAsResult(name: name, arguments: ["app": "Mail", "source": "return 1"])
            XCTAssertTrue(result.isError, name)
            XCTAssertTrue(toolText(of: result).contains("unsupportedTool(\"\(name)\")"), "\(name): \(toolText(of: result))")
            XCTAssertFalse(toolText(of: result).contains("macOS is locked"), "refusal must not be the lock error")
        }
    }

    func testCallRunScriptFailsClosedThroughCLIRunner() throws {
        let output = try runOpenComputerUseCall(
            .single(toolName: "run_script", argumentsJSON: #"{"app":"Mail","source":"return 1"}"#, argumentsFile: nil),
            guard: unlockedGuard
        )
        XCTAssertTrue(output.hasToolError)
        let data = try JSONSerialization.data(withJSONObject: output.jsonObject, options: [.fragmentsAllowed])
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains("unsupportedTool"), text)
    }

    func testListedNeverContainsLocalTools() {
        let localNames = Set(Self.allLocalToolNames)
        XCTAssertTrue(Set(ToolDefinitions.listed(environment: Self.enabledEnvironment).map(\.name)).isDisjoint(with: localNames))
        XCTAssertTrue(Set(ToolDefinitions.all.map(\.name)).isDisjoint(with: localNames))
    }

    func testSanitizerDropsScriptingFlag() {
        let sanitized = MacSessionLockPolicy.sanitizePeerEnvironment([
            Self.flag: "1",
            "OPEN_COMPUTER_USE_DEBUG": "1",
            "OPEN_COMPUTER_USE_ALLOW_LOCKED": "1",
            "UNRELATED": "x",
        ])
        XCTAssertEqual(sanitized, ["OPEN_COMPUTER_USE_DEBUG": "1"])
    }
}
