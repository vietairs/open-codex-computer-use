import XCTest
@testable import OpenComputerUseKit

/// Pins the agent-facing server instructions: start-of-turn freshness stays, per-action state fetches go, the batch
/// tool is named, and the AppleScript line keeps its exact text and position.
final class ServerInstructionsGuidanceTests: XCTestCase {
    private let appleScriptLine =
        "Avoid falling back to AppleScript during a computer use session. Prefer Computer Use tools as much as possible to complete tasks."

    func testInstructionsKeepStartOfTurnGetAppState() {
        XCTAssertTrue(baseComputerUseServerInstructions.contains("at the start of each assistant turn"))
    }

    func testInstructionsDiscourageGetAppStateAfterEveryAction() {
        XCTAssertTrue(baseComputerUseServerInstructions.contains("do not call `get_app_state` after every action"))
    }

    func testInstructionsDropTheFetchLatestStateAfterEachActionSentence() {
        XCTAssertFalse(
            baseComputerUseServerInstructions.contains("After each action, use the action result or fetch the latest state")
        )
    }

    func testToolListNamesPerformActions() {
        XCTAssertTrue(baseComputerUseServerInstructions.contains("set_value, and perform_actions."))
    }

    func testInstructionsExplainWhenToBatch() {
        XCTAssertTrue(
            baseComputerUseServerInstructions.contains("Use `perform_actions` for a short sequence you can fully specify")
        )
    }

    func testInstructionsMentionIncludeScreenshotOptIn() {
        XCTAssertTrue(baseComputerUseServerInstructions.contains("include_screenshot: true"))
    }

    func testAppleScriptLineIsVerbatimAndStaysAtSourceLineSixteen() {
        // The string body starts at source line 4, so element 12 is source line 16.
        let lines = baseComputerUseServerInstructions.components(separatedBy: "\n")
        XCTAssertGreaterThan(lines.count, 12)
        guard lines.count > 12 else { return }
        XCTAssertEqual(lines[12], appleScriptLine)
    }

    func testCascadeGuideIsNotAppendedWithoutTheAdvisoryTool() {
        XCTAssertEqual(computerUseServerInstructions(environment: [:]), baseComputerUseServerInstructions)
    }
}
