import Darwin
import Foundation

// Confirms, before any goal or screen text leaves this process, that the loopback listener on the configured port is
// the llama-server that scripts/decision-model/start-sidecar.sh started and recorded.
//
// Why: the sidecar has no authentication and its port is predictable (39000 + uid % 1000). Whatever process holds
// 127.0.0.1:<port> while the sidecar is down would otherwise receive the goal and up to 52 accessibility rows read by
// this TCC-privileged process. A sandboxed same-uid app with only the network-server entitlement is enough to hold
// the port, and it has no other way to read another app's accessibility tree. A bearer key would not close this: the
// client would still hand the key and the body to the squatter. Instead, the pid file that start-sidecar.sh writes
// under ~/Library/Application Support (outside every sandbox container) names the pid and the resolved llama-server
// binary, and the kernel is asked whether that pid runs that binary and holds the 127.0.0.1:<port> listening socket.
// llama-server binds that exact address without SO_REUSEPORT, so while the verified socket exists no other socket can
// accept connections for it.
//
// Residual: a non-sandboxed same-uid process can rewrite the pid file and run its own binary named llama-server. Such
// a process already has the user's full file access and is outside this check's threat model.

/// The fields of start-sidecar.sh's pid file that the verifier relies on. The file holds `key=value` lines.
public struct DecisionSidecarRecord: Equatable, Sendable {
    public let pid: pid_t
    public let port: Int
    public let binaryPath: String

    /// nil unless `pid`, `port` and an absolute `binary` are all present and well formed. Unknown keys are ignored.
    public static func parse(_ text: String) -> DecisionSidecarRecord? {
        var fields: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let separator = line.firstIndex(of: "=") else { continue }
            fields[String(line[..<separator])] = String(line[line.index(after: separator)...])
        }
        guard let pid = fields["pid"].flatMap({ Int32($0) }), pid > 1,
              let port = fields["port"].flatMap({ Int($0) }), (1...65_535).contains(port),
              let binaryPath = fields["binary"], binaryPath.hasPrefix("/")
        else { return nil }
        return DecisionSidecarRecord(pid: pid, port: port, binaryPath: binaryPath)
    }
}

public struct DecisionSidecarVerifier: Sendable {
    /// Where start-sidecar.sh records the sidecar it started.
    public static var defaultPidFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/OpenComputerUse/decision-model/run/llama-server.pid")
    }

    public let pidFileURL: URL
    /// Required last path component of the recorded binary. Tests substitute their own executable's name.
    public let executableName: String

    public init(pidFileURL: URL = DecisionSidecarVerifier.defaultPidFileURL, executableName: String = "llama-server") {
        self.pidFileURL = pidFileURL
        self.executableName = executableName
    }

    /// Throws `DecisionModelError.unverifiedSidecar` unless the recorded pid is alive, runs the recorded binary, and
    /// holds the IPv4 loopback listening socket on `port`. Performs no network I/O.
    public func verify(port: Int) throws {
        let record = try loadRecord()
        guard record.port == port else {
            throw DecisionModelError.unverifiedSidecar("the pid file records port \(record.port), the URL names port \(port)")
        }
        guard (record.binaryPath as NSString).lastPathComponent == executableName else {
            throw DecisionModelError.unverifiedSidecar("the recorded binary is not \(executableName)")
        }
        guard kill(record.pid, 0) == 0 else {
            throw DecisionModelError.unverifiedSidecar("recorded pid \(record.pid) is not running")
        }
        guard let running = Self.executablePath(of: record.pid),
              let recorded = Self.canonicalPath(record.binaryPath), running == recorded
        else {
            throw DecisionModelError.unverifiedSidecar("recorded pid \(record.pid) is not running the recorded binary")
        }
        guard Self.holdsIPv4LoopbackListener(pid: record.pid, port: port) else {
            throw DecisionModelError.unverifiedSidecar(
                "recorded pid \(record.pid) does not hold the listening socket on 127.0.0.1:\(port)"
            )
        }
    }

    /// Reads the pid file, refusing anything but a regular file owned by this user and not writable by others.
    private func loadRecord() throws -> DecisionSidecarRecord {
        var status = stat()
        guard lstat(pidFileURL.path, &status) == 0 else {
            throw DecisionModelError.unverifiedSidecar("no pid file at \(pidFileURL.path)")
        }
        guard status.st_mode & S_IFMT == S_IFREG, status.st_uid == getuid(),
              status.st_mode & (S_IWGRP | S_IWOTH) == 0
        else {
            throw DecisionModelError.unverifiedSidecar("the pid file is not a private regular file owned by this user")
        }
        guard let text = try? String(contentsOf: pidFileURL, encoding: .utf8),
              let record = DecisionSidecarRecord.parse(text)
        else {
            throw DecisionModelError.unverifiedSidecar("the pid file is unreadable or in an old format; restart the sidecar")
        }
        return record
    }

    /// The kernel's record of the executable the process runs; unlike argv[0], the process cannot rename it.
    static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(4 * MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return canonicalPath(String(cString: buffer))
    }

    /// realpath(3), so `/opt/homebrew/bin` symlinks and `/var` → `/private/var` compare equal. Foundation's
    /// `resolvingSymlinksInPath` is avoided because it strips a leading `/private`.
    static func canonicalPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// True when `pid` has a TCP socket in LISTEN state bound to exactly 127.0.0.1:`port`.
    static func holdsIPv4LoopbackListener(pid: pid_t, port: Int) -> Bool {
        let stride = MemoryLayout<proc_fdinfo>.stride
        let needed = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard needed > 0 else { return false }
        // Headroom for descriptors opened between the size query and the listing.
        var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(needed) / stride + 32)
        let filled = descriptors.withUnsafeMutableBytes { buffer in
            proc_pidinfo(pid, PROC_PIDLISTFDS, 0, buffer.baseAddress, Int32(buffer.count))
        }
        guard filled > 0 else { return false }

        let loopback = UInt32(0x7F00_0001)
        for descriptor in descriptors.prefix(Int(filled) / stride)
        where descriptor.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
            var info = socket_fdinfo()
            let size = Int32(MemoryLayout<socket_fdinfo>.size)
            guard proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDSOCKETINFO, &info, size) == size,
                  info.psi.soi_kind == SOCKINFO_TCP
            else { continue }
            let tcp = info.psi.soi_proto.pri_tcp
            let local = tcp.tcpsi_ini
            guard tcp.tcpsi_state == TSI_S_LISTEN, local.insi_vflag & UInt8(INI_IPV4) != 0 else { continue }
            let localPort = Int(UInt16(bigEndian: UInt16(truncatingIfNeeded: local.insi_lport)))
            let localAddress = UInt32(bigEndian: local.insi_laddr.ina_46.i46a_addr4.s_addr)
            if localPort == port, localAddress == loopback { return true }
        }
        return false
    }
}
