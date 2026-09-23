import Darwin
import Foundation
import XCTest
@testable import OpenComputerUseKit

/// The verifier must accept only the recorded pid, running the recorded binary, holding 127.0.0.1:<port>. The test
/// process stands in for llama-server: it opens its own listening sockets and records its own pid and executable, so
/// no other process is ever inspected or signalled.
final class DecisionSidecarVerifierTests: XCTestCase {
    private var directory: URL!
    private var pidFile: URL!
    private var sockets: [Int32] = []

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocu-sidecar-verifier-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        pidFile = directory.appendingPathComponent("llama-server.pid")
    }

    override func tearDownWithError() throws {
        for socket in sockets { close(socket) }
        try? FileManager.default.removeItem(at: directory)
    }

    private var ownExecutable: String {
        get throws { try XCTUnwrap(DecisionSidecarVerifier.executablePath(of: getpid())) }
    }

    private func verifier() throws -> DecisionSidecarVerifier {
        DecisionSidecarVerifier(pidFileURL: pidFile, executableName: (try ownExecutable as NSString).lastPathComponent)
    }

    /// Opens a TCP listening socket in this process on `address`:0 and returns the kernel-assigned port. Only
    /// loopback addresses are used, so the test never opens a port reachable from another host.
    private func listen(on address: String = "127.0.0.1") throws -> Int {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(fd, 0)
        sockets.append(fd)
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr(address)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        XCTAssertEqual(bound, 0, "bind failed: errno \(errno)")
        XCTAssertEqual(Darwin.listen(fd, 1), 0)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        XCTAssertEqual(named, 0)
        return Int(UInt16(bigEndian: addr.sin_port))
    }

    private func writePidFile(pid: pid_t = getpid(), port: Int, binary: String? = nil, mode: Int = 0o600) throws {
        let text = "pid=\(pid)\nport=\(port)\nlstart=Wed 23 Sep 12:00:00 2026\nbinary=\(try binary ?? ownExecutable)\nmodel=qwen3.5-4b-q4km\n"
        try text.write(to: pidFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: pidFile.path)
    }

    private func assertUnverified(port: Int, _ fragment: String, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertThrowsError(try verifier().verify(port: port), file: file, line: line) { error in
            guard case let .unverifiedSidecar(reason) = error as? DecisionModelError else {
                return XCTFail("expected .unverifiedSidecar, got \(error)", file: file, line: line)
            }
            XCTAssertTrue(reason.contains(fragment), "\(reason) should mention \(fragment)", file: file, line: line)
        }
    }

    // MARK: - Record parsing

    func testRecordParsesKeyValueLinesAndIgnoresUnknownKeys() {
        let record = DecisionSidecarRecord.parse(
            "pid=4242\nport=39501\nlstart=Wed 23 Sep 12:00:00 2026\nbinary=/opt/homebrew/bin/llama-server\nextra=1\n"
        )
        XCTAssertEqual(record, DecisionSidecarRecord(pid: 4242, port: 39501, binaryPath: "/opt/homebrew/bin/llama-server"))
    }

    func testRecordRejectsTheOldBarePidFormatAndMalformedFields() {
        for text in [
            "4242\n",
            "pid=4242\nport=39501\n",
            "pid=4242\nport=39501\nbinary=llama-server\n",
            "pid=1\nport=39501\nbinary=/x/llama-server\n",
            "pid=abc\nport=39501\nbinary=/x/llama-server\n",
            "pid=4242\nport=70000\nbinary=/x/llama-server\n",
        ] {
            XCTAssertNil(DecisionSidecarRecord.parse(text), text)
        }
    }

    // MARK: - verify

    func testVerifyAcceptsTheRecordedPidRunningTheRecordedBinaryOnItsLoopbackListener() throws {
        let port = try listen()
        try writePidFile(port: port)
        XCTAssertNoThrow(try verifier().verify(port: port))
    }

    func testVerifyRejectsWhenThereIsNoPidFile() throws {
        try assertUnverified(port: try listen(), "no pid file")
    }

    func testVerifyRejectsAPortOtherThanTheRecordedOne() throws {
        let port = try listen()
        try writePidFile(port: port)
        try assertUnverified(port: port == 65_535 ? port - 1 : port + 1, "records port")
    }

    func testVerifyRejectsWhenTheRecordedPidDoesNotHoldTheListener() throws {
        // Something listens on the port, but the pid file names a process that holds no socket there.
        let port = try listen()
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        helper.arguments = ["5"]
        try helper.run()
        defer { helper.terminate() }
        try writePidFile(pid: helper.processIdentifier, port: port, binary: "/bin/sleep")
        let verifier = DecisionSidecarVerifier(pidFileURL: pidFile, executableName: "sleep")
        XCTAssertThrowsError(try verifier.verify(port: port)) { error in
            guard case let .unverifiedSidecar(reason) = error as? DecisionModelError else {
                return XCTFail("expected .unverifiedSidecar, got \(error)")
            }
            XCTAssertTrue(reason.contains("does not hold the listening socket"), reason)
        }
    }

    /// start-sidecar.sh binds 127.0.0.1; a socket on the IPv6 loopback with the same port number is someone else's.
    func testVerifyRejectsAnIPv6LoopbackListenerOnTheRecordedPort() throws {
        let fd = Darwin.socket(AF_INET6, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(fd, 0)
        sockets.append(fd)
        var addr = sockaddr_in6()
        addr.sin6_family = sa_family_t(AF_INET6)
        addr.sin6_addr = in6addr_loopback
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in6>.size)) }
        }
        XCTAssertEqual(bound, 0, "bind failed: errno \(errno)")
        XCTAssertEqual(Darwin.listen(fd, 1), 0)
        var length = socklen_t(MemoryLayout<sockaddr_in6>.size)
        let named = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        XCTAssertEqual(named, 0)
        let port = Int(UInt16(bigEndian: addr.sin6_port))

        try writePidFile(port: port)
        try assertUnverified(port: port, "does not hold the listening socket")
    }

    func testVerifyRejectsWhenThePidRunsADifferentBinaryWithTheSameName() throws {
        let port = try listen()
        let impostor = directory.appendingPathComponent((try ownExecutable as NSString).lastPathComponent)
        try Data().write(to: impostor)
        try writePidFile(port: port, binary: impostor.path)
        try assertUnverified(port: port, "not running the recorded binary")
    }

    func testVerifyRejectsARecordedBinaryThatIsNotNamedLlamaServer() throws {
        let port = try listen()
        try writePidFile(port: port)
        let production = DecisionSidecarVerifier(pidFileURL: pidFile)
        XCTAssertThrowsError(try production.verify(port: port)) { error in
            guard case let .unverifiedSidecar(reason) = error as? DecisionModelError else {
                return XCTFail("expected .unverifiedSidecar, got \(error)")
            }
            XCTAssertTrue(reason.contains("not llama-server"), reason)
        }
    }

    func testVerifyRejectsARecordedPidThatIsNotRunning() throws {
        let port = try listen()
        let finished = Process()
        finished.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try finished.run()
        finished.waitUntilExit()
        try writePidFile(pid: finished.processIdentifier, port: port)
        try assertUnverified(port: port, "is not running")
    }

    func testVerifyRejectsAPidFileOthersCanWrite() throws {
        let port = try listen()
        try writePidFile(port: port, mode: 0o666)
        try assertUnverified(port: port, "not a private regular file")
    }

    func testVerifyRejectsTheOldBarePidFormat() throws {
        let port = try listen()
        try "\(getpid())\n".write(to: pidFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: pidFile.path)
        try assertUnverified(port: port, "old format")
    }
}
