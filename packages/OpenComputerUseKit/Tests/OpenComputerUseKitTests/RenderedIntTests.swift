import CoreGraphics
import Foundation
import XCTest
@testable import OpenComputerUseKit

/// Accessibility frames and caller coordinates can be NaN or infinite; `Int(_:)` traps on those and takes the shared
/// app agent down, so every displayed integer goes through `renderedInt`.
final class RenderedIntTests: XCTestCase {

    func testNonFiniteValuesRenderAsZero() {
        XCTAssertEqual(renderedInt(.nan), 0)
        XCTAssertEqual(renderedInt(.infinity), 0)
        XCTAssertEqual(renderedInt(-.infinity), 0)
    }

    func testOutOfRangeValuesClampToIntBounds() {
        XCTAssertEqual(renderedInt(1e30), Int.max)
        XCTAssertEqual(renderedInt(-1e30), Int.min)
        XCTAssertEqual(renderedInt(Double(Int.max)), Int.max, "2^63 is not representable and must clamp, not trap")
        XCTAssertEqual(renderedInt(Double(Int.min)), Int.min)
    }

    func testFiniteValuesTruncateTowardZeroLikeInt() {
        XCTAssertEqual(renderedInt(0), 0)
        XCTAssertEqual(renderedInt(12.9), 12)
        XCTAssertEqual(renderedInt(-12.9), -12)
        XCTAssertEqual(renderedInt(-0.5), 0)
        XCTAssertEqual(renderedInt(0.999), 0)
        XCTAssertEqual(renderedInt(-300), -300)
        XCTAssertEqual(renderedInt(CGFloat(42.7)), 42)
    }

    func testFrameTextMatchesIntTruncationForOrdinaryFrames() {
        let frame = CGRect(x: 10.9, y: -4.2, width: 300.5, height: 20.99)
        XCTAssertEqual(renderedFrameText(frame), "x=10, y=-4, w=300, h=20")
    }

    func testFrameTextDoesNotTrapOnNonFiniteOriginAndSize() {
        let nanOrigin = CGRect(x: CGFloat.nan, y: CGFloat.nan, width: 10, height: 20)
        XCTAssertEqual(renderedFrameText(nanOrigin), "x=0, y=0, w=10, h=20")

        let infiniteSize = CGRect(x: 5, y: 6, width: CGFloat.infinity, height: -CGFloat.infinity)
        XCTAssertEqual(renderedFrameText(infiniteSize), "x=5, y=6, w=0, h=0")

        let everythingBroken = CGRect(
            x: CGFloat.infinity,
            y: -CGFloat.infinity,
            width: CGFloat.nan,
            height: CGFloat(1e30)
        )
        XCTAssertEqual(renderedFrameText(everythingBroken), "x=0, y=0, w=0, h=\(Int.max)")
    }

    func testElementSearchFrameTextUsesTheSameSafeRendering() {
        let broken = CGRect(x: CGFloat.nan, y: 1, width: CGFloat.infinity, height: 2)
        XCTAssertEqual(elementSearchRenderedFrame(broken), "x=0, y=1, w=0, h=2")
    }
}
