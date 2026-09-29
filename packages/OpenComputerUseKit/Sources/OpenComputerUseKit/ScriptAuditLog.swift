import CryptoKit
import Foundation

/// One record of a script-channel call (`run_script`, `open_url`, `run_shortcut`).
///
/// A request entry carries the full payload so the operator can reconstruct what ran; the matching result entry
/// carries only the exit status, duration and a short outcome. `targetApp` is the app the agent *declared*, not the
/// app the script actually tells, so treat it as advisory.
public struct ScriptAuditEntry: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case runScript = "run_script"
        case openURL = "open_url"
        case runShortcut = "run_shortcut"
    }

    public enum Phase: String, Sendable {
        case request
        case result
    }

    public let kind: Kind
    public let phase: Phase
    public let timestamp: Date
    public let relayPID: Int32
    public let parentPID: Int32
    public let targetApp: String?
    public let payload: String?          // full script text / URL / "name\ninput"; request phase only
    public let payloadSHA256: String
    public let exitStatus: Int32?
    public let durationMilliseconds: Int?
    public let outcome: String?

    public init(
        kind: Kind, phase: Phase, timestamp: Date = Date(),
        relayPID: Int32 = getpid(), parentPID: Int32 = getppid(),
        targetApp: String?, payload: String?, payloadSHA256: String,
        exitStatus: Int32? = nil, durationMilliseconds: Int? = nil, outcome: String? = nil
    ) {
        self.kind = kind
        self.phase = phase
        self.timestamp = timestamp
        self.relayPID = relayPID
        self.parentPID = parentPID
        self.targetApp = targetApp
        self.payload = payload
        self.payloadSHA256 = payloadSHA256
        self.exitStatus = exitStatus
        self.durationMilliseconds = durationMilliseconds
        self.outcome = outcome
    }
}

public enum ScriptAuditLogError: Error, Equatable {
    case directoryUnsafe(String)
    case fileUnsafe(String)
    case writeFailed(String)
}

/// Append-only, owner-only audit log for script-channel calls.
///
/// Safety properties: the log directory must be a real directory owned by the current user with no group/other
/// access; the log file is opened with `O_NOFOLLOW`, must be a regular file owned by the current user with no
/// group/other access, and is written with a single `write(2)` under an exclusive `flock` so concurrent relays never
/// interleave. When the file reaches the size limit it is renamed to a single previous generation. No descriptor is
/// kept open between calls. Standard error receives a metadata line only, never the payload.
public final class ScriptAuditLog: @unchecked Sendable {
    public static let fileName = "scripts.log"
    public static let rotatedFileName = "scripts.log.1"
    public static let defaultMaximumFileBytes = 10 * 1024 * 1024

    public static var defaultDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("OpenComputerUse", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
    }

    /// Longest agent-influenced value (in Unicode scalars) that reaches the standard-error metadata line.
    private static let metadataValueLimit = 128
    private static let maximumOpenAttempts = 3

    public let directory: URL
    private let maximumFileBytes: Int
    private let standardErrorWriter: @Sendable (String) -> Void

    public init(
        directory: URL = ScriptAuditLog.defaultDirectory,
        maximumFileBytes: Int = ScriptAuditLog.defaultMaximumFileBytes,
        standardErrorWriter: @escaping @Sendable (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) }
    ) {
        self.directory = directory
        self.maximumFileBytes = maximumFileBytes
        self.standardErrorWriter = standardErrorWriter
    }

    public func record(_ entry: ScriptAuditEntry) throws {
        try ensureSafeDirectory()
        let line = try Self.encodedLine(for: entry)
        let path = directory.appendingPathComponent(Self.fileName).path
        let rotatedPath = directory.appendingPathComponent(Self.rotatedFileName).path

        var descriptor = try openLockedLogFile(at: path)
        if Self.currentSize(of: descriptor) >= off_t(maximumFileBytes) {
            // Only the holder of the live inode's lock reaches this point, and it renames exactly once: writers that
            // waited on the old inode notice the mismatch in `openLockedLogFile` and reopen the fresh file.
            if rename(path, rotatedPath) != 0 {
                let code = errno
                close(descriptor)
                throw ScriptAuditLogError.writeFailed("could not rotate the log (errno \(code))")
            }
            close(descriptor)
            descriptor = try openLockedLogFile(at: path)
        }
        defer { close(descriptor) }  // closing also releases the lock

        try Self.writeWhole(line, to: descriptor)
        standardErrorWriter(Self.metadataLine(for: entry))
    }

    public static func sha256Hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func metadataLine(for entry: ScriptAuditEntry) -> String {
        let app = entry.targetApp.map(sanitizedMetadataValue) ?? "-"
        let digest = sanitizedMetadataValue(String(entry.payloadSHA256.prefix(16)))
        let exit = entry.exitStatus.map { String($0) } ?? "-"
        let duration = entry.durationMilliseconds.map { String($0) } ?? "-"
        let outcome = entry.outcome.map(sanitizedMetadataValue) ?? "-"
        return "[open-computer-use] \(entry.kind.rawValue) \(entry.phase.rawValue) app=\(app) sha256=\(digest) "
            + "exit=\(exit) duration_ms=\(duration) outcome=\(outcome)\n"
    }

    // MARK: - Metadata line

    /// Caps the value, then writes every C0 or C1 control, line-separator or bidi-override scalar as a visible
    /// `\u{XXXX}` escape, so the value can never start a new line in a terminal or a log collector (NEL, 8-bit CSI)
    /// or visually reorder the rest of the line. Works on scalars because `"\r\n"` is a single `Character`.
    private static func sanitizedMetadataValue(_ value: String) -> String {
        var result = ""
        for scalar in value.unicodeScalars.prefix(metadataValueLimit) {
            switch scalar.value {
            case 0x00...0x1F, 0x7F...0x9F, 0x2028, 0x2029, 0x202A...0x202E, 0x2066...0x2069:
                result += "\\u{" + String(format: "%04X", scalar.value) + "}"
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    // MARK: - Encoding

    private static func encodedLine(for entry: ScriptAuditEntry) throws -> Data {
        var object: [String: Any] = [
            "kind": entry.kind.rawValue,
            "phase": entry.phase.rawValue,
            "timestamp": timestampString(entry.timestamp),
            "relay_pid": Int(entry.relayPID),
            "parent_pid": Int(entry.parentPID),
            "payload_sha256": entry.payloadSHA256,
        ]
        if let targetApp = entry.targetApp { object["target_app"] = targetApp }
        if let payload = entry.payload { object["payload"] = payload }
        if let exitStatus = entry.exitStatus { object["exit_status"] = Int(exitStatus) }
        if let duration = entry.durationMilliseconds { object["duration_ms"] = duration }
        if let outcome = entry.outcome { object["outcome"] = outcome }

        do {
            var data = try JSONSerialization.data(
                withJSONObject: object,
                options: [.sortedKeys, .withoutEscapingSlashes]
            )
            data.append(0x0A)
            return data
        } catch {
            throw ScriptAuditLogError.writeFailed("could not encode the entry: \(error.localizedDescription)")
        }
    }

    private static func timestampString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    // MARK: - File handling

    private func ensureSafeDirectory() throws {
        // The last component is created by `mkdir(2)` with its final mode in one step. Creating it through
        // FileManager makes it briefly world-readable, which a concurrent relay would reject as unsafe.
        try? FileManager.default.createDirectory(
            at: directory.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        _ = mkdir(directory.path, 0o700)  // EEXIST is fine; the checks below decide whether it is usable
        var info = stat()
        guard lstat(directory.path, &info) == 0 else {
            throw ScriptAuditLogError.directoryUnsafe("log directory is missing or unreadable: \(directory.path)")
        }
        guard (info.st_mode & S_IFMT) == S_IFDIR else {
            throw ScriptAuditLogError.directoryUnsafe("log directory is not a real directory: \(directory.path)")
        }
        guard info.st_uid == getuid() else {
            throw ScriptAuditLogError.directoryUnsafe("log directory is not owned by the current user")
        }
        guard (info.st_mode & 0o077) == 0 else {
            throw ScriptAuditLogError.directoryUnsafe("log directory is accessible to group or others")
        }
    }

    /// Opens the live log file and returns a descriptor holding the exclusive lock. The descriptor is only returned
    /// once it is confirmed to still name the file at `path`: a relay that waited on the lock while another relay
    /// rotated the file would otherwise append to the renamed previous generation.
    private func openLockedLogFile(at path: String) throws -> Int32 {
        for _ in 0..<Self.maximumOpenAttempts {
            let descriptor = open(path, O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard descriptor >= 0 else {
                let code = errno
                if code == ELOOP {
                    throw ScriptAuditLogError.fileUnsafe("log file is a symbolic link: \(path)")
                }
                throw ScriptAuditLogError.writeFailed("could not open the log file (errno \(code))")
            }

            var opened = stat()
            guard fstat(descriptor, &opened) == 0,
                  (opened.st_mode & S_IFMT) == S_IFREG,
                  opened.st_uid == getuid(),
                  (opened.st_mode & 0o077) == 0
            else {
                close(descriptor)
                throw ScriptAuditLogError.fileUnsafe("log file is not an owner-only regular file: \(path)")
            }

            var lockResult: Int32
            repeat { lockResult = flock(descriptor, LOCK_EX) } while lockResult != 0 && errno == EINTR
            guard lockResult == 0 else {
                let code = errno
                close(descriptor)
                throw ScriptAuditLogError.writeFailed("could not lock the log file (errno \(code))")
            }

            var live = stat()
            if lstat(path, &live) == 0, live.st_dev == opened.st_dev, live.st_ino == opened.st_ino {
                return descriptor
            }
            flock(descriptor, LOCK_UN)
            close(descriptor)
        }
        throw ScriptAuditLogError.fileUnsafe("log file kept changing while it was being locked: \(path)")
    }

    private static func currentSize(of descriptor: Int32) -> off_t {
        var info = stat()
        return fstat(descriptor, &info) == 0 ? info.st_size : 0
    }

    private static func writeWhole(_ data: Data, to descriptor: Int32) throws {
        var written = -1
        repeat {
            written = data.withUnsafeBytes { buffer in
                write(descriptor, buffer.baseAddress, buffer.count)
            }
        } while written < 0 && errno == EINTR
        guard written == data.count else {
            throw ScriptAuditLogError.writeFailed("wrote \(max(written, 0)) of \(data.count) bytes")
        }
    }
}
