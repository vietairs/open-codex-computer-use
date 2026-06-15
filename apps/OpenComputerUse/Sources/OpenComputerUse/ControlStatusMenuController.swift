import AppKit
import OpenComputerUseKit

@MainActor
final class ControlStatusMenuController {
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?

    // Commands injected by the runtime owner
    var openPermissionWindowAction: (() -> Void)?
    var copyDiagnosticsAction: (() -> Void)?
    var quitAction: (() -> Void)?
    var restartAction: (() -> Void)?  // nil in direct AppKit MCP mode

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "⚙︎"
        item.button?.toolTip = "Open Computer Use"
        let menu = buildMenu()
        item.menu = menu
        self.statusItem = item
        self.menu = menu
    }

    func uninstall() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    func updateFromStore() {
        guard let button = statusItem?.button else { return }
        let store = ControlActivityStore.shared
        let connectionCount = store.connections.count
        let hasActive = store.connections.values.contains(where: {
            if case .active = $0.status { return true }
            return false
        })
        let hasLocked = store.connections.values.contains(where: {
            if case .locked = $0.status { return true }
            return false
        })
        let hasError = store.connections.values.contains(where: {
            if case .recentError = $0.status { return true }
            return false
        })

        if hasLocked {
            button.title = "⚙︎🔒"
        } else if hasError {
            button.title = "⚙︎⚠"
        } else if hasActive {
            button.title = "⚙︎●"
        } else {
            button.title = "⚙︎"
        }
        button.toolTip = "Open Computer Use (\(connectionCount) connection\(connectionCount == 1 ? "" : "s"))"
        rebuildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        rebuildMenuItems(menu)
        return menu
    }

    private func rebuildMenu() {
        guard let menu = menu else { return }
        menu.removeAllItems()
        rebuildMenuItems(menu)
    }

    private func rebuildMenuItems(_ menu: NSMenu) {
        let store = ControlActivityStore.shared

        if store.connections.isEmpty {
            let item = NSMenuItem(title: "No active connections", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for state in store.connections.values.sorted(by: { $0.isAppAgentMode && !$1.isAppAgentMode }) {
                let statusStr: String
                switch state.status {
                case .idle: statusStr = "idle"
                case .active: statusStr = "active"
                case .locked: statusStr = "locked"
                case .permissionMissing: statusStr = "permission missing"
                case .recentError(let msg): statusStr = "error: \(msg)"
                }
                let appStr = state.appDisplayName.map { " — \($0)" } ?? ""
                let toolStr = state.lastToolName.map { " [\($0)]" } ?? ""
                let title = "\(state.isAppAgentMode ? "agent" : "direct")\(appStr)\(toolStr): \(statusStr)"
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        let permItem = NSMenuItem(title: "Open Permissions…", action: #selector(openPermissionWindow), keyEquivalent: "")
        permItem.target = self
        menu.addItem(permItem)

        let diagItem = NSMenuItem(title: "Copy Diagnostics", action: #selector(copyDiagnostics), keyEquivalent: "")
        diagItem.target = self
        menu.addItem(diagItem)

        menu.addItem(NSMenuItem.separator())

        // Restart: only available in app-agent mode
        let hasAgentModeConnection = store.connections.values.contains(where: { $0.isAppAgentMode })
        let restartItem = NSMenuItem(
            title: "Restart Agent",
            action: restartAction != nil && hasAgentModeConnection ? #selector(restartAgent) : nil,
            keyEquivalent: ""
        )
        restartItem.target = self
        if restartAction == nil || !hasAgentModeConnection {
            restartItem.isEnabled = false
            if restartAction == nil {
                restartItem.toolTip = "Not available in direct MCP mode. Relaunch the host to restart."
            }
        }
        menu.addItem(restartItem)

        let quitItem = NSMenuItem(title: "Quit Open Computer Use", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func openPermissionWindow() {
        openPermissionWindowAction?()
    }

    @objc private func copyDiagnostics() {
        copyDiagnosticsAction?()
    }

    @objc private func restartAgent() {
        restartAction?()
    }

    @objc private func quit() {
        quitAction?()
    }
}
