import AppKit
import Darwin
import Foundation
import OpenComputerUseKit

private let appAgentCommand = "__open-computer-use-app-agent"
private let appAgentDisableEnvironmentKey = "OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY"
private let appAgentProcessStartDate = Date()

enum MacOSAppAgentProxy {
    static func isAgentInvocation(arguments: [String]) -> Bool {
        arguments.first == appAgentCommand
    }

    @MainActor
    static func runAgent(arguments: [String]) throws {
        guard arguments.count == 2 else {
            throw OpenComputerUseCLIError(message: "\(appAgentCommand) requires a socket path")
        }

        try MacOSAppAgentRuntime.run(socketPath: arguments[1])
    }

    static func shouldProxy(command: OpenComputerUseCLICommand) -> Bool {
        shouldUseMacOSAppAgentProxy(
            command: command,
            proxyDisabled: proxyDisabled,
            appBundleAvailable: PermissionSupport.currentAppBundleURL() != nil,
            runningFromLaunchServicesAppInstance: isRunningFromLaunchServicesAppInstance
        )
    }

    @MainActor
    static func runProxy(command: OpenComputerUseCLICommand, arguments: [String]) throws -> Int32 {
        let socketPath = defaultSocketPath()
        // Only a new MCP host session is an explicit request for computer use, so only it lifts an
        // earlier menu Quit. Other CLI commands (doctor, list-apps, ...) leave the marker in place.
        if case .mcp = command {
            AppAgentQuitMarker.clear(forSocketPath: socketPath)
        }

        // A permission snapshot is a pure read: it must never launch, replace or terminate the shared
        // agent, so it takes its own path ahead of connectOrLaunchAgent.
        if macOSAppAgentConnectionPolicy(for: command) == .readOnlySnapshot {
            return runReadOnlyPermissionSnapshot(socketPath: socketPath, arguments: arguments)
        }

        let client = try connectOrLaunchAgent(socketPath: socketPath)

        switch command {
        case .mcp:
            try proxyMCP(client: client, socketPath: socketPath)
            return EXIT_SUCCESS
        default:
            let response = try sendCLIRequest(arguments: arguments, client: client)
            if !response.stdout.isEmpty {
                FileHandle.standardOutput.write(Data(response.stdout.utf8))
            }
            if !response.stderr.isEmpty {
                FileHandle.standardError.write(Data(response.stderr.utf8))
            }
            return response.exitCode
        }
    }

    /// Prints the permission JSON from the already-running, current agent, because the grants belong
    /// to the app bundle. With no usable agent (none running, a stale build, or a lost connection)
    /// it reports only the app's persisted TCC record, never this process's own grants (the terminal
    /// that started the CLI is a different app), and fails when that record cannot be read. It never
    /// starts, replaces or terminates anything.
    @MainActor
    private static func runReadOnlyPermissionSnapshot(socketPath: String, arguments: [String]) -> Int32 {
        if let appURL = PermissionSupport.currentAppBundleURL(),
           let client = AppAgentSocketClient.connect(path: socketPath),
           (try? client.isCurrentAgent(for: appURL)) == true,
           let response = try? sendCLIRequest(arguments: arguments, client: client) {
            if !response.stdout.isEmpty {
                FileHandle.standardOutput.write(Data(response.stdout.utf8))
            }
            if !response.stderr.isEmpty {
                FileHandle.standardError.write(Data(response.stderr.utf8))
            }
            return response.exitCode
        }

        do {
            let json = try PermissionDiagnostics.fromAppTCCRecord().jsonText(source: .tcc)
            FileHandle.standardOutput.write(Data((json + "\n").utf8))
            return EXIT_SUCCESS
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            FileHandle.standardError.write(Data((message + "\n").utf8))
            return EXIT_FAILURE
        }
    }

    private static var proxyDisabled: Bool {
        let value = ProcessInfo.processInfo.environment[appAgentDisableEnvironmentKey]?.lowercased()
        return value == "1" || value == "true" || value == "yes" || value == "on"
    }

    private static var isRunningFromOpenComputerUseAppBundle: Bool {
        Bundle.main.bundleURL.standardizedFileURL.pathExtension == "app"
            && PermissionSupport.isOpenComputerUseBundleIdentifier(Bundle.main.bundleIdentifier)
    }

    private static var isRunningFromLaunchServicesAppInstance: Bool {
        isRunningFromOpenComputerUseAppBundle && getppid() == 1
    }

    private static func defaultSocketPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(
                openComputerUseAppAgentSocketFileName(
                    namespace: ProcessInfo.processInfo.environment[openComputerUseAppAgentSocketNamespaceEnvironmentKey]
                )
            )
            .standardizedFileURL
            .path
    }

    /// `allowLockedOptIn` carries the proxy's lock-screen opt-in into a freshly launched agent. The
    /// first launch passes it through; a relaunch after an agent crash must not, so it fails closed
    /// (lock-screen control off) until the operator quits Open Computer Use from the menu bar and
    /// restarts the host with the opt-in.
    @MainActor
    private static func connectOrLaunchAgent(socketPath: String, allowLockedOptIn: Bool = true) throws -> AppAgentSocketClient {
        guard let appURL = PermissionSupport.currentAppBundleURL() else {
            throw OpenComputerUseCLIError(message: "Unable to locate Open Computer Use.app for app-scoped macOS permissions.")
        }

        if let client = AppAgentSocketClient.connect(path: socketPath) {
            if (try? client.isCurrentAgent(for: appURL)) == true {
                return client
            }

            _ = try? client.request(["kind": "terminate"])
            unlink(socketPath)
        } else {
            unlink(socketPath)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = [appAgentCommand, socketPath]
        configuration.activates = false
        configuration.createsNewApplicationInstance = true
        // The lock-screen opt-in is security-sensitive: it must travel only through this
        // trusted launch environment (set here by the operator-run proxy from its real shell
        // env), never the per-call socket channel, so a same-uid client cannot forge it against
        // an already-running, TCC-authorized agent. Fixed for the agent's lifetime.
        if allowLockedOptIn, let allowLocked = ProcessInfo.processInfo.environment[MacSessionLockPolicy.environmentKey] {
            configuration.environment = [MacSessionLockPolicy.environmentKey: allowLocked]
        }

        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, _ in }

        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if let client = AppAgentSocketClient.connect(path: socketPath) {
                return client
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        throw OpenComputerUseCLIError(message: "Timed out waiting for Open Computer Use.app agent to start.")
    }

    /// Reconnects after an agent loss. A user Quit from the status menu keeps computer use stopped
    /// (no relaunch); a crash leaves no marker and relaunches, with the lock-screen opt-in off.
    @MainActor
    private static func reconnectAgent(socketPath: String) throws -> AppAgentSocketClient {
        if AppAgentQuitMarker.exists(forSocketPath: socketPath) {
            throw AppAgentQuitByUser()
        }
        return try connectOrLaunchAgent(socketPath: socketPath, allowLockedOptIn: false)
    }

    /// Relays MCP lines to the shared app agent for the life of the host connection. When the agent
    /// dies mid-request the host gets an error reply for that request and the proxy stays up: the next
    /// line reconnects (relaunching the agent if needed), so one agent crash does not close every
    /// session's MCP connection. A request the agent may have received is never replayed; it may be
    /// what crashed the agent, and actions are not idempotent. A request that could not even be
    /// written is safe to resend, so it is resent once on a fresh connection.
    @MainActor
    private static func proxyMCP(client initialClient: AppAgentSocketClient, socketPath: String) throws {
        var client: AppAgentSocketClient? = initialClient
        let router = LocalChannelRouter(isStopped: { AppAgentQuitMarker.exists(forSocketPath: socketPath) })
        try router.run { line in
            let expectsReply = AppAgentLossResponse.expectsReply(requestLine: line)

            if client == nil {
                if expectsReply {
                    do {
                        client = try reconnectAgent(socketPath: socketPath)
                    } catch is AppAgentQuitByUser {
                        return AppAgentLossResponse.response(
                            forRequestLine: line,
                            message: AppAgentLossResponse.quitMessage
                        )
                    } catch {
                        let reason = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                        return AppAgentLossResponse.response(
                            forRequestLine: line,
                            message: "The Open Computer Use app agent is not reachable (\(reason)). The call was NOT sent; try again."
                        )
                    }
                } else {
                    // A notification has no reply to carry a failure, so it never triggers a blocking
                    // relaunch: reuse an agent that is already up, otherwise drop it.
                    client = AppAgentSocketClient.connect(path: socketPath)
                }
            }
            guard let connected = client else {
                return nil
            }

            do {
                return try relayMCPLine(line, client: connected)
            } catch is AppAgentConnectionLost {
                client = nil
                return connectionLostResponse(forRequestLine: line, socketPath: socketPath)
            } catch is AppAgentRequestNotDelivered {
                client = nil
                guard expectsReply else {
                    return nil
                }
                // The write failed, so the agent never saw this line and one resend cannot duplicate it.
                let fresh: AppAgentSocketClient
                do {
                    fresh = try reconnectAgent(socketPath: socketPath)
                } catch is AppAgentQuitByUser {
                    return AppAgentLossResponse.response(
                        forRequestLine: line,
                        message: AppAgentLossResponse.quitMessage
                    )
                } catch {
                    return AppAgentLossResponse.response(
                        forRequestLine: line,
                        message: AppAgentLossResponse.notDeliveredMessage
                    )
                }
                client = fresh
                do {
                    return try relayMCPLine(line, client: fresh)
                } catch is AppAgentRequestNotDelivered {
                    client = nil
                    return AppAgentLossResponse.response(
                        forRequestLine: line,
                        message: AppAgentLossResponse.notDeliveredMessage
                    )
                } catch is AppAgentConnectionLost {
                    client = nil
                    return connectionLostResponse(forRequestLine: line, socketPath: socketPath)
                }
            }
        }
    }

    /// Reply for a call that was in flight when the agent went away: a menu Quit says so, anything
    /// else reads as a crash or restart.
    private static func connectionLostResponse(forRequestLine line: String, socketPath: String) -> String? {
        AppAgentLossResponse.lostConnectionResponse(
            forRequestLine: line,
            quitByUser: AppAgentQuitMarker.exists(forSocketPath: socketPath)
        )
    }

    /// Forwards one MCP request line to the app agent and returns its response line, if any.
    private static func relayMCPLine(_ line: String, client: AppAgentSocketClient) throws -> String? {
        let response = try client.request([
            "kind": "mcp",
            "line": line,
            "environment": proxiedEnvironment(forwardingImageSettings: StdioMCPServer.mayCaptureScreenshot(line: line)),
        ])
        return response["response"] as? String
    }

    private static func sendCLIRequest(arguments: [String], client: AppAgentSocketClient) throws -> CLIProxyResponse {
        let forwardedArguments = try inliningOpenComputerUseCallFiles(arguments: arguments)
        let response = try client.request([
            "kind": "cli",
            "arguments": forwardedArguments,
            "environment": proxiedEnvironment(
                forwardingImageSettings: openComputerUseCLIMayCaptureScreenshot(arguments: arguments)
            ),
        ])

        return CLIProxyResponse(
            stdout: response["stdout"] as? String ?? "",
            stderr: response["stderr"] as? String ?? "",
            exitCode: Int32(response["exitCode"] as? Int ?? 1)
        )
    }

    /// `forwardingImageSettings` attaches the caller's screenshot settings (environment over config file over
    /// defaults), resolved and validated here in the calling host's own process. The config file path itself never
    /// travels: the agent applies the values to this call and opens no screenshot config file a caller names. A
    /// `call --args-file` / `--calls-file` path is likewise read here and sent inline.
    private static func proxiedEnvironment(forwardingImageSettings: Bool) -> [String: String] {
        // The lock-screen opt-in is deliberately excluded from the per-call channel — it is fixed
        // at agent launch (see connectOrLaunchAgent) so a per-call client cannot forge it. The
        // agent applies the same filter on receipt; this side is a courtesy, not the enforcement.
        // Raw screenshot settings never travel: they are replaced by their validated form, or dropped when the
        // call takes no screenshot.
        OCUConfiguration.relayedEnvironment(
            processEnvironment: ProcessInfo.processInfo.environment,
            imageSettings: forwardingImageSettings ? OCUConfiguration.forwardedImageEnvironment() : nil
        )
    }
}

private struct CLIProxyResponse {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

@MainActor
private final class MacOSAppAgentRuntime: NSObject, NSApplicationDelegate {
    private let socketPath: String
    private var listener: AppAgentSocketListener?
    private var turnEndedObserver: NSObjectProtocol?
    private let connectionID = ControlConnectionID()
    private var statusMenu: ControlStatusMenuController?

    private init(socketPath: String) {
        self.socketPath = socketPath
    }

    static func run(socketPath: String) throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)

        let delegate = MacOSAppAgentRuntime(socketPath: socketPath)
        application.delegate = delegate
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register app-agent mode connection
        ControlActivityStore.shared.registerConnection(connectionID, isAppAgentMode: true)

        // A previous agent that was killed may have left other apps' windows pinned visible.
        recoverOpenComputerUseBackgroundWindowState()

        // Install status menu — restart enabled in app-agent mode
        let menu = ControlStatusMenuController()
        menu.restartAction = { [weak self] in
            self?.restartAgent()
        }
        menu.openPermissionWindowAction = {
            PermissionOnboardingApp.present()
        }
        menu.copyDiagnosticsAction = { [weak self] in
            self?.copyDiagnosticsToClipboard()
        }
        menu.quitAction = { [weak self] in
            self?.quitFromMenu()
        }
        menu.install()
        statusMenu = menu

        turnEndedObserver = DistributedNotificationCenter.default().addObserver(
            forName: openComputerUseTurnEndedNotificationName,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                resetOpenComputerUseVisualCursor()
            }
        }

        do {
            let listener = try AppAgentSocketListener(path: socketPath)
            self.listener = listener
            listener.start()
        } catch {
            writeAgentError(error)
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let turnEndedObserver {
            DistributedNotificationCenter.default().removeObserver(turnEndedObserver)
        }
        ControlActivityStore.shared.unregisterConnection(connectionID)
        statusMenu?.uninstall()
        listener?.stop()
        releaseOpenComputerUseBackgroundWindowState()
    }

    /// The status-menu Quit: record that the user stopped computer use so a proxy does not relaunch
    /// this agent behind their back. Restart Agent and the `terminate` request (bundle eviction)
    /// deliberately skip this, because both expect a relaunch.
    private func quitFromMenu() {
        AppAgentQuitMarker.write(forSocketPath: socketPath)
        NSApp.terminate(nil)
    }

    private func restartAgent() {
        // Terminate this agent instance; the proxy will relaunch a fresh one on next connection
        listener?.stop()
        NSApp.terminate(nil)
    }

    private func copyDiagnosticsToClipboard() {
        let permissions = PermissionDiagnostics.current()
        let lines: [String] = [
            "Open Computer Use diagnostics",
            "Mode: app-agent",
            "Socket peer-auth: \(SocketPeerAuthenticator.statusDescription)",
            "",
            permissions.summary,
        ]
        let text = lines.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func writeAgentError(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}

private final class AppAgentSocketListener: @unchecked Sendable {
    private let path: String
    private let socketFD: Int32
    private var running = true

    init(path: String) throws {
        self.path = path
        unlink(path)

        socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFD >= 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
        try withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            try pointer.withMemoryRebound(to: CChar.self, capacity: pathCapacity) { buffer in
                let bytes = Array(path.utf8)
                guard bytes.count < pathCapacity else {
                    throw OpenComputerUseCLIError(message: "Socket path is too long: \(path)")
                }
                for index in 0..<bytes.count {
                    buffer[index] = CChar(bitPattern: bytes[index])
                }
                buffer[bytes.count] = 0
            }
        }

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            close(socketFD)
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }

        guard listen(socketFD, 16) == 0 else {
            close(socketFD)
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }

        guard chmod(path, mode_t(S_IRUSR | S_IWUSR)) == 0 else {
            close(socketFD)
            unlink(path)
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
    }

    func start() {
        Thread.detachNewThread {
            self.acceptLoop()
        }
    }

    func stop() {
        running = false
        close(socketFD)
        unlink(path)
    }

    private func acceptLoop() {
        while running {
            let clientFD = accept(socketFD, nil, nil)
            guard clientFD >= 0 else {
                if running {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                continue
            }

            // A proxy that dies mid-call must not kill this shared agent when the reply is written:
            // the write has to fail with EPIPE instead of raising SIGPIPE.
            disableAppAgentSocketSigPipe(clientFD)

            // Authenticate the connecting process before it can drive the TCC-authorized agent.
            // Same-uid alone is insufficient (any user process could connect); require the peer to
            // be code-signed by the same developer as this agent, with a same-uid dev fallback.
            switch SocketPeerAuthenticator.authenticate(fileDescriptor: clientFD) {
            case .allow:
                Thread.detachNewThread {
                    AppAgentConnection(fileDescriptor: clientFD).run()
                }
            case .allowUnsignedFallback:
                UnsignedPeerFallbackNotice.shared.emitIfNeeded()
                Thread.detachNewThread {
                    AppAgentConnection(fileDescriptor: clientFD).run()
                }
            case let .reject(reason):
                fputs("[open-computer-use] rejected app-agent socket peer: \(reason)\n", stderr)
                close(clientFD)
            }
        }
    }
}

private final class AppAgentConnection: @unchecked Sendable {
    private let fileDescriptor: Int32
    private let server = StdioMCPServer()

    init(fileDescriptor: Int32) {
        self.fileDescriptor = fileDescriptor
    }

    func run() {
        guard let file = fdopen(fileDescriptor, "r+") else {
            close(fileDescriptor)
            return
        }
        defer {
            // This host's session is over: release its window pins, and only its own.
            server.endSession()
            fclose(file)
        }

        while let line = readAppAgentLine(file) {
            let response = handle(requestLine: line)
            writeAgentResponse(response, to: file)
        }
    }

    private func handle(requestLine: String) -> [String: Any] {
        do {
            guard let request = try JSONSerialization.jsonObject(with: Data(requestLine.utf8)) as? [String: Any],
                  let kind = request["kind"] as? String
            else {
                return ["error": "Invalid app-agent request"]
            }

            switch kind {
            case "agentInfo":
                return [
                    "bundleIdentifier": Bundle.main.bundleIdentifier ?? "",
                    "bundleURL": Bundle.main.bundleURL.standardizedFileURL.path,
                    "executableURL": Bundle.main.executableURL?.standardizedFileURL.path ?? "",
                    "processStartTime": appAgentProcessStartDate.timeIntervalSince1970,
                ]
            case "terminate":
                Task { @MainActor in
                    NSApp.terminate(nil)
                }
                return ["ok": true]
            case "mcp":
                let line = request["line"] as? String ?? ""
                let environment = sanitizedPeerEnvironment(request["environment"] as? [String: String] ?? [:])
                // The per-call environment is also passed explicitly, so settings such as the decision-model URL come
                // from this host alone, never from another host's overrides that are set on the shared process
                // environment at the same moment. decide_next_action reads nothing else from the environment and
                // blocks on the model for seconds, so it skips the process-wide override lock entirely. The
                // screenshot settings travel only with the call, so a call whose only values are those takes no lock.
                let response: String?
                if StdioMCPServer.readsOnlyCallEnvironment(line: line) {
                    response = server.handle(line: line, environment: environment)
                } else {
                    response = AppAgentEnvironment.withOverrides(OCUConfiguration.processOverrides(from: environment)) {
                        server.handle(line: line, environment: environment)
                    }
                }
                if let response {
                    return ["response": response]
                }
                return ["response": NSNull()]
            case "cli":
                let arguments = request["arguments"] as? [String] ?? []
                let environment = sanitizedPeerEnvironment(request["environment"] as? [String: String] ?? [:])
                // Same rule as the "mcp" kind: runCLI hands the per-call environment to the call explicitly, and a
                // single `call decide_next_action` reads nothing else, so its model round trip skips the lock.
                let response: CLIProxyResponse
                if openComputerUseCLIReadsOnlyCallEnvironment(arguments: arguments) {
                    response = runCLI(arguments: arguments, environment: environment)
                } else {
                    response = AppAgentEnvironment.withOverrides(OCUConfiguration.processOverrides(from: environment)) {
                        runCLI(arguments: arguments, environment: environment)
                    }
                }
                return [
                    "stdout": response.stdout,
                    "stderr": response.stderr,
                    "exitCode": Int(response.exitCode),
                ]
            default:
                return ["error": "Unknown app-agent request kind: \(kind)"]
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            return ["error": message]
        }
    }

    /// A peer's environment is untrusted input, so the agent re-applies the filter rather than
    /// trusting that the sender applied it. See `MacSessionLockPolicy.sanitizePeerEnvironment`.
    private func sanitizedPeerEnvironment(_ environment: [String: String]) -> [String: String] {
        MacSessionLockPolicy.sanitizePeerEnvironment(environment)
    }

    private func runCLI(arguments: [String], environment: [String: String]) -> CLIProxyResponse {
        do {
            let command = try parseOpenComputerUseCLI(arguments: arguments)

            switch command {
            case .launchOnboarding:
                let permissions = PermissionDiagnostics.current()
                if !permissions.allGranted {
                    Task { @MainActor in
                        PermissionOnboardingApp.present()
                    }
                }
                return CLIProxyResponse(stdout: "", stderr: "", exitCode: EXIT_SUCCESS)

            case let .doctor(json):
                let permissions = PermissionDiagnostics.current()
                if shouldPresentPermissionOnboarding(json: json, missingPermissions: permissions.missingPermissions) {
                    Task { @MainActor in
                        PermissionOnboardingApp.present()
                    }
                }
                return CLIProxyResponse(
                    stdout: (try json ? permissions.jsonText(source: .agent) : permissions.summary) + "\n",
                    stderr: "",
                    exitCode: EXIT_SUCCESS
                )

            case .listApps:
                let service = ComputerUseService()
                return CLIProxyResponse(stdout: (service.listApps().primaryText ?? "") + "\n", stderr: "", exitCode: EXIT_SUCCESS)

            case let .snapshot(app, textLimit, treeLimits):
                let service = ComputerUseService()
                let text = try service.withForwardedImageSettings(environment: environment) {
                    try service.getAppState(app: app, textLimit: textLimit, treeLimits: treeLimits).primaryText ?? ""
                }
                return CLIProxyResponse(stdout: text + "\n", stderr: "", exitCode: EXIT_SUCCESS)

            case let .call(invocation):
                let output = try runOpenComputerUseCall(invocation, callEnvironment: environment)
                return CLIProxyResponse(
                    stdout: try output.jsonText() + "\n",
                    stderr: "",
                    exitCode: output.hasToolError ? EXIT_FAILURE : EXIT_SUCCESS
                )

            default:
                return CLIProxyResponse(stdout: "", stderr: "Unsupported proxied command.\n", exitCode: EXIT_FAILURE)
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            return CLIProxyResponse(stdout: "", stderr: message + "\n", exitCode: EXIT_FAILURE)
        }
    }
}

private enum AppAgentEnvironment {
    private static let lock = NSLock()

    static func withOverrides<T>(_ overrides: [String: String], _ body: () throws -> T) rethrows -> T {
        guard !overrides.isEmpty else {
            return try body()
        }

        lock.lock()
        defer { lock.unlock() }

        let previousValues = Dictionary(
            uniqueKeysWithValues: overrides.keys.map { key in
                (key, ProcessInfo.processInfo.environment[key])
            }
        )
        for (key, value) in overrides {
            setenv(key, value, 1)
        }

        defer {
            for (key, previousValue) in previousValues {
                if let previousValue {
                    setenv(key, previousValue, 1)
                } else {
                    unsetenv(key)
                }
            }
        }

        return try body()
    }
}

/// The agent closed its socket before answering (it crashed, was restarted, or was quit).
/// Distinct from an error the agent reported, so the MCP proxy can reconnect instead of exiting.
private struct AppAgentConnectionLost: LocalizedError {
    var errorDescription: String? { "Open Computer Use.app agent closed the connection." }
}

/// The user quit Open Computer Use from its status menu, so the proxy must not relaunch the agent.
private struct AppAgentQuitByUser: Error {}

/// The request could not be written because the agent was already gone, so the agent never saw it.
/// Unlike `AppAgentConnectionLost`, the call provably did not run and may be sent again.
private struct AppAgentRequestNotDelivered: LocalizedError {
    var errorDescription: String? { "Open Computer Use.app agent is not reachable." }
}

private final class AppAgentSocketClient: @unchecked Sendable {
    private let file: UnsafeMutablePointer<FILE>

    private init(file: UnsafeMutablePointer<FILE>) {
        self.file = file
    }

    deinit {
        fclose(file)
    }

    static func connect(path: String) -> AppAgentSocketClient? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            return nil
        }
        // Close-on-exec so a script or helper process spawned later never inherits the relay socket.
        guard fcntl(fd, F_SETFD, FD_CLOEXEC) == 0 else {
            close(fd)
            return nil
        }
        // A write to an agent that already died must fail with EPIPE, not kill this proxy with SIGPIPE.
        disableAppAgentSocketSigPipe(fd)

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
        let copied = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: pathCapacity) { buffer -> Bool in
                let bytes = Array(path.utf8)
                guard bytes.count < pathCapacity else {
                    return false
                }
                for index in 0..<bytes.count {
                    buffer[index] = CChar(bitPattern: bytes[index])
                }
                buffer[bytes.count] = 0
                return true
            }
        }

        guard copied else {
            close(fd)
            return nil
        }

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0, let file = fdopen(fd, "r+") else {
            close(fd)
            return nil
        }

        return AppAgentSocketClient(file: file)
    }

    func request(_ object: [String: Any]) throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
        guard let line = String(data: data, encoding: .utf8) else {
            throw ComputerUseError.message("Failed to encode app-agent request.")
        }

        guard writeAppAgentLine(line, to: file) else {
            throw AppAgentRequestNotDelivered()
        }

        guard let responseLine = readAppAgentLine(file),
              let response = try JSONSerialization.jsonObject(with: Data(responseLine.utf8)) as? [String: Any]
        else {
            throw AppAgentConnectionLost()
        }

        if let error = response["error"] as? String {
            throw ComputerUseError.message(error)
        }

        return response
    }

    func isCurrentAgent(for appURL: URL) throws -> Bool {
        let response = try request(["kind": "agentInfo"])
        let expectedBundleURL = appURL.standardizedFileURL

        guard response["bundleURL"] as? String == expectedBundleURL.path else {
            return false
        }

        guard let processStartTime = response["processStartTime"] as? TimeInterval else {
            return false
        }

        guard let executableURL = executableURL(for: expectedBundleURL),
              let modifiedAt = try? executableURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        else {
            return true
        }

        return processStartTime + 0.5 >= modifiedAt.timeIntervalSince1970
    }

    private func executableURL(for appURL: URL) -> URL? {
        guard let bundle = Bundle(url: appURL),
              let executableName = bundle.object(forInfoDictionaryKey: kCFBundleExecutableKey as String) as? String,
              !executableName.isEmpty
        else {
            return nil
        }

        return appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent(executableName)
            .standardizedFileURL
    }
}

private func writeAgentResponse(_ object: [String: Any], to file: UnsafeMutablePointer<FILE>) {
    if let data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]),
       let line = String(data: data, encoding: .utf8)
    {
        writeAppAgentLine(line, to: file)
    }
}
