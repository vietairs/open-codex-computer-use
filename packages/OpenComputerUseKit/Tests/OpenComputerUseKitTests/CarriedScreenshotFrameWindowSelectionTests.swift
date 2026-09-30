import CoreGraphics
import XCTest
@testable import OpenComputerUseKit

/// An x/y click reads its coordinates from the last screenshot returned to the caller. After a text-only action
/// result, the click is scaled by that carried frame only while the snapshot still targets the same window at the
/// same size. These tests pin the window selection that decides "same window" when a small non-modal window of the
/// app (Mail's search suggestions list, shown after its search field takes focus) appears in front of the
/// accessibility root window.
final class CarriedScreenshotFrameWindowSelectionTests: XCTestCase {
    // Geometry measured on Mail: the viewer window and the search suggestions list below its toolbar search field.
    private let viewer = candidate(4344, bounds: CGRect(x: 461, y: 131, width: 1_458, height: 1_021), frontToBackIndex: 2)
    private let suggestions = candidate(4438, bounds: CGRect(x: 1_586, y: 177, width: 350, height: 76), frontToBackIndex: 0)
    private let hiddenPhantom = candidate(
        4352, bounds: CGRect(x: 700, y: 447, width: 420, height: 632), frontToBackIndex: 1, isOnscreen: false
    )
    private let returnedPixelSize = CGSize(width: 1_280, height: 896)

    private static func candidate(
        _ windowID: CGWindowID,
        bounds: CGRect,
        frontToBackIndex: Int,
        isOnscreen: Bool = true
    ) -> WindowCaptureCandidate {
        WindowCaptureCandidate(
            windowID: windowID,
            layer: 0,
            bounds: bounds,
            title: nil,
            area: Int(bounds.width * bounds.height),
            frontToBackIndex: frontToBackIndex,
            isOnscreen: isOnscreen
        )
    }

    private func candidate(
        _ windowID: CGWindowID,
        bounds: CGRect,
        frontToBackIndex: Int,
        isOnscreen: Bool = true
    ) -> WindowCaptureCandidate {
        Self.candidate(windowID, bounds: bounds, frontToBackIndex: frontToBackIndex, isOnscreen: isOnscreen)
    }

    /// The frame recorded when get_app_state returned the viewer screenshot.
    private func frameReturnedWithViewerScreenshot() throws -> ReturnedScreenshotFrame {
        let selected = try XCTUnwrap(
            preferredWindowCaptureCandidate([hiddenPhantom, viewer], titleHint: nil, preferredWindowID: viewer.windowID)
        )
        return ReturnedScreenshotFrame(
            windowID: selected.windowID,
            windowSize: selected.bounds.size,
            pixelSize: returnedPixelSize
        )
    }

    func testNonModalWindowInFrontDoesNotReplaceAccessibilityRoot() {
        let selected = preferredWindowCaptureCandidate(
            [suggestions, hiddenPhantom, viewer],
            titleHint: nil,
            preferredWindowID: viewer.windowID,
            isNonModalAccessibilityWindow: { $0 == self.suggestions.windowID }
        )

        XCTAssertEqual(selected?.windowID, viewer.windowID)
    }

    /// The live sequence: get_app_state (screenshot of the viewer), element_index click on the search field
    /// (text-only result; the suggestions list is now in front), then x/y click read from the first screenshot.
    func testXYClickAfterTextOnlyResultKeepsCarriedFrameWhenSuggestionsListAppears() throws {
        let lastReturned = try frameReturnedWithViewerScreenshot()

        let afterElementClick = try XCTUnwrap(
            preferredWindowCaptureCandidate(
                [suggestions, hiddenPhantom, viewer],
                titleHint: nil,
                preferredWindowID: viewer.windowID,
                isNonModalAccessibilityWindow: { $0 == self.suggestions.windowID }
            )
        )

        let pixelSize = try resolveScreenshotPixelSize(
            snapshotPixelSize: nil,
            windowID: afterElementClick.windowID,
            windowBounds: afterElementClick.bounds,
            lastReturned: lastReturned
        )

        XCTAssertEqual(pixelSize, returnedPixelSize)
    }

    func testXYClickAfterTextOnlyResultStillFailsClosedWhenWindowIsResized() throws {
        let lastReturned = try frameReturnedWithViewerScreenshot()
        let resized = candidate(
            viewer.windowID, bounds: CGRect(x: 461, y: 131, width: 1_200, height: 1_021), frontToBackIndex: 2
        )
        let selected = try XCTUnwrap(
            preferredWindowCaptureCandidate(
                [suggestions, resized],
                titleHint: nil,
                preferredWindowID: viewer.windowID,
                isNonModalAccessibilityWindow: { $0 == self.suggestions.windowID }
            )
        )

        XCTAssertThrowsError(
            try resolveScreenshotPixelSize(
                snapshotPixelSize: nil,
                windowID: selected.windowID,
                windowBounds: selected.bounds,
                lastReturned: lastReturned
            )
        ) { error in
            XCTAssertEqual(error.localizedDescription, screenshotFrameMismatchMessage)
        }
    }

    /// A modal panel (or any window not known to be a non-modal window of the app) that appears in front still
    /// becomes the capture target, so an x/y click read from the older screenshot fails closed instead of landing on
    /// the panel at the wrong place.
    func testXYClickAfterTextOnlyResultFailsClosedWhenModalPanelAppears() throws {
        let lastReturned = try frameReturnedWithViewerScreenshot()
        let panel = candidate(5000, bounds: CGRect(x: 700, y: 200, width: 880, height: 448), frontToBackIndex: 0)

        let selected = try XCTUnwrap(
            preferredWindowCaptureCandidate(
                [panel, hiddenPhantom, viewer],
                titleHint: nil,
                preferredWindowID: viewer.windowID,
                isNonModalAccessibilityWindow: { _ in false }
            )
        )

        XCTAssertEqual(selected.windowID, panel.windowID)
        XCTAssertThrowsError(
            try resolveScreenshotPixelSize(
                snapshotPixelSize: nil,
                windowID: selected.windowID,
                windowBounds: selected.bounds,
                lastReturned: lastReturned
            )
        ) { error in
            XCTAssertEqual(error.localizedDescription, screenshotFrameMismatchMessage)
        }
    }

    func testModalPanelBehindNonModalWindowStillWins() {
        let panel = candidate(5000, bounds: CGRect(x: 700, y: 200, width: 880, height: 448), frontToBackIndex: 1)
        let suggestionsInFront = candidate(4438, bounds: suggestions.bounds, frontToBackIndex: 0)
        let viewerBehind = candidate(viewer.windowID, bounds: viewer.bounds, frontToBackIndex: 2)

        let selected = preferredWindowCaptureCandidate(
            [suggestionsInFront, panel, viewerBehind],
            titleHint: nil,
            preferredWindowID: viewer.windowID,
            isNonModalAccessibilityWindow: { $0 == suggestionsInFront.windowID }
        )

        XCTAssertEqual(selected?.windowID, panel.windowID)
    }

    func testNonModalCheckIsNotConsultedWhenRootIsFrontmost() {
        var consulted: [CGWindowID] = []
        let viewerInFront = candidate(viewer.windowID, bounds: viewer.bounds, frontToBackIndex: 0)
        let behind = candidate(4438, bounds: suggestions.bounds, frontToBackIndex: 1)

        let selected = preferredWindowCaptureCandidate(
            [viewerInFront, behind],
            titleHint: nil,
            preferredWindowID: viewer.windowID,
            isNonModalAccessibilityWindow: { consulted.append($0); return true }
        )

        XCTAssertEqual(selected?.windowID, viewer.windowID)
        XCTAssertEqual(consulted, [])
    }

    func testNonModalAccessibilityWindowIDsKeepsOnlyExplicitlyNonModalWindows() {
        let ids = nonModalAccessibilityWindowIDs([
            (windowID: 4438, isModal: false),
            (windowID: 5000, isModal: true),
            (windowID: 5001, isModal: nil),
            (windowID: nil, isModal: false),
        ])

        XCTAssertEqual(ids, [4438])
    }
}
