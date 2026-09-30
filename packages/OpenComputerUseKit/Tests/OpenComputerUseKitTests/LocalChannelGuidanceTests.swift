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
