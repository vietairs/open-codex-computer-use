import AppKit
import CoreGraphics
import XCTest
@testable import OpenComputerUseKit

/// Pins how a Stage Manager off-stage window is detected and what an agent sees for it: no capture, a note in the
/// state text, and a clear error for x/y input.
final class StageManagerOffStageWindowTests: XCTestCase {
    private let axFrame = CGRect(x: 310, y: 87, width: 1458, height: 1021)
    private let stripThumbnail = CGRect(x: 16, y: 515, width: 115, height: 129)

    // MARK: - Detection

    func testOnStageWindowWithEqualFramesIsNotOffStage() {
        let result = offStageWindow(windowID: 4344, accessibilityFrame: axFrame, isMinimized: false) { _ in self.axFrame }
        XCTAssertNil(result)
    }

    func testStripThumbnailFrameIsOffStage() {
        var requested: [CGWindowID] = []
        let result = offStageWindow(windowID: 4344, accessibilityFrame: axFrame, isMinimized: false) { id in
            requested.append(id)
            return self.stripThumbnail
        }
        XCTAssertEqual(result, OffStageWindow(windowID: 4344, accessibilityFrame: axFrame))
        XCTAssertEqual(requested, [4344], "the window-server frame must be read for the AX window's own id")
    }

    func testMinimizedWindowIsNotOffStageAndSkipsTheWindowServerRead() {
        var readWindowServer = false
        let result = offStageWindow(windowID: 4344, accessibilityFrame: axFrame, isMinimized: true) { _ in
            readWindowServer = true
            return self.stripThumbnail
        }
        XCTAssertNil(result)
        XCTAssertFalse(readWindowServer)
    }

    func testMissingWindowServerEntryIsNotOffStage() {
        XCTAssertNil(offStageWindow(windowID: 4344, accessibilityFrame: axFrame, isMinimized: false) { _ in nil })
    }

    func testMissingWindowIDOrAccessibilityFrameIsNotOffStage() {
        XCTAssertNil(offStageWindow(windowID: nil, accessibilityFrame: axFrame, isMinimized: false) { _ in self.stripThumbnail })
        XCTAssertNil(offStageWindow(windowID: 4344, accessibilityFrame: nil, isMinimized: false) { _ in self.stripThumbnail })
        XCTAssertNil(offStageWindow(windowID: 4344, accessibilityFrame: .zero, isMinimized: false) { _ in self.stripThumbnail })
    }

    func testAreaRatioThresholdBoundary() {
        let window = CGRect(x: 0, y: 0, width: 100, height: 100)
        let atThreshold = CGRect(x: 0, y: 0, width: 50, height: 100)
        let belowThreshold = CGRect(x: 0, y: 0, width: 49, height: 100)
        XCTAssertEqual(offStageWindowAreaRatioThreshold, 0.5)
        XCTAssertNil(offStageWindow(windowID: 1, accessibilityFrame: window, isMinimized: false) { _ in atThreshold })
        XCTAssertNotNil(offStageWindow(windowID: 1, accessibilityFrame: window, isMinimized: false) { _ in belowThreshold })
    }

    // MARK: - Capture

    func testOffStageWindowIsNeverCapturedWhateverThePolicy() {
        for policy in [SnapshotCapturePolicy.always, .whenTreeEmpty, .never] {
            XCTAssertEqual(windowImageCaptureTiming(policy: policy, isOnscreen: true, isOffStage: true), .skip)
            XCTAssertEqual(windowImageCaptureTiming(policy: policy, isOnscreen: false, isOffStage: true), .skip)
        }
    }

    // MARK: - State text

    func testOffStageNoteAppearsInEveryTextStyle() {
        let snapshot = makeSnapshot(isOffStage: true)
        for style in [SnapshotTextStyle.fullState, .actionResult, .compactActionable] {
            let lines = snapshot.renderedText(style: style).components(separatedBy: "\n")
            XCTAssertEqual(lines.filter { $0 == offStageWindowNote }.count, 1, "style \(style)")
            XCTAssertEqual(lines.firstIndex(of: offStageWindowNote), 2, "the note follows the Window line")
        }
    }

    func testOnStageSnapshotHasNoOffStageNote() {
        let text = makeSnapshot(isOffStage: false).renderedText(style: .fullState)
        XCTAssertFalse(text.contains("off stage"))
    }

    func testOffStageNoteTellsTheAgentWhatStillWorks() {
        XCTAssertTrue(offStageWindowNote.contains("Stage Manager"))
        XCTAssertTrue(offStageWindowNote.contains("no screenshot"))
        XCTAssertTrue(offStageWindowNote.contains("element_index actions still work"))
        XCTAssertTrue(offStageWindowNote.contains("x/y coordinates cannot be used"))
    }

    // MARK: - x/y input

    func testCoordinateInputIsRejectedOffStage() {
        XCTAssertThrowsError(try rejectCoordinateInputWhenOffStage(true)) { error in
            guard case let ComputerUseError.stateUnavailable(message) = error else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertEqual(message, offStageCoordinateInputMessage)
            XCTAssertTrue(message.contains("Stage Manager"))
            XCTAssertTrue(message.contains("element_index"))
        }
    }

    func testCoordinateInputIsAllowedOnStage() {
        XCTAssertNoThrow(try rejectCoordinateInputWhenOffStage(false))
    }

    // MARK: - Helpers

    private func makeSnapshot(isOffStage: Bool) -> AppSnapshot {
        let button = ElementRecord(
            index: 0,
            identifier: nil,
            element: nil,
            localFrame: CGRect(x: 10, y: 10, width: 80, height: 24),
            role: "button",
            rawActions: ["AXPress"],
            prettyActions: ["Press"]
        )
        return AppSnapshot(
            app: RunningAppDescriptor(
                name: "Mail",
                bundleIdentifier: "com.apple.mail",
                pid: 4242,
                runningApplication: NSRunningApplication.current
            ),
            windowTitle: "Inbox",
            windowBounds: axFrame,
            targetWindowID: 4344,
            targetWindowLayer: 0,
            screenshotPNGData: nil,
            mode: .accessibility,
            treeLines: ["0 button Search"],
            treeLineOffsets: [0: 0],
            focusedSummary: nil,
            focusedElement: nil,
            selectedText: nil,
            elements: [0: button],
            windowContentIsEmpty: false,
            isOffStage: isOffStage
        )
    }
}
