import Foundation
import XCTest
@testable import OpenComputerUseKit

/// The quit marker lets a proxy tell a deliberate menu Quit apart from an agent crash.
final class AppAgentQuitMarkerTests: XCTestCase {

    private func makeSocketPath() throws -> String {
        var template = Array((NSTemporaryDirectory() + "quit-marker-XXXXXX").utf8CString)
        let created = try XCTUnwrap(mkdtemp(&template), "mkdtemp failed")
        let directory = String(cString: created)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: directory) }
        return directory + "/open-computer-use-agent.sock"
    }

    func testPathSitsBesideTheSocket() {
        XCTAssertEqual(
            AppAgentQuitMarker.path(forSocketPath: "/tmp/x/open-computer-use-agent.sock"),
            "/tmp/x/open-computer-use-agent.sock.quit"
        )
    }

    func testMarkerIsAbsentUntilWritten() throws {
        let socketPath = try makeSocketPath()
        XCTAssertFalse(AppAgentQuitMarker.exists(forSocketPath: socketPath))
    }

    func testWriteThenExistsThenClear() throws {
        let socketPath = try makeSocketPath()

        XCTAssertTrue(AppAgentQuitMarker.write(forSocketPath: socketPath))
        XCTAssertTrue(AppAgentQuitMarker.exists(forSocketPath: socketPath))

        AppAgentQuitMarker.clear(forSocketPath: socketPath)
        XCTAssertFalse(AppAgentQuitMarker.exists(forSocketPath: socketPath))
    }

    func testWriteIsIdempotentAndOwnerOnly() throws {
        let socketPath = try makeSocketPath()

        XCTAssertTrue(AppAgentQuitMarker.write(forSocketPath: socketPath))
        XCTAssertTrue(AppAgentQuitMarker.write(forSocketPath: socketPath))

        let attributes = try FileManager.default.attributesOfItem(atPath: AppAgentQuitMarker.path(forSocketPath: socketPath))
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testClearWithoutMarkerIsHarmless() throws {
        let socketPath = try makeSocketPath()
        AppAgentQuitMarker.clear(forSocketPath: socketPath)
        XCTAssertFalse(AppAgentQuitMarker.exists(forSocketPath: socketPath))
    }

    func testWriteFailsWhenTheDirectoryIsMissing() {
        XCTAssertFalse(AppAgentQuitMarker.write(forSocketPath: "/nonexistent-dir-for-quit-marker/agent.sock"))
    }

    func testMarkersAreScopedPerSocket() throws {
        let first = try makeSocketPath()
        let second = try makeSocketPath()

        AppAgentQuitMarker.write(forSocketPath: first)

        XCTAssertTrue(AppAgentQuitMarker.exists(forSocketPath: first))
        XCTAssertFalse(AppAgentQuitMarker.exists(forSocketPath: second))
    }

    func testQuitMessageTellsTheHostToRestartAndIsAToolError() throws {
        let line = #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"click","arguments":{}}}"#
        let text = try XCTUnwrap(AppAgentLossResponse.response(forRequestLine: line, message: AppAgentLossResponse.quitMessage))
        XCTAssertTrue(text.contains("quit from its menu"))
        XCTAssertTrue(text.contains("restart your MCP host"))
        XCTAssertTrue(text.contains("\"isError\":true"))
    }
}
