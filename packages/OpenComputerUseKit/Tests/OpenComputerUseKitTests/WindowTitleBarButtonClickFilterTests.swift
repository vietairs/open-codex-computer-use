import CoreGraphics
import XCTest
@testable import OpenComputerUseKit

/// An `auto` click on a window presses its smallest pressable descendant when the window itself has no press action.
/// The title-bar buttons are small and pressable, so they must never be picked on the caller's behalf.
final class WindowTitleBarButtonClickFilterTests: XCTestCase {
    private func candidate(subrole: String?, width: CGFloat = 14, role: String? = nil) -> ElementRecord {
        ElementRecord(
            index: -1,
            identifier: nil,
            element: nil,
            localFrame: CGRect(x: 0, y: 0, width: width, height: 16),
            role: role,
            subrole: subrole,
            rawActions: ["AXPress"],
            prettyActions: ["AXPress"]
        )
    }

    func testDropsCloseMinimizeZoomAndFullScreenButtons() {
        let chrome = ["AXCloseButton", "AXMinimizeButton", "AXZoomButton", "AXFullScreenButton"].map {
            candidate(subrole: $0)
        }
        XCTAssertTrue(excludingWindowTitleBarButtons(chrome).isEmpty)
    }

    func testKeepsOtherPressableDescendantsInOrder() {
        let send = candidate(subrole: nil, width: 40, role: "AXButton")
        let close = candidate(subrole: "AXCloseButton")
        let toolbarButton = candidate(subrole: "AXToolbarButton", width: 30)
        let search = candidate(subrole: "AXSearchField", width: 200)

        let kept = excludingWindowTitleBarButtons([send, close, toolbarButton, search])

        XCTAssertEqual(kept.count, 3)
        XCTAssertTrue(kept[0] === send)
        XCTAssertTrue(kept[1] === toolbarButton)
        XCTAssertTrue(kept[2] === search)
    }

    func testEmptyInputStaysEmpty() {
        XCTAssertTrue(excludingWindowTitleBarButtons([]).isEmpty)
    }
}
