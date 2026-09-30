import CoreGraphics
import XCTest
@testable import OpenComputerUseKit

/// Pins the wall-clock cap on the blocking visual cursor travel. The recovered official timing stays
/// in the motion model for parity; only the overlay's duration is bounded.
final class CursorTravelCapTests: XCTestCase {
    func testRecoveredOfficialTravelTimeIsCappedToThreeTenthsOfASecond() {
        let capped = visualCursorTravelDuration(calibrated: OfficialCursorMotionModel.closeEnoughTime)
        XCTAssertEqual(capped, 0.3, accuracy: 1e-9)
    }

    func testTravelTimeBelowTheCapIsUnchanged() {
        XCTAssertEqual(visualCursorTravelDuration(calibrated: 0.2), 0.2, accuracy: 1e-9)
    }

    func testExplicitCapOverridesTheDefault() {
        XCTAssertEqual(visualCursorTravelDuration(calibrated: 5, cap: 0.5), 0.5, accuracy: 1e-9)
    }

    func testCapIsShorterThanTheRecoveredOfficialTime() {
        XCTAssertLessThan(visualCursorTravelDurationCap, OfficialCursorMotionModel.closeEnoughTime)
    }
}
