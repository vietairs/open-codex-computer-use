import XCTest
@testable import OpenComputerUseKit

/// Pins the single settle interval shared by every post-action wait and the batch inter-step wait.
final class PostActionSettleTests: XCTestCase {
    func testPostActionSettleIntervalIsOneNamedValue() {
        let interval: TimeInterval = postActionSettleInterval
        XCTAssertEqual(interval, 0.15, accuracy: 1e-9)
    }
}
