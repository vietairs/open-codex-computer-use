import CoreGraphics
import XCTest
@testable import OpenComputerUseKit

/// Pins the rules that make action results text-only by default: when the window is captured,
/// when a screenshot is attached, how x/y scaling survives a text-only result, and how the
/// `include_screenshot` argument is exposed and parsed.
final class ActionResultScreenshotPolicyTests: XCTestCase {
    // MARK: - Capture timing

    func testCaptureTimingForOnscreenWindowFollowsPolicy() {
        XCTAssertEqual(windowImageCaptureTiming(policy: .always, isOnscreen: true), .beforeWalk)
        XCTAssertEqual(windowImageCaptureTiming(policy: .whenTreeEmpty, isOnscreen: true), .afterWalkIfTreeEmpty)
        XCTAssertEqual(windowImageCaptureTiming(policy: .never, isOnscreen: true), .skip)
    }

    func testCaptureTimingSkipsOffscreenWindowForEveryPolicy() {
        XCTAssertEqual(windowImageCaptureTiming(policy: .always, isOnscreen: false), .skip)
        XCTAssertEqual(windowImageCaptureTiming(policy: .whenTreeEmpty, isOnscreen: false), .skip)
        XCTAssertEqual(windowImageCaptureTiming(policy: .never, isOnscreen: false), .skip)
    }

    // MARK: - Action capture policy and attach rule

    func testActionCapturePolicyMapsIncludeScreenshot() {
        XCTAssertEqual(actionCapturePolicy(includeScreenshot: false), .whenTreeEmpty)
        XCTAssertEqual(actionCapturePolicy(includeScreenshot: true), .always)
    }

    func testActionResultIsTextOnlyByDefault() {
        XCTAssertFalse(shouldAttachScreenshot(style: .actionResult, includeScreenshot: false, treeIsEmpty: false))
    }

    func testActionResultAttachesScreenshotWhenRequested() {
        XCTAssertTrue(shouldAttachScreenshot(style: .actionResult, includeScreenshot: true, treeIsEmpty: false))
    }

    func testActionResultAttachesScreenshotWhenTreeIsEmpty() {
        XCTAssertTrue(shouldAttachScreenshot(style: .actionResult, includeScreenshot: false, treeIsEmpty: true))
    }

    func testFullStateAlwaysAttachesScreenshot() {
        XCTAssertTrue(shouldAttachScreenshot(style: .fullState, includeScreenshot: false, treeIsEmpty: false))
    }

    func testCompactActionableNeverAttachesScreenshot() {
        XCTAssertFalse(shouldAttachScreenshot(style: .compactActionable, includeScreenshot: true, treeIsEmpty: true))
    }

    // MARK: - Carried screenshot frame

    func testSnapshotPixelSizeWinsOverCarriedFrame() throws {
        let carried = ReturnedScreenshotFrame(
            windowID: 7,
            windowSize: CGSize(width: 400, height: 300),
            pixelSize: CGSize(width: 1, height: 1)
        )

        let size = try resolveScreenshotPixelSize(
            snapshotPixelSize: CGSize(width: 800, height: 600),
            windowID: 9,
            windowBounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            lastReturned: carried
        )

        XCTAssertEqual(size, CGSize(width: 800, height: 600))
    }

    func testNoPixelSizeAndNoCarriedFrameMeansUnscaled() throws {
        let size = try resolveScreenshotPixelSize(
            snapshotPixelSize: nil,
            windowID: 7,
            windowBounds: CGRect(x: 0, y: 0, width: 400, height: 300),
            lastReturned: nil
        )

        XCTAssertNil(size)
    }

    func testCarriedFrameIsUsedWhenWindowIdentityAndSizeMatch() throws {
        let size = try resolveScreenshotPixelSize(
            snapshotPixelSize: nil,
            windowID: 7,
            windowBounds: CGRect(x: 30, y: 40, width: 400, height: 300),
            lastReturned: carriedFrame()
        )

        XCTAssertEqual(size, CGSize(width: 800, height: 600))
    }

    func testCarriedFrameFailsClosedWhenWindowSizeChanged() {
        XCTAssertThrowsError(
            try resolveScreenshotPixelSize(
                snapshotPixelSize: nil,
                windowID: 7,
                windowBounds: CGRect(x: 0, y: 0, width: 500, height: 300),
                lastReturned: carriedFrame()
            )
        ) { error in
            XCTAssertEqual(error.localizedDescription, screenshotFrameMismatchMessage)
        }
    }

    func testCarriedFrameFailsClosedWhenWindowIdentityChanged() {
        XCTAssertThrowsError(
            try resolveScreenshotPixelSize(
                snapshotPixelSize: nil,
                windowID: 8,
                windowBounds: CGRect(x: 0, y: 0, width: 400, height: 300),
                lastReturned: carriedFrame()
            )
        ) { error in
            XCTAssertEqual(error.localizedDescription, screenshotFrameMismatchMessage)
        }
    }

    // MARK: - Tool schema

    func testActionToolsExposeBooleanIncludeScreenshot() throws {
        let actionTools = ["click", "drag", "perform_secondary_action", "press_key", "scroll", "set_value", "type_text"]

        for name in actionTools {
            let tool = try XCTUnwrap(ToolDefinitions.all.first(where: { $0.name == name }), "missing tool \(name)")
            let properties = try XCTUnwrap(tool.inputSchema["properties"] as? [String: Any], "\(name) has no properties")
            let property = try XCTUnwrap(properties["include_screenshot"] as? [String: Any], "\(name) lacks include_screenshot")
            XCTAssertEqual(property["type"] as? String, "boolean", "\(name) include_screenshot type")
        }
    }

    func testReadOnlyToolsDoNotExposeIncludeScreenshot() throws {
        for name in ["get_app_state", "list_apps"] {
            let tool = try XCTUnwrap(ToolDefinitions.all.first(where: { $0.name == name }), "missing tool \(name)")
            let properties = tool.inputSchema["properties"] as? [String: Any] ?? [:]
            XCTAssertNil(properties["include_screenshot"], "\(name) must not expose include_screenshot")
        }
    }

    // MARK: - Dispatcher parsing

    func testDispatcherRejectsNonBooleanIncludeScreenshotBeforeResolvingApp() {
        let dispatcher = ComputerUseToolDispatcher(guard: MacSessionGuard(provider: PolicyTestUnlockedSessionProvider()))

        let result = dispatcher.callToolAsResult(
            name: "press_key",
            arguments: ["app": "NoSuchApp", "key": "a", "include_screenshot": "maybe"]
        )

        XCTAssertTrue(result.isError)
        XCTAssertTrue(
            result.primaryText?.contains("include_screenshot must be a boolean") == true,
            "unexpected text: \(result.primaryText ?? "nil")"
        )
    }

    // MARK: - Helpers

    private func carriedFrame() -> ReturnedScreenshotFrame {
        ReturnedScreenshotFrame(
            windowID: 7,
            windowSize: CGSize(width: 400, height: 300),
            pixelSize: CGSize(width: 800, height: 600)
        )
    }
}

private struct PolicyTestUnlockedSessionProvider: MacSessionStateProvider {
    func currentSnapshot() -> MacSessionSnapshot {
        MacSessionSnapshot(isLocked: false, isUnknown: false, rawKeysSeen: ["CGSSessionScreenIsLocked"])
    }
}
