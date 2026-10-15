import Foundation

/// A marker file beside the app-agent socket that records "the user quit Open Computer Use from its
/// status menu". The agent writes it on that one action; an MCP proxy that loses its agent checks it
/// before relaunching, so a deliberate Quit keeps computer use stopped while a crash still
/// self-heals. A fresh proxy start (a new host session) clears it and launches normally.
public enum AppAgentQuitMarker {
    /// The marker path for the agent that listens on `socketPath`.
    public static func path(forSocketPath socketPath: String) -> String {
        socketPath + ".quit"
    }

    /// Records a user-initiated quit. Owner-only, like the socket. Returns whether the marker was written.
    @discardableResult
    public static func write(forSocketPath socketPath: String) -> Bool {
        FileManager.default.createFile(
            atPath: path(forSocketPath: socketPath),
            contents: Data(),
            attributes: [.posixPermissions: 0o600]
        )
    }

    /// Whether the user quit the agent for `socketPath` and has not started a new session since.
    public static func exists(forSocketPath socketPath: String) -> Bool {
        var info = stat()
        return lstat(path(forSocketPath: socketPath), &info) == 0
    }

    /// Removes the marker; a missing marker is not an error.
    public static func clear(forSocketPath socketPath: String) {
        unlink(path(forSocketPath: socketPath))
    }
}
