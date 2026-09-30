import Foundation
import XCTest
@testable import OpenComputerUseKit

/// Pins the instruction text hosts read: the base instructions must advertise `find_elements` while keeping the
/// AppleScript line the relay swaps by exact match, and the script-first guide must not contradict the retained
/// turn-start `get_app_state` rule or drop the confirmation rule for externally visible actions.
final class LocalChannelGuidanceTests: XCTestCase {

    func testBaseInstructionsNameFindElements() {
        let toolSentence = baseComputerUseServerInstructions
            .components(separatedBy: "\n")
            .first { $0.hasPrefix("The available tools are") }
        XCTAssertNotNil(toolSentence, "the tool list sentence is missing from the base instructions")
        XCTAssertTrue(
            toolSentence?.contains("find_elements") ?? false,
            "the tool list sentence must name find_elements: \(toolSentence ?? "<none>")"
        )
        XCTAssertTrue(
            baseComputerUseServerInstructions.contains("call `find_elements`"),
            "the base instructions must tell the host when to call `find_elements`"
        )
    }

    func testBaseInstructionsKeepAppleScriptLine() {
        let occurrences = baseComputerUseServerInstructions
            .components(separatedBy: appleScriptAvoidanceInstructionLine)
            .count - 1
        XCTAssertEqual(
            occurrences, 1,
            "the AppleScript avoidance line must appear exactly once so the relay swap stays an exact match"
        )
    }

    func testScriptFirstGuideKeepsAskBeforeDestructive() {
        XCTAssertTrue(containsIgnoringCase(scriptFirstInstructionGuide, "Ask the user before"))
        XCTAssertTrue(scriptFirstInstructionGuide.contains("not a security boundary"))
        XCTAssertTrue(scriptFirstInstructionGuide.contains("run_script"))
    }

    func testScriptFirstGuideKeepsTurnStartStateForUIWork() {
        XCTAssertTrue(scriptFirstInstructionGuide.contains("find_elements"))
        XCTAssertTrue(scriptFirstInstructionGuide.contains("turn-start"))
        XCTAssertTrue(
            scriptFirstInstructionGuide.contains("only uses `run_script`"),
            "a script-only turn must be told it can skip the turn-start read"
        )
        XCTAssertTrue(
            containsIgnoringCase(scriptFirstInstructionGuide, "after a script changed the UI"),
            "the guide must name find_elements for the case where a script changed the UI"
        )
    }

    func testScriptFirstGuideNamesBatchTool() {
        XCTAssertTrue(
            scriptFirstInstructionGuide.contains("perform_actions"),
            "the guide's UI sentence must name the batch tool next to find_elements"
        )
    }

    func testInstructionsWithoutAdvisorStayBase() {
        XCTAssertEqual(
            computerUseServerInstructions(environment: [:]),
            baseComputerUseServerInstructions
        )
    }

    /// Hosts such as Claude Code cut server instructions at 2048 characters. The budget keeps headroom below that in
    /// every configuration a host can launch, so no tool's guidance is ever cut. The script channels make the text
    /// longest (the relay swaps the AppleScript line for the script-first guide); listing the advisory tool must not
    /// add to it, because its cascade guide travels in that tool's own description.
    private let instructionsCharacterBudget = 1900

    func testInstructionsFitTheBudgetInEveryHostConfiguration() throws {
        for advisor in [false, true] {
            for scripts in [false, true] {
                let label = "advisor \(advisor ? "set" : "unset"), scripts \(scripts ? "on" : "off")"
                let instructions = try hostInstructions(advisor: advisor, scripts: scripts)

                XCTAssertFalse(instructions.contains(DecisionAdvisor.cascadeGuide), "\(label): cascade guide")
                XCTAssertEqual(instructions.contains(scriptFirstInstructionGuide), scripts, "\(label): script-first guide")
                XCTAssertLessThanOrEqual(
                    instructions.count, instructionsCharacterBudget, "\(label): \(instructions.count) characters"
                )
            }
        }
    }

    private static let initializeLine =
        #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","clientInfo":{"name":"test","version":"0"},"capabilities":{}}}"#

    /// What a host receives from `initialize`: the agent's server answers it under the host's environment, and the relay
    /// patches the answer when the host turned the script channels on.
    private func hostInstructions(advisor: Bool, scripts: Bool) throws -> String {
        let agentEnvironment = advisor ? [DecisionModelEndpoint.environmentKey: "http://127.0.0.1:39501"] : [:]
        let server = StdioMCPServer(service: ComputerUseService(), environment: { agentEnvironment })
        let relay = LocalChannelRouter(environment: scripts ? [LocalChannelPolicy.environmentKey: "1"] : [:])

        let response = try XCTUnwrap(try relay.route(line: Self.initializeLine) { server.handle(line: $0) })
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any])
        let result = try XCTUnwrap(object["result"] as? [String: Any])
        return try XCTUnwrap(result["instructions"] as? String)
    }

    func testNewestToolGuidanceComesBeforeTheOlderRules() throws {
        let instructions = baseComputerUseServerInstructions
        let appleScriptLine = try XCTUnwrap(instructions.range(of: appleScriptAvoidanceInstructionLine))
        for marker in ["Use `perform_actions`", "call `find_elements`", "load `perform_actions` together with `get_app_state`"] {
            let range = try XCTUnwrap(instructions.range(of: marker), "missing: \(marker)")
            XCTAssertLessThan(range.lowerBound, appleScriptLine.lowerBound, "\(marker) must come before the older rules")
        }
    }

    private func containsIgnoringCase(_ text: String, _ needle: String) -> Bool {
        text.range(of: needle, options: .caseInsensitive) != nil
    }
}
