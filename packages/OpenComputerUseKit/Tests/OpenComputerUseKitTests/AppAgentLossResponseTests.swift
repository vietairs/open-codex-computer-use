import Foundation
import XCTest
@testable import OpenComputerUseKit

/// When the shared app agent dies mid-request the MCP proxy answers the host itself, so the host sees one failed call
/// instead of a closed connection.
final class AppAgentLossResponseTests: XCTestCase {

    private func object(_ line: String?) throws -> [String: Any] {
        let text = try XCTUnwrap(line, "expected a response line")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    func testToolsCallGetsAnIsErrorToolResultWithTheSameId() throws {
        let line = #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"click","arguments":{}}}"#
        let reply = try object(AppAgentLossResponse.response(forRequestLine: line))

        XCTAssertEqual(reply["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(reply["id"] as? Int, 7)
        XCTAssertNil(reply["error"])
        let result = try XCTUnwrap(reply["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, true)
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 1)
        guard let first = content.first else { return }
        let text = try XCTUnwrap(first["text"] as? String)
        XCTAssertTrue(text.contains("NOT retried"))
        XCTAssertTrue(text.contains("get_app_state"))
    }

    func testStringIdIsEchoedUnchanged() throws {
        let line = #"{"jsonrpc":"2.0","id":"abc-1","method":"tools/call","params":{"name":"get_app_state"}}"#
        let reply = try object(AppAgentLossResponse.response(forRequestLine: line))
        XCTAssertEqual(reply["id"] as? String, "abc-1")
    }

    func testNonToolRequestGetsAJsonRpcError() throws {
        let line = #"{"jsonrpc":"2.0","id":3,"method":"tools/list"}"#
        let reply = try object(AppAgentLossResponse.response(forRequestLine: line))

        XCTAssertEqual(reply["id"] as? Int, 3)
        XCTAssertNil(reply["result"])
        let error = try XCTUnwrap(reply["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32603)
        XCTAssertFalse((error["message"] as? String ?? "").isEmpty)
    }

    func testNotificationWithoutIdGetsNoResponse() {
        let line = #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#
        XCTAssertNil(AppAgentLossResponse.response(forRequestLine: line))
    }

    func testNullIdAndUnparseableLinesGetNoResponse() {
        XCTAssertNil(AppAgentLossResponse.response(forRequestLine: #"{"jsonrpc":"2.0","id":null,"method":"tools/call"}"#))
        XCTAssertNil(AppAgentLossResponse.response(forRequestLine: "not json"))
    }

    func testCustomMessageReplacesTheDefaultText() throws {
        let line = #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"click"}}"#
        let reply = try object(AppAgentLossResponse.response(forRequestLine: line, message: "agent unreachable"))
        let result = try XCTUnwrap(reply["result"] as? [String: Any])
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        XCTAssertEqual(content.first?["text"] as? String, "agent unreachable")
    }
}
