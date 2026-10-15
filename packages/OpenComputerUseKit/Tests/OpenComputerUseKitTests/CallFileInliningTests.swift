import XCTest
@testable import OpenComputerUseKit

final class CallFileInliningTests: XCTestCase {
    private func writeTemporaryFile(_ contents: String) throws -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("call-file-\(UUID().uuidString).json")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url.path
    }

    func testArgsFileBecomesInlineArgs() throws {
        let path = try writeTemporaryFile(#"{"app":"TextEdit"}"#)

        let inlined = try inliningOpenComputerUseCallFiles(arguments: ["call", "get_app_state", "--args-file", path])

        XCTAssertEqual(inlined, ["call", "get_app_state", "--args", #"{"app":"TextEdit"}"#])
    }

    func testCallsFileBecomesInlineCallsAndKeepsTheDelay() throws {
        let path = try writeTemporaryFile(#"[{"tool":"list_apps"}]"#)

        let inlined = try inliningOpenComputerUseCallFiles(
            arguments: ["call", "--calls-file", path, "--sleep", "0.5"]
        )

        XCTAssertEqual(inlined, ["call", "--calls", #"[{"tool":"list_apps"}]"#, "--sleep", "0.5"])
        guard case let .call(.sequence(callsJSON, callsFile, delay))? = try? parseOpenComputerUseCLI(arguments: inlined) else {
            return XCTFail("inlined arguments must parse as a call sequence")
        }
        XCTAssertEqual(callsJSON, #"[{"tool":"list_apps"}]"#)
        XCTAssertNil(callsFile)
        XCTAssertEqual(delay, 0.5)
    }

    func testCallsFileWithDefaultDelayKeepsTheDefault() throws {
        let path = try writeTemporaryFile("[]")

        let inlined = try inliningOpenComputerUseCallFiles(arguments: ["call", "--calls-file", path])

        guard case let .call(.sequence(_, _, delay))? = try? parseOpenComputerUseCLI(arguments: inlined) else {
            return XCTFail("inlined arguments must parse as a call sequence")
        }
        XCTAssertEqual(delay, openComputerUseDefaultInterCallDelay)
    }

    func testInlineAndNonCallArgumentsPassThroughUnchanged() throws {
        let unchanged: [[String]] = [
            ["call", "click", "--args", #"{"app":"x"}"#],
            ["call", "--calls", "[]"],
            ["list-apps"],
            ["snapshot", "Mail"],
            ["call", "click", "--args", "{}", "--args-file", "/nonexistent"],
            ["call", "--bogus"],
            [],
        ]
        for arguments in unchanged {
            XCTAssertEqual(try inliningOpenComputerUseCallFiles(arguments: arguments), arguments)
        }
    }

    func testUnreadableFileReportsTheCallerSidePath() {
        let missing = "/nonexistent/call-file.json"

        XCTAssertThrowsError(try inliningOpenComputerUseCallFiles(arguments: ["call", "click", "--args-file", missing])) { error in
            XCTAssertTrue((error as? OpenComputerUseCLIError)?.message.contains(missing) == true)
        }
    }
}
