import Foundation
import XCTest
@testable import OpenComputerUseKit

/// Every test writes only inside its own temporary directory, removed in `tearDown`; none touches the real
/// application-support log directory and none sends an Apple Event.
final class ScriptAuditLogTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("script-audit-log-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    override func tearDownWithError() throws {
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
        root = nil
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private var logDirectory: URL { root.appendingPathComponent("logs", isDirectory: true) }
    private var logFile: URL { logDirectory.appendingPathComponent("scripts.log") }
    private var rotatedFile: URL { logDirectory.appendingPathComponent("scripts.log.1") }

    /// Thread-safe capture for the standard-error writer.
    private final class Capture: @unchecked Sendable {
        private let lock = NSLock()
        private var chunks: [String] = []
        func append(_ text: String) {
            lock.lock()
            chunks.append(text)
            lock.unlock()
        }
        var all: [String] {
            lock.lock()
            defer { lock.unlock() }
            return chunks
        }
    }

    private func makeLog(
        maximumFileBytes: Int = ScriptAuditLog.defaultMaximumFileBytes,
        capture: Capture? = nil
    ) -> ScriptAuditLog {
        ScriptAuditLog(
            directory: logDirectory,
            maximumFileBytes: maximumFileBytes,
            standardErrorWriter: { text in capture?.append(text) }
        )
    }

    private func requestEntry(payload: String, targetApp: String? = "Mail") -> ScriptAuditEntry {
        ScriptAuditEntry(
            kind: .runScript,
            phase: .request,
            targetApp: targetApp,
            payload: payload,
            payloadSHA256: ScriptAuditLog.sha256Hex(payload)
        )
    }

    /// Deliberately tiny so a few of them stay well under a small rotation threshold.
    private func compactEntry() -> ScriptAuditEntry {
        ScriptAuditEntry(
            kind: .runScript,
            phase: .result,
            timestamp: Date(timeIntervalSince1970: 0),
            relayPID: 1,
            parentPID: 1,
            targetApp: nil,
            payload: nil,
            payloadSHA256: "0"
        )
    }

    private func createLogDirectory() throws {
        try FileManager.default.createDirectory(
            at: logDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        XCTAssertEqual(chmod(logDirectory.path, 0o700), 0)
    }

    private func mode(of url: URL) throws -> mode_t {
        var info = stat()
        XCTAssertEqual(lstat(url.path, &info), 0, "lstat failed for \(url.path)")
        return info.st_mode & 0o777
    }

    private func lines(of url: URL) throws -> [String] {
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    private func parseJSONObject(_ line: String) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: Data(line.utf8))
        return try XCTUnwrap(object as? [String: Any], "line is not a JSON object: \(line)")
    }

    private func assertFileUnsafe(_ body: () throws -> Void, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            guard case .fileUnsafe? = error as? ScriptAuditLogError else {
                XCTFail("expected .fileUnsafe, got \(error)", file: file, line: line)
                return
            }
        }
    }

    // MARK: - File safety

    func testLogFileIsOwnerOnly() throws {
        try makeLog().record(requestEntry(payload: "tell application \"Mail\" to count messages"))

        XCTAssertEqual(try mode(of: logFile), 0o600)
        XCTAssertEqual(try mode(of: logDirectory), 0o700)
    }

    func testSymlinkedLogFileIsRefused() throws {
        try createLogDirectory()
        let victim = root.appendingPathComponent("victim.txt")
        try "original".write(to: victim, atomically: true, encoding: .utf8)
        XCTAssertEqual(symlink(victim.path, logFile.path), 0)

        let capture = Capture()
        assertFileUnsafe {
            try makeLog(capture: capture).record(requestEntry(payload: "return 1"))
        }

        XCTAssertEqual(try String(contentsOf: victim, encoding: .utf8), "original")
        XCTAssertTrue(capture.all.isEmpty, "standard error must stay silent when the file write is refused")
    }

    func testWidePermissionLogIsRefused() throws {
        try createLogDirectory()
        XCTAssertTrue(FileManager.default.createFile(atPath: logFile.path, contents: Data()))
        XCTAssertEqual(chmod(logFile.path, 0o644), 0)

        let capture = Capture()
        assertFileUnsafe {
            try makeLog(capture: capture).record(requestEntry(payload: "return 1"))
        }
        XCTAssertTrue(capture.all.isEmpty)
    }

    func testSymlinkedDirectoryIsRefused() throws {
        let realDirectory = root.appendingPathComponent("real-logs", isDirectory: true)
        try FileManager.default.createDirectory(
            at: realDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        XCTAssertEqual(symlink(realDirectory.path, logDirectory.path), 0)

        XCTAssertThrowsError(try makeLog().record(requestEntry(payload: "return 1"))) { error in
            guard case .directoryUnsafe? = error as? ScriptAuditLogError else {
                XCTFail("expected .directoryUnsafe, got \(error)")
                return
            }
        }
        let leaked = try FileManager.default.contentsOfDirectory(atPath: realDirectory.path)
        XCTAssertTrue(leaked.isEmpty, "nothing may be written through a symlinked directory: \(leaked)")
    }

    // MARK: - Format and stderr hygiene

    func testEntryIsOneJSONLineWithFullPayload() throws {
        let script = "tell application \"Mail\"\n  return (count of messages of inbox)\nend tell"
        try makeLog().record(requestEntry(payload: script))

        let written = try lines(of: logFile)
        XCTAssertEqual(written.count, 1)
        let first = try XCTUnwrap(written.first)
        let object = try parseJSONObject(first)
        XCTAssertEqual(object["payload"] as? String, script)
        XCTAssertEqual(object["payload_sha256"] as? String, ScriptAuditLog.sha256Hex(script))
        XCTAssertEqual(object["kind"] as? String, "run_script")
        XCTAssertEqual(object["phase"] as? String, "request")
        XCTAssertEqual(object["target_app"] as? String, "Mail")
        XCTAssertNotNil(object["timestamp"] as? String)
        XCTAssertNotNil(object["relay_pid"])
        XCTAssertNotNil(object["parent_pid"])
    }

    func testSha256HexMatchesKnownVector() {
        XCTAssertEqual(
            ScriptAuditLog.sha256Hex("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func testStandardErrorCarriesMetadataOnly() throws {
        let marker = "SECRET-MARKER-\(UUID().uuidString)"
        let script = "return \"\(marker)\""
        let capture = Capture()
        try makeLog(capture: capture).record(requestEntry(payload: script))

        let joined = capture.all.joined()
        XCTAssertFalse(capture.all.isEmpty, "the writer must receive a metadata line")
        XCTAssertTrue(joined.contains(String(ScriptAuditLog.sha256Hex(script).prefix(16))))
        XCTAssertTrue(joined.contains("run_script"))
        XCTAssertFalse(joined.contains(marker), "payload text must never reach standard error")
    }

    func testResultEntryOmitsPayload() throws {
        let entry = ScriptAuditEntry(
            kind: .runScript,
            phase: .result,
            targetApp: "Mail",
            payload: nil,
            payloadSHA256: ScriptAuditLog.sha256Hex("return 1"),
            exitStatus: 0,
            durationMilliseconds: 42,
            outcome: "ok"
        )
        try makeLog().record(entry)

        let first = try XCTUnwrap(try lines(of: logFile).first)
        let object = try parseJSONObject(first)
        XCTAssertNil(object["payload"])
        XCTAssertEqual(object["phase"] as? String, "result")
        XCTAssertEqual((object["exit_status"] as? NSNumber)?.intValue, 0)
        XCTAssertEqual((object["duration_ms"] as? NSNumber)?.intValue, 42)
        XCTAssertEqual(object["outcome"] as? String, "ok")
    }

    func testMetadataLineEscapesControlCharacters() {
        let entry = ScriptAuditEntry(
            kind: .runScript,
            phase: .result,
            targetApp: "Mail\n[open-computer-use] run_script result",
            payload: nil,
            payloadSHA256: ScriptAuditLog.sha256Hex("return 1"),
            exitStatus: 0,
            durationMilliseconds: 1,
            outcome: "x\ry"
        )
        let line = ScriptAuditLog.metadataLine(for: entry)

        XCTAssertEqual(line.filter { $0 == "\n" }.count, 1, "only the terminator may be a newline: \(line.debugDescription)")
        XCTAssertTrue(line.hasSuffix("\n"))
        XCTAssertFalse(line.contains("\r"))
        XCTAssertFalse(line.unicodeScalars.contains { $0.value == 0x2028 || $0.value == 0x2029 })
    }

    func testMetadataLineEscapesC1ControlsAndBidiOverrides() {
        let hostile: [UInt32] = [0x80, 0x85, 0x9B, 0x9F, 0x202A, 0x202E, 0x2066, 0x2069]
        var app = "Mail"
        for value in hostile {
            app.unicodeScalars.append(Unicode.Scalar(value)!)
        }
        let entry = ScriptAuditEntry(
            kind: .runScript,
            phase: .result,
            targetApp: app,
            payload: nil,
            payloadSHA256: ScriptAuditLog.sha256Hex("return 1"),
            exitStatus: 0,
            durationMilliseconds: 1,
            outcome: "ok\u{0085}\u{202E}"
        )
        let line = ScriptAuditLog.metadataLine(for: entry)

        for value in hostile {
            XCTAssertFalse(line.unicodeScalars.contains { $0.value == value }, "raw U+\(String(value, radix: 16)) leaked")
        }
        XCTAssertTrue(line.contains("app=Mail\\u{0080}\\u{0085}\\u{009B}\\u{009F}\\u{202A}\\u{202E}\\u{2066}\\u{2069}"), line)
        XCTAssertTrue(line.contains("outcome=ok\\u{0085}\\u{202E}"), line)
    }

    func testMetadataLineCapsAgentInfluencedValues() {
        let entry = ScriptAuditEntry(
            kind: .runScript,
            phase: .result,
            targetApp: String(repeating: "A", count: 1_000),
            payload: nil,
            payloadSHA256: ScriptAuditLog.sha256Hex("return 1"),
            outcome: String(repeating: "B", count: 1_000)
        )
        let line = ScriptAuditLog.metadataLine(for: entry)

        XCTAssertFalse(line.contains(String(repeating: "A", count: 129)))
        XCTAssertFalse(line.contains(String(repeating: "B", count: 129)))
        XCTAssertLessThan(line.count, 600)
    }

    // MARK: - Rotation and concurrency

    func testRotationKeepsOnePreviousGeneration() throws {
        try createLogDirectory()
        let filler = Data(repeating: UInt8(ascii: "x"), count: 2_048)
        XCTAssertTrue(FileManager.default.createFile(atPath: logFile.path, contents: filler))
        XCTAssertEqual(chmod(logFile.path, 0o600), 0)

        try makeLog(maximumFileBytes: 1_024).record(requestEntry(payload: "return 1"))

        XCTAssertEqual(try Data(contentsOf: rotatedFile), filler)
        XCTAssertEqual(try lines(of: logFile).count, 1)
    }

    func testConcurrentWritersNeverInterleave() throws {
        let threadCount = 8
        let entriesPerThread = 50
        let group = DispatchGroup()
        let failures = Capture()

        for thread in 0..<threadCount {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                let log = ScriptAuditLog(
                    directory: self.logDirectory,
                    maximumFileBytes: ScriptAuditLog.defaultMaximumFileBytes,
                    standardErrorWriter: { _ in }
                )
                for index in 0..<entriesPerThread {
                    let payload = "thread \(thread) entry \(index) " + String(repeating: "p", count: 200)
                    do {
                        try log.record(self.requestEntry(payload: payload))
                    } catch {
                        failures.append("\(error)")
                    }
                }
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 60), .success)
        XCTAssertEqual(failures.all, [])

        let written = try lines(of: logFile)
        XCTAssertEqual(written.count, threadCount * entriesPerThread)
        for line in written {
            XCTAssertNoThrow(try parseJSONObject(line), "line is not valid JSON: \(line.prefix(120))")
        }
    }

    func testConcurrentRotationKeepsPreviousGeneration() throws {
        try createLogDirectory()
        let marker = "PREVIOUS-GENERATION-MARKER"
        var filler = Data(marker.utf8)
        filler.append(Data(repeating: UInt8(ascii: "x"), count: 2_048 - filler.count))
        XCTAssertTrue(FileManager.default.createFile(atPath: logFile.path, contents: filler))
        XCTAssertEqual(chmod(logFile.path, 0o600), 0)

        // Each compact entry is well under 150 bytes, so seven of them stay below the 1024-byte threshold and
        // only the first writer to see the oversized file rotates it; the other seven must notice the rotation
        // instead of rotating again over the previous generation.
        let writers = 8
        let ready = DispatchGroup()
        let done = DispatchGroup()
        let start = DispatchSemaphore(value: 0)
        let failures = Capture()

        for _ in 0..<writers {
            ready.enter()
            done.enter()
            DispatchQueue.global().async {
                let log = ScriptAuditLog(
                    directory: self.logDirectory,
                    maximumFileBytes: 1_024,
                    standardErrorWriter: { _ in }
                )
                ready.leave()
                start.wait()
                defer { done.leave() }
                do {
                    try log.record(self.compactEntry())
                } catch {
                    failures.append("\(error)")
                }
            }
        }
        XCTAssertEqual(ready.wait(timeout: .now() + 30), .success)
        for _ in 0..<writers { start.signal() }
        XCTAssertEqual(done.wait(timeout: .now() + 60), .success)
        XCTAssertEqual(failures.all, [])

        let rotated = try String(contentsOf: rotatedFile, encoding: .utf8)
        XCTAssertTrue(rotated.contains(marker), "the previous generation was overwritten by a second rotation")
        let written = try lines(of: logFile)
        XCTAssertEqual(written.count, writers)
        for line in written {
            XCTAssertNoThrow(try parseJSONObject(line), "line is not valid JSON: \(line.prefix(120))")
        }
    }
}
