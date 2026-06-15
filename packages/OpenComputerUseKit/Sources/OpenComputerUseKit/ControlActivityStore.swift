import Foundation

public typealias ControlConnectionID = UUID

public enum ControlConnectionStatus: Sendable {
    case idle
    case active
    case locked           // session is locked
    case permissionMissing
    case recentError(String)  // short message only, no raw args
}

public struct ControlActivityEvent {
    public let toolName: String           // e.g. "click"
    public let appDisplayName: String?   // from AppSnapshot.app.name
    public let bundleIdentifier: String? // from AppSnapshot.app.bundleIdentifier
    public let pid: pid_t?
    // NO: text, element labels, raw args, screenshot data, AX text

    public init(toolName: String, appDisplayName: String? = nil, bundleIdentifier: String? = nil, pid: pid_t? = nil) {
        self.toolName = toolName
        self.appDisplayName = appDisplayName
        self.bundleIdentifier = bundleIdentifier
        self.pid = pid
    }
}

public struct ControlConnectionState: Sendable {
    public let id: ControlConnectionID
    public var status: ControlConnectionStatus
    public var appDisplayName: String?
    public var bundleIdentifier: String?
    public var pid: pid_t?
    public var lastToolName: String?
    public var lastActivityAt: Date?
    public let isAppAgentMode: Bool  // false = direct AppKit MCP mode

    public init(
        id: ControlConnectionID,
        status: ControlConnectionStatus,
        appDisplayName: String?,
        bundleIdentifier: String?,
        pid: pid_t?,
        lastToolName: String?,
        lastActivityAt: Date?,
        isAppAgentMode: Bool
    ) {
        self.id = id
        self.status = status
        self.appDisplayName = appDisplayName
        self.bundleIdentifier = bundleIdentifier
        self.pid = pid
        self.lastToolName = lastToolName
        self.lastActivityAt = lastActivityAt
        self.isAppAgentMode = isAppAgentMode
    }
}

@MainActor
public final class ControlActivityStore {
    public static let shared = ControlActivityStore()

    public private(set) var connections: [ControlConnectionID: ControlConnectionState] = [:]
    private var nowProvider: () -> Date

    private let staleInterval: TimeInterval = 5 * 60  // 5 minutes
    // swiftlint:disable:next unused_declaration
    private let errorCollapseInterval: TimeInterval = 30  // errors collapse to idle after 30s

    public init(nowProvider: @escaping () -> Date = { Date() }) {
        self.nowProvider = nowProvider
    }

    public func registerConnection(_ id: ControlConnectionID, isAppAgentMode: Bool) {
        connections[id] = ControlConnectionState(
            id: id,
            status: .idle,
            appDisplayName: nil,
            bundleIdentifier: nil,
            pid: nil,
            lastToolName: nil,
            lastActivityAt: nil,
            isAppAgentMode: isAppAgentMode
        )
    }

    public func unregisterConnection(_ id: ControlConnectionID) {
        connections.removeValue(forKey: id)
    }

    public func record(_ event: ControlActivityEvent, forConnection id: ControlConnectionID) {
        guard connections[id] != nil else { return }
        connections[id]?.status = .active
        connections[id]?.lastToolName = event.toolName
        connections[id]?.appDisplayName = event.appDisplayName
        connections[id]?.bundleIdentifier = event.bundleIdentifier
        connections[id]?.pid = event.pid
        connections[id]?.lastActivityAt = nowProvider()
    }

    public func recordError(_ message: String, forConnection id: ControlConnectionID) {
        guard connections[id] != nil else { return }
        connections[id]?.status = .recentError(message)
        connections[id]?.lastActivityAt = nowProvider()
    }

    public func recordLocked(forConnection id: ControlConnectionID) {
        guard connections[id] != nil else { return }
        connections[id]?.status = .locked
        connections[id]?.lastActivityAt = nowProvider()
    }

    public func markTurnEnded(connectionID: ControlConnectionID?) {
        if let id = connectionID {
            connections[id]?.status = .idle
        } else {
            for id in connections.keys {
                connections[id]?.status = .idle
            }
        }
    }

    public func purgeStaleConnections() {
        let now = nowProvider()
        connections = connections.filter { _, state in
            guard let lastActivity = state.lastActivityAt else { return true }
            return now.timeIntervalSince(lastActivity) < staleInterval
        }
    }
}
