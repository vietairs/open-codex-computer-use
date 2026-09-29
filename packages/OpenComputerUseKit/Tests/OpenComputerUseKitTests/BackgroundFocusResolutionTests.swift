import ApplicationServices
import XCTest
@testable import OpenComputerUseKit

/// Pins how the focused element is found while the target app is in the background: from rendered nodes that report
/// AXFocused, and, inside a batch, from the pinned snapshot's elements re-read live.
final class BackgroundFocusResolutionTests: XCTestCase {
    private struct Candidate: Equatable {
        let name: String
        let role: String?
        let depth: Int
    }

    private func select(_ candidates: [Candidate]) -> Candidate? {
        selectBackgroundFocus(candidates, role: { $0.role }, depth: { $0.depth })
    }

    // MARK: - Snapshot fallback selection

    func testNoFocusedCandidatesSelectsNothing() {
        XCTAssertNil(select([]))
    }

    func testSingleFocusedTextFieldIsSelected() {
        let field = Candidate(name: "search", role: kAXTextFieldRole as String, depth: 6)
        XCTAssertEqual(select([field]), field)
    }

    func testWindowReportingFocusIsNeverTheTypingTarget() {
        let window = Candidate(name: "window", role: kAXWindowRole as String, depth: 0)
        XCTAssertNil(select([window]))

        let field = Candidate(name: "search", role: kAXTextFieldRole as String, depth: 4)
        XCTAssertEqual(select([window, field]), field)
    }

    func testContainerRolesAreSkipped() {
        let containers = [kAXApplicationRole, kAXSheetRole, kAXDrawerRole, kAXMenuBarRole].map {
            Candidate(name: $0 as String, role: $0 as String, depth: 9)
        }
        XCTAssertNil(select(containers))
    }

    func testDeepestFocusedControlWins() {
        let group = Candidate(name: "group", role: kAXGroupRole as String, depth: 3)
        let field = Candidate(name: "field", role: kAXTextFieldRole as String, depth: 5)
        XCTAssertEqual(select([group, field]), field)
        XCTAssertEqual(select([field, group]), field)
    }

    func testEqualDepthKeepsTreeOrder() {
        let first = Candidate(name: "first", role: kAXTextFieldRole as String, depth: 4)
        let second = Candidate(name: "second", role: kAXTextAreaRole as String, depth: 4)
        XCTAssertEqual(select([first, second]), first)
    }

    func testUnknownRoleIsStillACandidate() {
        let unknown = Candidate(name: "unknown", role: nil, depth: 2)
        XCTAssertEqual(select([unknown]), unknown)
    }

    // MARK: - Batch live probe order

    private func record(_ index: Int, pid: pid_t, role: String?, synthetic: Bool = false) -> ElementRecord {
        ElementRecord(
            index: index,
            identifier: nil,
            element: AXUIElementCreateApplication(pid),
            localFrame: nil,
            role: role,
            rawActions: [],
            prettyActions: [],
            isSyntheticText: synthetic
        )
    }

    private func pids(_ elements: [AXUIElement]) -> [pid_t] {
        elements.map { element in
            var pid: pid_t = 0
            AXUIElementGetPid(element, &pid)
            return pid
        }
    }

    func testProbeOrderStartsWithPinnedFocusThenTextEntriesByIndex() {
        let records = [
            record(9, pid: 909, role: kAXTextAreaRole as String),
            record(3, pid: 303, role: kAXTextFieldRole as String),
            record(5, pid: 505, role: kAXButtonRole as String),
            record(7, pid: 707, role: kAXComboBoxRole as String),
        ]

        let order = backgroundFocusProbeOrder(pinnedFocus: AXUIElementCreateApplication(101), records: records)

        XCTAssertEqual(pids(order), [101, 303, 707, 909])
    }

    func testProbeOrderSkipsNonTextSyntheticAndDuplicateElements() {
        let records = [
            record(1, pid: 303, role: kAXTextFieldRole as String),
            record(2, pid: 404, role: kAXTextFieldRole as String, synthetic: true),
            record(3, pid: 505, role: kAXStaticTextRole as String),
            record(4, pid: 606, role: nil),
        ]

        let order = backgroundFocusProbeOrder(pinnedFocus: AXUIElementCreateApplication(303), records: records)

        XCTAssertEqual(pids(order), [303])
    }

    func testProbeOrderWithoutPinnedFocusProbesTextEntriesOnly() {
        let order = backgroundFocusProbeOrder(
            pinnedFocus: nil,
            records: [record(2, pid: 202, role: "AXTextView"), record(1, pid: 111, role: kAXGroupRole as String)]
        )
        XCTAssertEqual(pids(order), [202])
    }

    func testProbeOrderIsEmptyWithNothingToProbe() {
        XCTAssertTrue(backgroundFocusProbeOrder(pinnedFocus: nil, records: []).isEmpty)
    }
}
