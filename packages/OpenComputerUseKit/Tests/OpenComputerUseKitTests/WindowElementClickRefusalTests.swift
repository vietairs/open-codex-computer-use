import CoreGraphics
import XCTest
@testable import OpenComputerUseKit

/// An element_index click on a window has no press of its own, so `auto` used to press whichever hidden control sat
/// inside it. The window is refused up front, hidden descendants are never pressed, and a failed refresh after an
/// action says the action already ran.
final class WindowElementClickRefusalTests: XCTestCase {
    private let windowFrame = CGRect(x: 0, y: 0, width: 800, height: 600)

    private func candidate(frame: CGRect?, subrole: String? = nil, actions: [String] = ["AXPress"]) -> ElementRecord {
        ElementRecord(
            index: -1,
            identifier: nil,
            element: nil,
            localFrame: frame,
            subrole: subrole,
            rawActions: actions,
            prettyActions: actions
        )
    }

    // MARK: window refusal

    func testWindowTargetIsRefusedForAutoAndAccessibility() throws {
        for method in [ClickMethod.auto, .accessibility] {
            let message = try XCTUnwrap(windowElementClickRefusal(role: "AXWindow", method: method, elementIndex: "0"))
            XCTAssertTrue(message.contains("element 0 is the window itself"))
            XCTAssertTrue(message.contains("does not raise or select windows"))
        }
    }

    func testWindowTargetIsAllowedForExplicitPostingMethods() {
        for method in [ClickMethod.appPost, .skyClick, .global] {
            XCTAssertNil(windowElementClickRefusal(role: "AXWindow", method: method, elementIndex: "0"))
        }
    }

    func testNonWindowTargetsAreNeverRefused() {
        for role in ["AXButton", "AXTextField", nil] {
            XCTAssertNil(windowElementClickRefusal(role: role, method: .auto, elementIndex: "3"))
        }
    }

    // MARK: descendant filter

    func testZeroSizeAndOutsideFramesAreExcluded() {
        let visible = candidate(frame: CGRect(x: 100, y: 100, width: 40, height: 20))
        let zeroWidth = candidate(frame: CGRect(x: 10, y: 10, width: 0, height: 18))
        let zeroHeight = candidate(frame: CGRect(x: 10, y: 10, width: 18, height: 0))
        let outside = candidate(frame: CGRect(x: 2000, y: 2000, width: 18, height: 18))

        let kept = excludingHiddenAndTabCloseCandidates(
            [zeroWidth, visible, zeroHeight, outside],
            targetFrame: windowFrame,
            closeButtonLabels: { _ in (nil, nil) }
        )

        XCTAssertEqual(kept.count, 1)
        if let first = kept.first {
            XCTAssertTrue(first === visible)
        }
    }

    func testTabCloseButtonsAreExcludedByIdentifierAndDescription() {
        let byIdentifier = candidate(frame: CGRect(x: 14, y: 57, width: 18, height: 18))
        let byDescription = candidate(frame: CGRect(x: 40, y: 57, width: 18, height: 18))
        let send = candidate(frame: CGRect(x: 300, y: 20, width: 60, height: 24))

        let kept = excludingHiddenAndTabCloseCandidates(
            [byIdentifier, byDescription, send],
            targetFrame: windowFrame,
            closeButtonLabels: { record in
                if record === byIdentifier { return ("_closeButton", nil) }
                if record === byDescription { return (nil, "Close tab") }
                return ("sendButton", "Send")
            }
        )

        XCTAssertEqual(kept.count, 1)
        if let first = kept.first {
            XCTAssertTrue(first === send)
        }
    }

    func testVisiblePressableControlsAreKeptInOrder() {
        let first = candidate(frame: CGRect(x: 10, y: 10, width: 30, height: 30))
        let second = candidate(frame: CGRect(x: 60, y: 10, width: 30, height: 30))
        let noFrame = candidate(frame: nil)

        let kept = excludingHiddenAndTabCloseCandidates(
            [first, noFrame, second],
            targetFrame: windowFrame,
            closeButtonLabels: { _ in ("compose", "Compose") }
        )

        XCTAssertEqual(kept.count, 3)
        if kept.count == 3 {
            XCTAssertTrue(kept[0] === first)
            XCTAssertTrue(kept[1] === noFrame)
            XCTAssertTrue(kept[2] === second)
        }
    }

    func testNonActionableCandidatesAreNeverAskedForLabels() {
        let inert = candidate(frame: CGRect(x: 10, y: 10, width: 30, height: 30), actions: [])
        var asked = 0
        _ = excludingHiddenAndTabCloseCandidates([inert], targetFrame: nil, closeButtonLabels: { _ in asked += 1; return (nil, nil) })
        XCTAssertEqual(asked, 0)
    }

    func testTitleBarCloseSubroleIsNotATabCloseButton() {
        XCTAssertFalse(isTabCloseButton(identifier: nil, description: "Close"))
        XCTAssertTrue(isTabCloseButton(identifier: "x_closeButton", description: nil))
        XCTAssertTrue(isTabCloseButton(identifier: nil, description: "close TAB"))
    }

    func testFrameFilterUsesTheTargetFrameItIsGiven() {
        // The target's cached frame is far from its children, but the live frame contains them.
        let staleTarget = CGRect(x: 0, y: 0, width: 200, height: 24)
        let liveTarget = CGRect(x: 0, y: 300, width: 200, height: 24)
        let child = candidate(frame: CGRect(x: 10, y: 302, width: 40, height: 20))
        let empty = candidate(frame: CGRect(x: 10, y: 302, width: 0, height: 0))

        let dropped = excludingHiddenAndTabCloseCandidates(
            [child], targetFrame: staleTarget, closeButtonLabels: { _ in (nil, nil) }
        )
        XCTAssertTrue(dropped.isEmpty)

        let kept = excludingHiddenAndTabCloseCandidates(
            [child, empty], targetFrame: liveTarget, closeButtonLabels: { _ in (nil, nil) }
        )
        XCTAssertEqual(kept.count, 1)
        if let first = kept.first {
            XCTAssertTrue(first === child)
        }
    }

    // MARK: batch pre-check

    func testBatchRefusesWindowClickBeforeAnyStepRuns() throws {
        let steps: [ActionStep] = [
            .typeText(text: "foo"),
            .click(elementIndex: "0", x: nil, y: nil, clickCount: 1, mouseButton: "left", clickMethod: .auto),
        ]
        let roles = ["0": "AXWindow"]

        let message = try XCTUnwrap(batchWindowClickRefusal(steps: steps, roleForIndex: { roles[$0] }))

        XCTAssertTrue(message.hasPrefix("step 2: "))
        XCTAssertTrue(message.contains("element 0 is the window itself"))
    }

    func testBatchAllowsControlClicksAndExplicitPostingOnWindows() {
        let steps: [ActionStep] = [
            .click(elementIndex: "1", x: nil, y: nil, clickCount: 1, mouseButton: "left", clickMethod: .auto),
            .click(elementIndex: "0", x: nil, y: nil, clickCount: 1, mouseButton: "left", clickMethod: .appPost),
            .click(elementIndex: nil, x: 5, y: 5, clickCount: 1, mouseButton: "left", clickMethod: .auto),
        ]
        let roles = ["0": "AXWindow", "1": "AXButton"]

        XCTAssertNil(batchWindowClickRefusal(steps: steps, roleForIndex: { roles[$0] }))
    }

    // MARK: honest post-action error

    func testNoWindowErrorAfterActionSaysActionWasPerformed() throws {
        let original = ComputerUseError.stateUnavailable(noBackgroundWindowMessage(appName: "Mail"))

        let rewritten = errorAfterPerformedAction(original, appName: "Mail")

        let message = try XCTUnwrap((rewritten as? ComputerUseError)?.errorDescription)
        XCTAssertTrue(message.hasPrefix(computerUseNoWindowFoundMessage))
        XCTAssertTrue(message.contains("The action was performed"))
        XCTAssertTrue(message.contains("may have closed"))
        XCTAssertTrue(message.contains("get_app_state"))
        XCTAssertFalse(message.contains("does not activate"))
    }

    func testOtherRefreshErrorsPassThroughUnchanged() throws {
        let other = ComputerUseError.stateUnavailable("something else broke")
        let passed = errorAfterPerformedAction(other, appName: "Mail")
        XCTAssertEqual((passed as? ComputerUseError)?.errorDescription, "something else broke")

        let nonState = ComputerUseError.message(noBackgroundWindowMessage(appName: "Mail"))
        XCTAssertEqual(
            (errorAfterPerformedAction(nonState, appName: "Mail") as? ComputerUseError)?.errorDescription,
            nonState.errorDescription
        )
    }
}
