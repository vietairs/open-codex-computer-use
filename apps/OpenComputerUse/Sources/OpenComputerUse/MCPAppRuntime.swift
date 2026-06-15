import AppKit
import Foundation
import OpenComputerUseKit

final class MCPAppRuntime: NSObject, NSApplicationDelegate {
    private let server: StdioMCPServer
    private var runtimeError: Error?
    private var turnEndedObserver: NSObjectProtocol?
    private let connectionID = ControlConnectionID()
    private var statusMenu: ControlStatusMenuController?

    private init(server: StdioMCPServer) {
        self.server = server
    }

    @MainActor
    static func run(server: StdioMCPServer) throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)

        let delegate = MCPAppRuntime(server: server)
        application.delegate = delegate
        application.run()

        if let runtimeError = delegate.runtimeError {
            throw runtimeError
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register direct AppKit MCP connection (not app-agent mode)
        ControlActivityStore.shared.registerConnection(connectionID, isAppAgentMode: false)

        // Install status menu — restart disabled in direct MCP mode (DoS vector)
        let menu = ControlStatusMenuController()
        menu.restartAction = nil
        menu.openPermissionWindowAction = {
            PermissionOnboardingApp.present()
        }
        menu.copyDiagnosticsAction = { [weak self] in
            self?.copyDiagnosticsToClipboard()
        }
        menu.quitAction = {
            NSApp.terminate(nil)
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
        Thread.detachNewThreadSelector(#selector(processStandardIO), toTarget: self, with: nil)

        // Proactive startup check — warn if CGSSessionScreenIsLocked key is absent (version skew indicator)
        let startupSnapshot = MacSessionGuard().currentState()
        if startupSnapshot.isUnknown {
            fputs("[open-computer-use] WARNING: CGSSessionScreenIsLocked key absent from CGSessionCopyCurrentDictionary at startup (keys seen: \(startupSnapshot.rawKeysSeen.sorted().joined(separator: ","))). Lock detection will treat all states as locked. Verify macOS version compatibility.\n", stderr)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let turnEndedObserver {
            DistributedNotificationCenter.default().removeObserver(turnEndedObserver)
        }
        ControlActivityStore.shared.unregisterConnection(connectionID)
        statusMenu?.uninstall()
    }

    private func copyDiagnosticsToClipboard() {
        let permissions = PermissionDiagnostics.current()
        let lines: [String] = [
            "Open Computer Use diagnostics",
            "Mode: direct AppKit MCP (not app-agent)",
            "Note: To restart, relaunch the host process.",
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

    @objc
    private func processStandardIO() {
        do {
            try server.run()
        } catch {
            runtimeError = error
        }

        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
    }
}
