import XCTest
@testable import OpenComputerUseKit

private struct ClickFocusTestUnlockedSessionProvider: MacSessionStateProvider {
    func currentSnapshot() -> MacSessionSnapshot {
        MacSessionSnapshot(isLocked: false, isUnknown: false, rawKeysSeen: ["CGSSessionScreenIsLocked"])
    }
}

final class ClickTextEntryFocusTests: XCTestCase {
    // MARK: - Decision

    func testTextEntryRolesAreFocusedWhenSettable() {
        for role in ["AXTextField", "AXTextArea", "AXComboBox", "AXSecureTextField"] {
            XCTAssertTrue(shouldFocusTextEntryAfterClick(role: role, subrole: nil, focusSettable: true), role)
        }
    }

    func testTextEntrySubrolesAreFocusedEvenWithAnUnexpectedRole() {
        for subrole in ["AXSearchField", "AXSecureTextField"] {
            XCTAssertTrue(shouldFocusTextEntryAfterClick(role: "AXGroup", subrole: subrole, focusSettable: true), subrole)
        }
    }

    func testNonTextControlsAreNeverFocused() {
        for role in ["AXButton", "AXRow", "AXCell", "AXStaticText", "AXWindow"] {
            XCTAssertFalse(shouldFocusTextEntryAfterClick(role: role, subrole: nil, focusSettable: true), role)
        }
        XCTAssertFalse(shouldFocusTextEntryAfterClick(role: nil, subrole: nil, focusSettable: true))
    }

    func testTextEntryWithUnsettableFocusIsNotWritten() {
        XCTAssertFalse(shouldFocusTextEntryAfterClick(role: "AXTextField", subrole: "AXSearchField", focusSettable: false))
    }

    // MARK: - Runner

    func testRunnerWritesFocusOnSettableSearchField() {
        var subroleReads = 0
        var writes = 0
        let written = focusTextEntryAfterClick(
            role: "AXTextField",
            readSubrole: { subroleReads += 1; return "AXSearchField" },
            isFocusSettable: { true },
            setFocused: { writes += 1; return true }
        )

        XCTAssertTrue(written)
        XCTAssertEqual(writes, 1)
        // The role already settles it, so the subrole is not read.
        XCTAssertEqual(subroleReads, 0)
    }

    func testRunnerSkipsSettableCheckAndWriteForButtons() {
        var settableChecks = 0
        var writes = 0
        let written = focusTextEntryAfterClick(
            role: "AXButton",
            readSubrole: { nil },
            isFocusSettable: { settableChecks += 1; return true },
            setFocused: { writes += 1; return true }
        )

        XCTAssertFalse(written)
        XCTAssertEqual(settableChecks, 0)
        XCTAssertEqual(writes, 0)
    }

    func testRunnerUsesSubroleWhenRoleIsNotTextEntry() {
        var writes = 0
        let written = focusTextEntryAfterClick(
            role: nil,
            readSubrole: { "AXSearchField" },
            isFocusSettable: { true },
            setFocused: { writes += 1; return true }
        )

        XCTAssertTrue(written)
        XCTAssertEqual(writes, 1)
    }

    func testRunnerDoesNotWriteWhenFocusIsNotSettable() {
        var writes = 0
        let written = focusTextEntryAfterClick(
            role: "AXTextField",
            readSubrole: { nil },
            isFocusSettable: { false },
            setFocused: { writes += 1; return true }
        )

        XCTAssertFalse(written)
        XCTAssertEqual(writes, 0)
    }

    func testRefusedWriteIsReportedWithoutThrowing() {
        let written = focusTextEntryAfterClick(
            role: "AXTextArea",
            readSubrole: { nil },
            isFocusSettable: { true },
            setFocused: { false }
        )

        XCTAssertFalse(written)
    }

    // MARK: - set_value arguments

    private func makeDispatcher() -> ComputerUseToolDispatcher {
        ComputerUseToolDispatcher(guard: MacSessionGuard(provider: ClickFocusTestUnlockedSessionProvider()))
    }

    /// A blocked password-manager bundle id: app lookup refuses it before looking for, launching, or touching any
    /// app, so an accepted argument surfaces as that refusal instead of reaching a real app.
    private let refusedApp = "com.bitwarden.desktop"

    func testSetValueAcceptsEmptyStringToClearAField() {
        let result = makeDispatcher().callToolAsResult(
            name: "set_value",
            arguments: ["app": refusedApp, "element_index": "1", "value": ""]
        )

        XCTAssertTrue(result.isError)
        XCTAssertNotEqual(result.primaryText, "Missing required argument: value")
    }

    func testSetValueStillRejectsMissingValue() {
        let result = makeDispatcher().callToolAsResult(
            name: "set_value",
            arguments: ["app": refusedApp, "element_index": "1"]
        )

        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.primaryText, "Missing required argument: value")
    }

    func testSetValueRejectsNonStringValueAsMissing() {
        let result = makeDispatcher().callToolAsResult(
            name: "set_value",
            arguments: ["app": refusedApp, "element_index": "1", "value": 5]
        )

        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.primaryText, "Missing required argument: value")
    }

    func testBatchSetValueStepAcceptsEmptyString() throws {
        let steps = try makeDispatcher().parseBatchSteps([
            ["tool": "set_value", "args": ["element_index": "3", "value": ""]],
        ])

        XCTAssertEqual(steps, [.setValue(elementIndex: "3", value: "")])
    }

    func testBatchSetValueStepStillRejectsMissingValue() {
        XCTAssertThrowsError(
            try makeDispatcher().parseBatchSteps([
                ["tool": "set_value", "args": ["element_index": "3"]],
            ])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("Missing required argument: value"), "\(error)")
        }
    }
}
