import Foundation
import XCTest
@testable import OpenComputerUseKit

/// Runs real, harmless system binaries (`ls`, `env`, `cat`, `sleep`, `sh`, `pwd`) through the confined runner. No
/// test starts an app, sends an Apple Event or needs a permission grant.
///
/// Timing bounds: a lower bound proves a floor or a wait; an upper bound only proves "bounded, not hung", so it sits
/// far below the child's natural run time (30 second sleeps) yet leaves seconds of headroom for a loaded CI runner.
final class ConfinedChildProcessRunnerTests: XCTestCase {

    private var descriptorsToClose: [Int32] = []

    override func tearDown() {
        for descriptor in descriptorsToClose {
            close(descriptor)
        }
        descriptorsToClose.removeAll()
        super.tearDown()
    }

    private func run(
        _ path: String,
        _ arguments: [String] = [],
        input: Data = Data(),
        timeout: TimeInterval = 10,
        outputByteLimit: Int = ConfinedChildProcessRunner.defaultOutputByteLimit
    ) throws -> ConfinedChildProcessResult {
        try ConfinedChildProcessRunner.run(
            ConfinedChildProcessRequest(
                executablePath: path,
                arguments: arguments,
                standardInput: input,
                environment: ConfinedChildProcessRunner.scrubbedEnvironment(from: [:]),
                timeout: timeout,
                outputByteLimit: outputByteLimit
            )
        )
    }

    private func text(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }

    func testChildSeesOnlyStandardDescriptors() throws {
        let nullDescriptor = open("/dev/null", O_RDONLY)
        XCTAssertGreaterThanOrEqual(nullDescriptor, 0)
        XCTAssertEqual(dup2(nullDescriptor, 200), 200)
        close(nullDescriptor)
        descriptorsToClose.append(200)

        var pair: [Int32] = [-1, -1]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &pair), 0)
        XCTAssertEqual(pair.count, 2)
        XCTAssertEqual(dup2(pair[0], 201), 201)
        close(pair[0])
        close(pair[1])
        descriptorsToClose.append(201)

        // Low-numbered leak candidates: the lowest free slots from 5 upward. F_DUPFD never clobbers a descriptor the
        // test process already uses, and 3 and 4 are skipped because `ls` opens its own directory handles there.
        var lowDescriptors: [Int32] = []
        for _ in 0..<5 {
            let duplicate = fcntl(200, F_DUPFD, 5)
            XCTAssertGreaterThanOrEqual(duplicate, 5)
            guard duplicate >= 5 else { break }
            lowDescriptors.append(duplicate)
            descriptorsToClose.append(duplicate)
        }
        XCTAssertEqual(lowDescriptors.count, 5)

        // Every stand-in descriptor carries no close-on-exec flag in the parent.
        let parentOnlyDescriptors: [Int32] = [200, 201] + lowDescriptors
        for descriptor in parentOnlyDescriptors {
            XCTAssertEqual(fcntl(descriptor, F_GETFD) & FD_CLOEXEC, 0, "fd \(descriptor) is close-on-exec")
        }

        let result = try run("/bin/ls", ["/dev/fd"])
        XCTAssertEqual(result.exitStatus, 0)
        let descriptors = Set(
            text(result.standardOutput)
                .split(whereSeparator: \.isNewline)
                .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
        )
        XCTAssertTrue(descriptors.isSuperset(of: [0, 1, 2]), "fds seen: \(descriptors.sorted())")
        // None of the inheritable parent descriptors reaches the child. Anything else the child lists (fd 3 and fd 4
        // on current macOS) is a directory handle `ls` opens for itself, so it is not bounded here.
        for descriptor in parentOnlyDescriptors {
            XCTAssertFalse(descriptors.contains(descriptor), "fd \(descriptor) leaked; fds seen: \(descriptors.sorted())")
        }
    }

    func testChildEnvironmentIsScrubbed() throws {
        let scrubbed = ConfinedChildProcessRunner.scrubbedEnvironment(from: [
            "PATH": "/evil",
            "HOME": "/Users/x",
            "LANG": "C",
            "SECRET_TOKEN": "s",
            "OPEN_COMPUTER_USE_ENABLE_SCRIPTING": "1",
            "DYLD_INSERT_LIBRARIES": "/tmp/x",
        ])
        XCTAssertEqual(Set(scrubbed.keys), ["HOME", "LANG", "PATH"])
        XCTAssertEqual(scrubbed["PATH"], ConfinedChildProcessRunner.fixedSearchPath)
        XCTAssertEqual(ConfinedChildProcessRunner.fixedSearchPath, "/usr/bin:/bin:/usr/sbin:/sbin")

        let result = try ConfinedChildProcessRunner.run(
            ConfinedChildProcessRequest(
                executablePath: "/usr/bin/env",
                arguments: [],
                environment: scrubbed,
                timeout: 10
            )
        )
        XCTAssertEqual(result.exitStatus, 0)
        let keys = Set(
            text(result.standardOutput)
                .split(whereSeparator: \.isNewline)
                .compactMap { line in line.split(separator: "=", maxSplits: 1).first.map(String.init) }
        )
        XCTAssertEqual(keys, ["HOME", "LANG", "PATH"])
        XCTAssertTrue(text(result.standardOutput).contains("PATH=/usr/bin:/bin:/usr/sbin:/sbin"))
    }

    func testScrubbedEnvironmentFallsBackForRelativeHomeAndMissingLang() {
        let scrubbed = ConfinedChildProcessRunner.scrubbedEnvironment(from: ["HOME": "relative/home"])
        XCTAssertEqual(scrubbed["LANG"], "en_US.UTF-8")
        XCTAssertEqual(scrubbed["HOME"], NSHomeDirectory())
    }

    func testStandardInputIsDelivered() throws {
        let result = try run("/bin/cat", input: Data("hello\n".utf8))
        XCTAssertEqual(text(result.standardOutput), "hello\n")
        XCTAssertEqual(result.exitStatus, 0)
    }

    func testTimeoutKillsChild() throws {
        let result = try run("/bin/sleep", ["30"], timeout: 0.5)
        XCTAssertTrue(result.timedOut)
        XCTAssertNil(result.exitStatus)
        XCTAssertNotNil(result.terminatingSignal)
        XCTAssertLessThan(result.duration, 10.0)
    }

    func testTermIgnoringChildIsKilled() throws {
        let result = try run("/bin/sh", ["-c", "trap \"\" TERM; sleep 30"], timeout: 0.5)
        XCTAssertTrue(result.timedOut)
        XCTAssertLessThan(result.duration, 10.0)
    }

    func testOutputBeyondCapDoesNotDeadlock() throws {
        let script = "head -c 300000 /dev/zero | tr '\\0' x; head -c 300000 /dev/zero | tr '\\0' y >&2"
        let result = try run("/bin/sh", ["-c", script], timeout: 10)
        XCTAssertFalse(result.timedOut)
        XCTAssertEqual(result.standardOutput.count, 65_536)
        XCTAssertEqual(result.standardError.count, 65_536)
        XCTAssertTrue(result.standardOutputTruncated)
        XCTAssertTrue(result.standardErrorTruncated)
    }

    func testRelativeExecutablePathIsRejected() {
        XCTAssertThrowsError(try run("osascript")) { error in
            XCTAssertEqual(error as? ConfinedChildProcessError, .executablePathNotAbsolute("osascript"))
        }
    }

    func testExitStatusIsReported() throws {
        let result = try run("/bin/sh", ["-c", "exit 3"])
        XCTAssertEqual(result.exitStatus, 3)
        XCTAssertFalse(result.timedOut)
    }

    func testLingeringDescendantDoesNotWedgeRunner() throws {
        let result = try run("/bin/sh", ["-c", "sleep 30 & echo hi; exit 0"], timeout: 20)
        XCTAssertLessThan(result.duration, 10.0)
        XCTAssertFalse(result.timedOut)
        XCTAssertEqual(result.exitStatus, 0)
        XCTAssertTrue(text(result.standardOutput).hasPrefix("hi"))
    }

    func testBackgroundedDescendantWithShortTimeoutReturnsPromptly() throws {
        let result = try run("/bin/sh", ["-c", "sleep 30 & sleep 30"], timeout: 2)
        XCTAssertTrue(result.timedOut)
        XCTAssertLessThan(result.duration, 10.0 + ConfinedChildProcessRunner.killGracePeriod)
    }

    func testChildWorkingDirectoryIsRoot() throws {
        let result = try run("/bin/pwd")
        XCTAssertEqual(text(result.standardOutput), "/\n")
    }
}

/// Runs the real `/usr/bin/osascript` with scripts that never message another app, so no Apple Event leaves this
/// process and no Automation grant is needed.
final class OsascriptChildRunnerTests: XCTestCase {

    private let runner = OsascriptChildRunner()

    func testArgumentsReadSourceFromStandardInput() {
        XCTAssertEqual(OsascriptChildRunner.arguments(for: .applescript), ["-l", "AppleScript", "-"])
        XCTAssertEqual(OsascriptChildRunner.arguments(for: .javascript), ["-l", "JavaScript", "-"])
    }

    func testAppleScriptReturnsResult() throws {
        let outcome = try runner.run(source: "return 1 + 1", language: .applescript, timeout: 20)
        XCTAssertEqual(outcome.resultText, "2")
        XCTAssertNil(outcome.errorNumber)
    }

    func testJavaScriptReturnsResult() throws {
        let outcome = try runner.run(source: "1 + 1", language: .javascript, timeout: 20)
        XCTAssertEqual(outcome.resultText, "2")
    }

    func testScriptErrorNumberIsParsed() throws {
        let outcome = try runner.run(source: "error \"boom\" number -1743", language: .applescript, timeout: 20)
        XCTAssertEqual(outcome.errorNumber, -1743)
        XCTAssertFalse(outcome.timedOut)
    }

    func testParseErrorNumberTable() {
        XCTAssertEqual(
            OsascriptChildRunner.parseErrorNumber(
                fromStandardError: "1:5: execution error: Not authorized to send Apple events to Mail. (-1743)"
            ),
            -1743
        )
        XCTAssertNil(OsascriptChildRunner.parseErrorNumber(fromStandardError: "no number here"))
    }

    func testEffectiveTimeoutTable() {
        XCTAssertEqual(OsascriptChildRunner.effectiveTimeout(requested: nil, isFirstContactWithTarget: false), 20)
        XCTAssertEqual(OsascriptChildRunner.effectiveTimeout(requested: 5, isFirstContactWithTarget: false), 5)
        XCTAssertEqual(OsascriptChildRunner.effectiveTimeout(requested: 90, isFirstContactWithTarget: false), 60)
        XCTAssertEqual(OsascriptChildRunner.effectiveTimeout(requested: 5, isFirstContactWithTarget: true), 30)
        XCTAssertEqual(OsascriptChildRunner.effectiveTimeout(requested: 45, isFirstContactWithTarget: true), 45)
        XCTAssertEqual(OsascriptChildRunner.effectiveTimeout(requested: 0, isFirstContactWithTarget: false), 20)
        XCTAssertEqual(
            OsascriptChildRunner.effectiveTimeout(requested: 1, isFirstContactWithTarget: true, firstContactFloor: 3),
            3
        )
        XCTAssertEqual(
            OsascriptChildRunner.effectiveTimeout(requested: 1, isFirstContactWithTarget: false, firstContactFloor: 3),
            1
        )
    }

    func testDecodeOutputSurvivesSplitMultibyteCharacter() {
        // 0xC3 is the first byte of a two-byte character that the byte cap cut in half.
        let data = Data(repeating: 0x78, count: 65_535) + Data([0xC3])
        let decoded = OsascriptChildRunner.decodeOutput(data)
        XCTAssertFalse(decoded.isEmpty)
        XCTAssertTrue(decoded.hasPrefix(String(repeating: "x", count: 65_535)))
    }

    func testDelayScriptTimesOut() throws {
        let outcome = try runner.run(source: "delay 30", language: .applescript, timeout: 1)
        XCTAssertTrue(outcome.timedOut)
        XCTAssertLessThan(outcome.durationMilliseconds, 12_000)
    }

    func testOversizedSourceIsRejected() {
        let source = String(repeating: "x", count: 65_537)
        XCTAssertThrowsError(try runner.run(source: source, language: .applescript, timeout: 5)) { error in
            XCTAssertEqual(error as? OsascriptChildRunnerError, .sourceTooLarge(byteCount: 65_537))
        }
    }

    func testUserFacingMessageForAutomationDenied() throws {
        let message = try XCTUnwrap(OsascriptChildRunner.userFacingMessage(errorNumber: -1743, app: "Mail"))
        XCTAssertTrue(message.contains("Automation"))
        XCTAssertTrue(message.contains("System Settings"))
        XCTAssertTrue(message.contains("Mail"))
    }
}
