import Darwin
import Foundation
import XCTest
@testable import OpenComputerUseKit

/// The proxy and the agent exchange newline-terminated lines over a socket. A message cut short by a dying peer must read
/// as a lost connection, never as a complete request, and a write to a dead peer must report failure.
final class AppAgentLineIOTests: XCTestCase {

    /// Two connected stream endpoints wrapped as `FILE`s, with SIGPIPE off so a write to a closed peer returns an error.
    private func makePair() throws -> (a: UnsafeMutablePointer<FILE>, b: UnsafeMutablePointer<FILE>) {
        var fds: [Int32] = [0, 0]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds), 0)
        for fd in fds {
            var noSigPipe: Int32 = 1
            _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        }
        let a = try XCTUnwrap(fdopen(fds[0], "r+"))
        let b = try XCTUnwrap(fdopen(fds[1], "r+"))
        return (a, b)
    }

    func testWrittenLineReadsBackWithoutTheNewline() throws {
        let (a, b) = try makePair()
        defer { fclose(a); fclose(b) }

        XCTAssertTrue(writeAppAgentLine(#"{"kind":"agentInfo"}"#, to: a))
        XCTAssertEqual(readAppAgentLine(b), #"{"kind":"agentInfo"}"#)
    }

    func testUnterminatedLineAtEndOfStreamReadsAsNil() throws {
        let (a, b) = try makePair()
        defer { fclose(b) }

        fputs(#"{"response":"cut sho"#, a)
        fflush(a)
        fclose(a)

        XCTAssertNil(readAppAgentLine(b), "a partial line is not a complete message")
    }

    func testCompleteLineBeforeEndOfStreamIsStillDelivered() throws {
        let (a, b) = try makePair()
        defer { fclose(b) }

        XCTAssertTrue(writeAppAgentLine("first", to: a))
        fputs("second-without-newline", a)
        fflush(a)
        fclose(a)

        XCTAssertEqual(readAppAgentLine(b), "first")
        XCTAssertNil(readAppAgentLine(b))
    }

    func testWriteToClosedPeerReportsFailure() throws {
        let (a, b) = try makePair()
        defer { fclose(a) }
        fclose(b)

        XCTAssertFalse(writeAppAgentLine(#"{"kind":"mcp"}"#, to: a))
    }

    func testNotificationExpectsNoReplyAndRequestDoes() {
        XCTAssertFalse(AppAgentLossResponse.expectsReply(requestLine: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#))
        XCTAssertFalse(AppAgentLossResponse.expectsReply(requestLine: #"{"jsonrpc":"2.0","id":null,"method":"ping"}"#))
        XCTAssertFalse(AppAgentLossResponse.expectsReply(requestLine: "not json"))
        XCTAssertTrue(AppAgentLossResponse.expectsReply(requestLine: #"{"jsonrpc":"2.0","id":3,"method":"ping"}"#))
    }

    func testNotDeliveredMessageSaysTheCallDidNotRun() throws {
        let line = #"{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"click","arguments":{}}}"#
        let text = try XCTUnwrap(AppAgentLossResponse.response(forRequestLine: line, message: AppAgentLossResponse.notDeliveredMessage))

        XCTAssertTrue(text.contains("NOT sent"))
        XCTAssertFalse(text.contains("may or may not"))
    }
}
