import ApplicationServices
import CoreGraphics
import Foundation
import XCTest
@testable import OpenComputerUseKit

private struct BatchTestUnlockedSessionProvider: MacSessionStateProvider {
    func currentSnapshot() -> MacSessionSnapshot {
        MacSessionSnapshot(isLocked: false, isUnknown: false, rawKeysSeen: ["CGSSessionScreenIsLocked"])
    }
}

private struct BatchTestLockedSessionProvider: MacSessionStateProvider {
    func currentSnapshot() -> MacSessionSnapshot {
        MacSessionSnapshot(isLocked: true, isUnknown: false, rawKeysSeen: ["CGSSessionScreenIsLocked"])
    }
}

private struct BatchTestBoom: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Covers the batch runner, its result shape, the step parser and the batch-only focus and geometry rules.
final class BatchActionRunnerTests: XCTestCase {
    // MARK: - Fixtures

    private let clickStep = ActionStep.click(
        elementIndex: "12", x: nil, y: nil, clickCount: 1, mouseButton: "left", clickMethod: .auto
    )

    private func fourSteps() -> [ActionStep] {
        [
            clickStep,
            .typeText(text: "secret-typed-text"),
            .pressKey(key: "Return"),
            .click(elementIndex: "40", x: nil, y: nil, clickCount: 1, mouseButton: "left", clickMethod: .auto),
        ]
    }

    private func makePinnedSnapshot(focusedElement: AXUIElement?) -> AppSnapshot {
        AppSnapshot(
            app: RunningAppDescriptor(
                name: "Sample Chat",
                bundleIdentifier: "com.example.SampleChat",
                pid: 18_465,
                runningApplication: NSRunningApplication.current
            ),
            windowTitle: "Sample Chat",
            windowBounds: nil,
            targetWindowID: nil,
            targetWindowLayer: nil,
            screenshotPNGData: nil,
            mode: .accessibility,
            treeLines: [],
            treeLineOffsets: [:],
            focusedSummary: nil,
            focusedElement: focusedElement,
            selectedText: nil,
            elements: [:],
            windowContentIsEmpty: true
        )
    }

    private func makeUnlockedDispatcher() -> ComputerUseToolDispatcher {
        ComputerUseToolDispatcher(guard: MacSessionGuard(provider: BatchTestUnlockedSessionProvider()))
    }

    private func step(_ tool: String, _ args: [String: Any]) -> [String: Any] {
        ["tool": tool, "args": args]
    }

    /// The message of the `invalidArguments` error `parseBatchSteps` throws, or nil when it does not throw that.
    private func parseFailureMessage(_ raw: Any?) -> String? {
        do {
            _ = try makeUnlockedDispatcher().parseBatchSteps(raw)
            return nil
        } catch ComputerUseError.invalidArguments(let message) {
            return message
        } catch {
            return nil
        }
    }

    // MARK: - Runner: stop on first failure

    func testRunStopsAtFirstFailureAndMarksLaterStepsNotRun() {
        var performed: [Int] = []
        var settled: [Int] = []
        let report = BatchActionRunner.run(
            steps: fourSteps(),
            beforeEachStep: { settled.append($0) },
            perform: { index, _ in
                performed.append(index)
                if index == 1 { throw BatchTestBoom(message: "boom") }
            }
        )

        XCTAssertEqual(report.outcomes, [.ok, .failed("boom"), .notRun, .notRun])
        XCTAssertEqual(performed, [0, 1])
        XCTAssertEqual(settled, [0, 1])
        XCTAssertTrue(report.hasFailure)
    }

    func testRunMarksStepFailedWhenBeforeEachStepThrowsAndNeverPerformsIt() {
        var performed: [Int] = []
        let report = BatchActionRunner.run(
            steps: fourSteps(),
            beforeEachStep: { index in
                if index == 1 { throw ComputerUseError.stateUnavailable("macOS is locked") }
            },
            perform: { index, _ in performed.append(index) }
        )

        XCTAssertEqual(report.outcomes, [.ok, .failed("macOS is locked"), .notRun, .notRun])
        XCTAssertEqual(performed, [0])
    }

    func testRunReportsNoFailureWhenEveryStepSucceeds() {
        let report = BatchActionRunner.run(steps: fourSteps(), beforeEachStep: { _ in }, perform: { _, _ in })

        XCTAssertEqual(report.outcomes, [.ok, .ok, .ok, .ok])
        XCTAssertFalse(report.hasFailure)
    }

    // MARK: - Step lines

    func testStepLinesUseExactTextAndNeverEchoTypedText() {
        let report = BatchActionReport(
            steps: fourSteps(),
            outcomes: [.ok, .ok, .failed("boom"), .notRun]
        )

        XCTAssertEqual(report.stepLines, [
            "Step 1 click element_index=12: ok",
            "Step 2 type_text: ok",
            "Step 3 press_key key=Return: failed: boom",
            "Step 4 click element_index=40: not run",
        ])
        XCTAssertFalse(report.stepLines.joined(separator: "\n").contains("secret-typed-text"))
    }

    func testSummaryCoversEveryStepKindWithoutValues() {
        XCTAssertEqual(
            ActionStep.click(elementIndex: nil, x: 100, y: 40, clickCount: 1, mouseButton: "left", clickMethod: .auto)
                .summary,
            "click x=100 y=40"
        )
        XCTAssertEqual(ActionStep.setValue(elementIndex: "3", value: "private-value").summary, "set_value element_index=3")
        XCTAssertEqual(
            ActionStep.scroll(direction: "down", elementIndex: "5", pages: 1).summary,
            "scroll element_index=5 direction=down"
        )
        XCTAssertEqual(
            ActionStep.performSecondaryAction(elementIndex: "7", action: "AXShowMenu").summary,
            "perform_secondary_action element_index=7 action=AXShowMenu"
        )
    }

    func testToolNameAndElementIndexAccessors() {
        XCTAssertEqual(clickStep.toolName, "click")
        XCTAssertEqual(clickStep.elementIndex, "12")
        XCTAssertEqual(ActionStep.typeText(text: "a").toolName, "type_text")
        XCTAssertNil(ActionStep.typeText(text: "a").elementIndex)
        XCTAssertEqual(ActionStep.pressKey(key: "a").toolName, "press_key")
        XCTAssertEqual(ActionStep.setValue(elementIndex: "3", value: "v").elementIndex, "3")
        XCTAssertEqual(ActionStep.scroll(direction: "up", elementIndex: "4", pages: 2).toolName, "scroll")
        XCTAssertEqual(
            ActionStep.performSecondaryAction(elementIndex: "7", action: "AXPress").toolName,
            "perform_secondary_action"
        )
        XCTAssertEqual(
            ActionStep.allowedToolNames,
            ["click", "type_text", "press_key", "set_value", "scroll", "perform_secondary_action"]
        )
        XCTAssertEqual(BatchActionRunner.maxSteps, 10)
    }

    // MARK: - Result shape

    func testResultJoinsStepLinesBlankLineAndFinalState() {
        let report = BatchActionReport(steps: [clickStep], outcomes: [.ok])

        let result = BatchActionRunner.result(
            report: report, finalState: .success(ToolCallResult.text("STATE")), notReadReason: nil
        )

        XCTAssertEqual(result.primaryText, report.stepLines.joined(separator: "\n") + "\n\nSTATE")
        XCTAssertEqual(result.content.count, 1)
        XCTAssertFalse(result.isError)
    }

    func testResultKeepsAttachedImageAfterTheText() {
        let report = BatchActionReport(steps: [clickStep], outcomes: [.ok])
        let state = ToolCallResult(content: [.text("STATE"), .pngImage(Data([1, 2, 3]))])

        let result = BatchActionRunner.result(report: report, finalState: .success(state), notReadReason: nil)

        XCTAssertEqual(result.content.count, 2)
        XCTAssertEqual(result.content[0].dictionary["type"] as? String, "text")
        XCTAssertEqual(result.content[1].dictionary["type"] as? String, "image")
    }

    func testResultIsErrorWhenAnyStepFailedEvenIfFinalStateSucceeded() {
        let report = BatchActionReport(steps: fourSteps(), outcomes: [.ok, .failed("boom"), .notRun, .notRun])

        let result = BatchActionRunner.result(
            report: report, finalState: .success(ToolCallResult.text("STATE")), notReadReason: nil
        )

        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.isError, report.hasFailure)
        XCTAssertTrue((result.primaryText ?? "").hasSuffix("STATE"))
    }

    func testFinalStateFailureKeepsStepLines() {
        let report = BatchActionReport(steps: [clickStep, .pressKey(key: "Return")], outcomes: [.ok, .ok])

        let result = BatchActionRunner.result(
            report: report,
            finalState: .failure(ComputerUseError.stateUnavailable("no window")),
            notReadReason: nil
        )

        let text = result.primaryText ?? ""
        XCTAssertTrue(text.hasPrefix(report.stepLines.joined(separator: "\n")))
        XCTAssertTrue(text.contains("Final state unavailable: "))
        XCTAssertTrue(text.contains("no window"))
        XCTAssertTrue(result.isError)
    }

    func testFinalStateSkippedWhenLockedReportsWhyAndIsError() {
        let report = BatchActionReport(steps: [clickStep], outcomes: [.ok])

        let result = BatchActionRunner.result(report: report, finalState: nil, notReadReason: "macOS is locked")

        let text = result.primaryText ?? ""
        XCTAssertTrue(text.hasPrefix(report.stepLines.joined(separator: "\n")))
        XCTAssertTrue(text.contains("Final state not read: macOS is locked"))
        XCTAssertTrue(result.isError)
    }

    func testErrorTextMatchesWhatTheDispatcherShowsForTheSameError() {
        XCTAssertEqual(
            BatchActionRunner.errorText(ComputerUseError.stateUnavailable("window gone")), "window gone"
        )
        XCTAssertEqual(
            BatchActionRunner.errorText(ComputerUseError.invalidArguments("bad")), "invalidArguments(\"bad\")"
        )
        XCTAssertEqual(BatchActionRunner.errorText(BatchTestBoom(message: "boom")), "boom")
    }

    // MARK: - Index resolution and recovery policy

    func testUnknownElementIndicesAreReportedAgainstThePinnedSnapshot() {
        let steps: [ActionStep] = [
            .click(elementIndex: "12", x: nil, y: nil, clickCount: 1, mouseButton: "left", clickMethod: .auto),
            .setValue(elementIndex: "99", value: "v"),
            .pressKey(key: "Return"),
        ]

        XCTAssertEqual(BatchActionRunner.unknownElementIndices(in: steps, knownIndices: [12, 40]), ["99"])
        XCTAssertEqual(BatchActionRunner.unknownElementIndices(in: steps, knownIndices: [12, 99]), [])
    }

    func testUnknownElementIndicesTreatNonNumericValuesAsUnknownInStepOrder() {
        let steps: [ActionStep] = [
            .scroll(direction: "down", elementIndex: "abc", pages: 1),
            .performSecondaryAction(elementIndex: "77", action: "AXPress"),
        ]

        XCTAssertEqual(BatchActionRunner.unknownElementIndices(in: steps, knownIndices: [1]), ["abc", "77"])
    }

    // MARK: - Received state required for element_index steps

    func testElementIndexStepWithoutReceivedStateFailsClosedNamingTheFirstSuchStep() throws {
        let steps: [ActionStep] = [
            .pressKey(key: "cmd+f"),
            .setValue(elementIndex: "12", value: "v"),
            clickStep,
        ]

        let message = try XCTUnwrap(
            BatchActionRunner.missingReceivedStateMessage(app: "Mail", steps: steps, hasReceivedState: false)
        )

        XCTAssertTrue(message.hasPrefix("step 2: "), message)
        XCTAssertTrue(message.contains("call get_app_state for Mail before perform_actions"), message)
    }

    func testElementIndexStepsRunWhenStateWasReceived() {
        XCTAssertNil(BatchActionRunner.missingReceivedStateMessage(app: "Mail", steps: fourSteps(), hasReceivedState: true))
    }

    func testCoordinateAndKeyOnlyBatchesNeedNoReceivedState() {
        let steps: [ActionStep] = [
            .click(elementIndex: nil, x: 10, y: 20, clickCount: 1, mouseButton: "left", clickMethod: .auto),
            .typeText(text: "hello"),
            .pressKey(key: "Return"),
        ]

        XCTAssertNil(BatchActionRunner.missingReceivedStateMessage(app: "Mail", steps: steps, hasReceivedState: false))
    }

    func testDispatcherRefusesElementIndexBatchWithoutReceivedStateBeforeResolvingTheApp() {
        let result = makeUnlockedDispatcher().callToolAsResult(
            name: "perform_actions",
            arguments: [
                "app": "NoSuchApp-batch-state-test",
                "actions": [step("press_key", ["key": "a"]), step("click", ["element_index": "3"])],
            ]
        )

        XCTAssertTrue(result.isError)
        let text = result.primaryText ?? ""
        XCTAssertTrue(text.contains("step 2: "), text)
        XCTAssertTrue(text.contains("call get_app_state for NoSuchApp-batch-state-test before perform_actions"), text)
        XCTAssertFalse(text.contains("appNotFound"), text)
    }

    func testDispatcherLetsCoordinateAndKeyOnlyBatchesPassTheStateCheck() {
        let result = makeUnlockedDispatcher().callToolAsResult(
            name: "perform_actions",
            arguments: [
                "app": "NoSuchApp-batch-state-test",
                "actions": [step("click", ["x": 10, "y": 20]), step("press_key", ["key": "a"])],
            ]
        )

        // The batch got past the state check and failed only on resolving the unknown app.
        XCTAssertTrue(result.isError)
        let text = result.primaryText ?? ""
        XCTAssertTrue(text.contains("appNotFound"), text)
        XCTAssertFalse(text.contains("before perform_actions"), text)
    }

    func testMostRestrictiveRecoveryPolicyIsReadOnlyOnlyWhenAnyClickUsesSkyClick() {
        let auto = clickStep
        let sky = ActionStep.click(
            elementIndex: "12", x: nil, y: nil, clickCount: 1, mouseButton: "left", clickMethod: .skyClick
        )

        XCTAssertEqual(BatchActionRunner.mostRestrictiveRecoveryPolicy(for: [auto, sky]), .readOnly)
        XCTAssertEqual(
            BatchActionRunner.mostRestrictiveRecoveryPolicy(for: [auto, .typeText(text: "a")]), .allowActivation
        )
    }

    // MARK: - Live focus (a batch must never use the pinned focus)

    func testBatchStepReadsFocusLiveAndIgnoresPinnedFocus() throws {
        let pinnedFocus = AXUIElementCreateApplication(4_242)
        let liveFocus = AXUIElementCreateApplication(4_243)
        var liveReads = 0
        let context = ActionContext.batchStep(pinned: makePinnedSnapshot(focusedElement: pinnedFocus))

        let target = typingTargetElement(
            context: context,
            snapshotFocus: pinnedFocus,
            liveFocus: {
                liveReads += 1
                return liveFocus
            }
        )

        XCTAssertTrue(CFEqual(try XCTUnwrap(target), liveFocus))
        XCTAssertFalse(CFEqual(try XCTUnwrap(target), pinnedFocus))
        XCTAssertEqual(liveReads, 1)
        XCTAssertTrue(context.isBatchStep)
    }

    func testSingleActionKeepsSnapshotFocusAndNeverReadsLiveFocus() throws {
        let snapshotFocus = AXUIElementCreateApplication(4_242)
        var liveReads = 0
        let context = ActionContext.single(includeScreenshot: false)

        let target = typingTargetElement(
            context: context,
            snapshotFocus: snapshotFocus,
            liveFocus: {
                liveReads += 1
                return AXUIElementCreateApplication(4_243)
            }
        )

        XCTAssertTrue(CFEqual(try XCTUnwrap(target), snapshotFocus))
        XCTAssertEqual(liveReads, 0)
        XCTAssertFalse(context.isBatchStep)
        XCTAssertNil(context.pinnedSnapshot)
        XCTAssertFalse(context.includeScreenshot)
    }

    // MARK: - Live geometry (never the pinned values)

    func testBatchGeometryUsesLiveWindowBoundsAndLiveFrame() throws {
        let pinned = CGRect(x: 0, y: 0, width: 800, height: 600)
        let live = CGRect(x: 40, y: 60, width: 800, height: 600)
        let frame = CGRect(x: 10, y: 20, width: 30, height: 12)

        let geometry = try batchStepGeometry(
            pinnedWindowBounds: pinned,
            liveWindowBounds: live,
            liveLocalFrame: frame,
            needsElementFrame: true,
            elementIndex: "3"
        )

        XCTAssertEqual(geometry.windowBounds, live)
        XCTAssertEqual(geometry.localFrame, frame)
    }

    func testBatchGeometryThrowsWhenTheWindowLeftTheScreen() {
        XCTAssertThrowsError(
            try batchStepGeometry(
                pinnedWindowBounds: CGRect(x: 0, y: 0, width: 800, height: 600),
                liveWindowBounds: nil,
                liveLocalFrame: CGRect(x: 1, y: 1, width: 5, height: 5),
                needsElementFrame: true,
                elementIndex: "3"
            )
        ) { error in
            XCTAssertTrue(BatchActionRunner.errorText(error).contains("the target window is no longer on screen"))
        }
    }

    func testBatchGeometryThrowsWhenTheElementFrameIsGone() {
        XCTAssertThrowsError(
            try batchStepGeometry(
                pinnedWindowBounds: CGRect(x: 0, y: 0, width: 800, height: 600),
                liveWindowBounds: CGRect(x: 0, y: 0, width: 800, height: 600),
                liveLocalFrame: nil,
                needsElementFrame: true,
                elementIndex: "3"
            )
        ) { error in
            XCTAssertTrue(BatchActionRunner.errorText(error).contains("element_index 3 is no longer on screen"))
        }
    }

    func testBatchGeometrySkipsTheElementFrameWhenNotNeeded() throws {
        let geometry = try batchStepGeometry(
            pinnedWindowBounds: nil,
            liveWindowBounds: nil,
            liveLocalFrame: nil,
            needsElementFrame: false,
            elementIndex: nil
        )

        XCTAssertNil(geometry.windowBounds)
        XCTAssertNil(geometry.localFrame)
    }

    func testBatchCoordinateClickFailsClosedWhenTheWindowResizedSinceThePinnedScreenshot() {
        XCTAssertThrowsError(
            try batchStepGeometry(
                pinnedWindowBounds: CGRect(x: 0, y: 0, width: 800, height: 600),
                liveWindowBounds: CGRect(x: 0, y: 0, width: 1000, height: 600),
                liveLocalFrame: nil,
                needsElementFrame: false,
                elementIndex: nil,
                scalesByPinnedScreenshot: true
            )
        ) { error in
            XCTAssertEqual(BatchActionRunner.errorText(error), screenshotFrameMismatchMessage)
        }
    }

    func testBatchCoordinateClickKeepsThePinnedScreenshotWhenOnlyTheWindowMoved() throws {
        let live = CGRect(x: 40, y: 60, width: 800, height: 600)

        let geometry = try batchStepGeometry(
            pinnedWindowBounds: CGRect(x: 0, y: 0, width: 800, height: 600),
            liveWindowBounds: live,
            liveLocalFrame: nil,
            needsElementFrame: false,
            elementIndex: nil,
            scalesByPinnedScreenshot: true
        )

        XCTAssertEqual(geometry.windowBounds, live)
    }

    func testBatchGeometryIgnoresResizeWhenNoPinnedScreenshotScalesCoordinates() throws {
        let live = CGRect(x: 0, y: 0, width: 1000, height: 600)

        let geometry = try batchStepGeometry(
            pinnedWindowBounds: CGRect(x: 0, y: 0, width: 800, height: 600),
            liveWindowBounds: live,
            liveLocalFrame: nil,
            needsElementFrame: false,
            elementIndex: nil,
            scalesByPinnedScreenshot: false
        )

        XCTAssertEqual(geometry.windowBounds, live)
    }

    // MARK: - Upfront parse

    func testEmptyActionsAreRejectedBeforeAnyServiceWork() {
        let result = makeUnlockedDispatcher().callToolAsResult(
            name: "perform_actions", arguments: ["app": "NoSuchApp", "actions": [Any]()]
        )

        XCTAssertTrue(result.isError)
        XCTAssertTrue((result.primaryText ?? "").contains("actions must be an array of 1-10 steps"))
    }

    func testMissingActionsAreRejected() {
        XCTAssertEqual(parseFailureMessage(nil), "actions must be an array of 1-10 steps")
    }

    func testMoreThanTenStepsAreRejected() {
        let steps = (0..<11).map { _ in step("press_key", ["key": "a"]) }

        XCTAssertEqual(parseFailureMessage(steps), "actions must be an array of 1-10 steps")
        XCTAssertNil(parseFailureMessage((0..<10).map { _ in step("press_key", ["key": "a"]) }))
    }

    func testStepThatIsNotAnObjectWithToolAndArgsIsRejected() {
        XCTAssertEqual(
            parseFailureMessage([["tool": "press_key"]]),
            "step 1: each step must be an object with \"tool\" and \"args\""
        )
        XCTAssertEqual(
            parseFailureMessage([step("press_key", ["key": "a"]), "click"]),
            "step 2: each step must be an object with \"tool\" and \"args\""
        )
    }

    func testDragIsNotAllowedInABatch() {
        let result = makeUnlockedDispatcher().callToolAsResult(
            name: "perform_actions",
            arguments: ["app": "NoSuchApp", "actions": [step("drag", ["from_x": 1, "from_y": 1, "to_x": 2, "to_y": 2])]]
        )

        XCTAssertTrue(result.isError)
        XCTAssertTrue((result.primaryText ?? "").contains("step 1: tool 'drag' is not allowed in perform_actions"))
    }

    func testAppInsideAStepIsRejected() {
        let message = parseFailureMessage([
            step("press_key", ["key": "a"]),
            step("type_text", ["app": "X", "text": "a"]),
        ])

        XCTAssertEqual(message, "step 2: args must not contain \"app\"; perform_actions acts on one app")
    }

    func testArgumentErrorsAreWrappedWithTheStepNumber() throws {
        let message = try XCTUnwrap(parseFailureMessage([step("press_key", [:])]))

        XCTAssertTrue(message.hasPrefix("step 1: "))
        XCTAssertTrue(message.contains(BatchActionRunner.errorText(ComputerUseError.missingArgument("key"))))
    }

    func testScrollArgumentsFollowTheSingleToolRules() throws {
        let badDirection = try XCTUnwrap(parseFailureMessage([
            step("scroll", ["element_index": "1", "direction": "sideways"]),
        ]))
        XCTAssertTrue(badDirection.hasPrefix("step 1: "))

        let badPages = try XCTUnwrap(parseFailureMessage([
            step("scroll", ["element_index": "1", "direction": "down", "pages": 0]),
        ]))
        XCTAssertTrue(badPages.hasPrefix("step 1: "))
    }

    func testBatchClickCountFollowsTheSingleClickRange() throws {
        for value in [1e20, Double.infinity, 0, 4, 1.5] as [Any] {
            let message = try XCTUnwrap(
                parseFailureMessage([step("click", ["element_index": "1", "click_count": value])]),
                "click_count \(value) was accepted"
            )
            XCTAssertTrue(message.hasPrefix("step 1: "), message)
            XCTAssertTrue(message.contains("click_count"), message)
        }

        // JSON `true` decodes to an NSNumber that bridges to 1; it must still be refused on the batch path.
        let decodedTrue = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(#"{"element_index": "1", "click_count": true}"#.utf8)) as? [String: Any]
        )
        let booleanMessage = try XCTUnwrap(parseFailureMessage([step("click", decodedTrue)]), "click_count true was accepted")
        XCTAssertTrue(booleanMessage.contains("click_count"), booleanMessage)

        let steps = try makeUnlockedDispatcher().parseBatchSteps([
            step("click", ["element_index": "1", "click_count": 3]),
        ])
        XCTAssertEqual(steps, [
            .click(elementIndex: "1", x: nil, y: nil, clickCount: 3, mouseButton: "left", clickMethod: .auto),
        ])
    }

    // MARK: - Parse success

    func testParseBatchStepsBuildsTypedStepsWithSingleToolDefaults() throws {
        let steps = try makeUnlockedDispatcher().parseBatchSteps([
            step("click", ["element_index": "12"]),
            step("type_text", ["text": "combio"]),
            step("press_key", ["key": "Return"]),
        ])

        XCTAssertEqual(steps, [
            .click(elementIndex: "12", x: nil, y: nil, clickCount: 1, mouseButton: "left", clickMethod: .auto),
            .typeText(text: "combio"),
            .pressKey(key: "Return"),
        ])
    }

    func testParseBatchStepsCoversSetValueScrollAndSecondaryAction() throws {
        let steps = try makeUnlockedDispatcher().parseBatchSteps([
            step("set_value", ["element_index": "3", "value": "hello"]),
            step("scroll", ["element_index": "5", "direction": "down", "pages": 2]),
            step("perform_secondary_action", ["element_index": "7", "action": "AXShowMenu"]),
            step("click", ["x": 100, "y": 40]),
        ])

        XCTAssertEqual(steps, [
            .setValue(elementIndex: "3", value: "hello"),
            .scroll(direction: "down", elementIndex: "5", pages: 2),
            .performSecondaryAction(elementIndex: "7", action: "AXShowMenu"),
            .click(elementIndex: nil, x: 100, y: 40, clickCount: 1, mouseButton: "left", clickMethod: .auto),
        ])
    }

    // MARK: - Registration

    func testPerformActionsIsRegisteredLastWithTheBatchSchema() throws {
        let definition = try XCTUnwrap(ToolDefinitions.all.last)
        XCTAssertEqual(definition.name, "perform_actions")
        XCTAssertEqual(definition.inputSchema["required"] as? [String], ["app", "actions"])

        let properties = try XCTUnwrap(definition.inputSchema["properties"] as? [String: Any])
        let actions = try XCTUnwrap(properties["actions"] as? [String: Any])
        XCTAssertEqual(actions["maxItems"] as? Int, 10)
        XCTAssertEqual(actions["minItems"] as? Int, 1)
        let items = try XCTUnwrap(actions["items"] as? [String: Any])
        let itemProperties = try XCTUnwrap(items["properties"] as? [String: Any])
        let tool = try XCTUnwrap(itemProperties["tool"] as? [String: Any])
        XCTAssertEqual(tool["enum"] as? [String], ActionStep.allowedToolNames)
        XCTAssertNotNil(properties["include_screenshot"])
        XCTAssertEqual(ToolDefinitions.all.count, 10)
    }

    func testLockedDispatcherRefusesPerformActionsBeforeParsing() {
        let dispatcher = ComputerUseToolDispatcher(
            service: ComputerUseService(),
            guard: MacSessionGuard(provider: BatchTestLockedSessionProvider())
        )

        let result = dispatcher.callToolAsResult(
            name: "perform_actions",
            arguments: ["app": "Finder", "actions": [step("press_key", ["key": "a"])]]
        )

        XCTAssertTrue(result.isError)
        XCTAssertTrue((result.primaryText ?? "").contains("macOS is locked"))
    }
}
