import XCTest
@testable import OpenComputerUseKit

/// Pins the normative algorithm in
/// `plans/260923-0939-notarize-translate-decision-model/decision-model/phase-02-swift-candidate-pruning-and-labels.md`.
/// Written before `DecisionCandidates.swift` exists; every assertion here must fail (compile error or runtime
/// assertion) until that file is implemented to this exact contract.
final class DecisionCandidatesTests: XCTestCase {

    // MARK: - Fixture builders

    private static let compactHeaderLines = [
        "App=com.example (pid 1)",
        "Window: \"Sample\", App: Sample.",
    ]

    /// Builds a full compact-view text: the 2 standard header lines, the "Compact actionable view: n of n …" line,
    /// then one row per string in `rows` (each already in "<index> <rowText>" form).
    private func compactText(rows: [String]) -> String {
        let header = "Compact actionable view: \(rows.count) of \(rows.count) elements, screenshot omitted. "
            + "element_index values match the full tree; re-run without compact for full context."
        return (Self.compactHeaderLines + [header] + rows).joined(separator: "\n")
    }

    /// Builds a full-tree text: the 2 standard header lines, then whatever tree lines are supplied. With no tree
    /// lines, `menuBarStartIndex` must be `nil`, so this doubles as the "no menu bar in play" fixture for tests
    /// that only exercise a single prune rule.
    private func fullText(_ treeLines: [String] = []) -> String {
        (Self.compactHeaderLines + treeLines).joined(separator: "\n")
    }

    private func build(
        goal: String,
        full: String? = nil,
        compactRows rows: [String],
        maxPages: Int = DecisionCandidateBuilder.defaultMaxPages
    ) -> DecisionCandidateSet {
        DecisionCandidateBuilder.build(
            goal: goal,
            renderedFull: full ?? fullText(),
            renderedCompact: compactText(rows: rows),
            maxPages: maxPages
        )
    }

    // MARK: - labelAlphabet / defaultMaxPages

    func testLabelAlphabetIsFiftyTwoUniqueAscendingLetters() {
        let alphabet = DecisionCandidateBuilder.labelAlphabet
        XCTAssertEqual(alphabet.count, 52)
        XCTAssertEqual(Set(alphabet).count, 52)
        XCTAssertEqual(alphabet.first, "A")
        XCTAssertEqual(alphabet[25], "Z")
        XCTAssertEqual(alphabet[26], "a")
        XCTAssertEqual(alphabet.last, "z")
    }

    /// Amendment (plan validation, 2026-09-23, binding): K11 stage-2 paging is cut for v1, so the default is 1
    /// page, not the 4 written in the phase file's Signature comment. Overflow beyond that is reported as the
    /// `.overflow` prune cause (see `testBuildOverflowsBeyondMaxPagesAndReportsOverflow`).
    func testDefaultMaxPagesIsOnePerV1Amendment() {
        XCTAssertEqual(DecisionCandidateBuilder.defaultMaxPages, 1)
    }

    // MARK: - parseCompactRows

    func testParseCompactRowsExtractsIndexRowTextAndFocus() {
        let text = [
            "App=com.example (pid 1)",
            "Window: \"Sample\", App: Sample.",
            "Compact actionable view: 2 of 4 elements, screenshot omitted. element_index values match the full "
                + "tree; re-run without compact for full context.",
            "1 button Send Secondary Actions: Press",
            "3 text field (settable, string) Message (focused)",
            "",
            "The focused UI element is 3 text field.",
        ].joined(separator: "\n")

        let candidates = DecisionCandidateBuilder.parseCompactRows(text)

        XCTAssertEqual(candidates.map(\.elementIndex), [1, 3])
        XCTAssertFalse(candidates[0].isFocused)
        XCTAssertEqual(candidates[0].rowText, "button Send Secondary Actions: Press")
        XCTAssertTrue(candidates[1].isFocused)
        XCTAssertEqual(candidates[1].rowText, "text field (settable, string) Message")
    }

    func testParseCompactRowsReturnsEmptyForNoActionableMessage() {
        let text = [
            "App=com.example (pid 1)",
            "Window: \"Sample\", App: Sample.",
            "(no actionable elements found; re-run without compact for the full tree)",
        ].joined(separator: "\n")

        XCTAssertEqual(DecisionCandidateBuilder.parseCompactRows(text), [])
    }

    func testParseCompactRowsKeepsSpanTextInRowText() {
        let candidates = DecisionCandidateBuilder.parseCompactRows(
            compactText(rows: ["7 static text Label — some span"])
        )

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].rowText, "static text Label — some span")
    }

    func testParseCompactRowsDetectsFixtureInlineFocusMarker() {
        let candidates = DecisionCandidateBuilder.parseCompactRows(
            compactText(rows: ["2 button Increment (focused) ID: fixture-increment Frame: 0,0 10x10"])
        )

        XCTAssertEqual(candidates.count, 1)
        XCTAssertTrue(candidates[0].isFocused)
    }

    // MARK: - disabled rule

    func testPruneRuleDisabledDropsWhenParenGroupIsAllTraitTokens() {
        let set = build(
            goal: "do something unrelated",
            compactRows: [
                "5 button (disabled) Save",
                "6 button Save (disabled draft)",
                "7 button (disabled) Cancel (focused)",
            ]
        )

        XCTAssertEqual(set.dropped[5], .disabled)
        XCTAssertNil(set.dropped[6], "a paren group holding a non-trait token must not match")
        XCTAssertNil(set.dropped[7], "a focused candidate is never dropped, even by the disabled rule")
        XCTAssertTrue(set.offeredIndices.contains(6))
        XCTAssertTrue(set.offeredIndices.contains(7))
    }

    // MARK: - menuBarStartIndex

    func testMenuBarStartIndexFindsRealMenuBarNode() {
        let text = fullText([
            "1 window",
            "\t2 toolbar",
            "3 menu bar",
            "\t4 File",
            "\t5 Edit",
        ])

        XCTAssertEqual(DecisionCandidateBuilder.menuBarStartIndex(renderedFull: text), 3)
    }

    func testMenuBarStartIndexFindsElidedMenuBar() {
        let text = fullText([
            "1 window",
            "\t2 toolbar",
            "3 File",
            "4 Edit",
        ])

        XCTAssertEqual(DecisionCandidateBuilder.menuBarStartIndex(renderedFull: text), 3)
    }

    func testMenuBarStartIndexIsNilWhenTreeIsTruncatedAtDepthTwo() {
        let text = fullText([
            "1 window",
            "\t2 toolbar",
            "\t\t3 button",
        ])

        XCTAssertNil(DecisionCandidateBuilder.menuBarStartIndex(renderedFull: text))
    }

    func testMenuBarStartIndexIsNilForFlatTreeWithElidedRoot() {
        let text = fullText([
            "1 button A",
            "2 button B",
            "3 button C",
        ])

        XCTAssertNil(DecisionCandidateBuilder.menuBarStartIndex(renderedFull: text))
    }

    func testMenuBarStartIndexIsNilForFixtureFourSpaceIndentSingleRoot() {
        let text = fullText([
            "1 window",
            "    2 child",
            "    3 sibling",
        ])

        XCTAssertNil(DecisionCandidateBuilder.menuBarStartIndex(renderedFull: text))
    }

    func testMenuBarStartIndexIgnoresNonSequentialDepthZeroSpanLine() {
        let text = fullText([
            "1 window",
            "7 KB",
            "\t2 toolbar",
            "3 menu bar",
            "\t4 File",
            "\t5 Edit",
        ])

        XCTAssertEqual(DecisionCandidateBuilder.menuBarStartIndex(renderedFull: text), 3)
    }

    // MARK: - menu_bar rule

    func testPruneRuleMenuBarDropsOnlyWhenGoalDoesNotMentionMenuOrItsContents() {
        let full = fullText([
            "1 window",
            "\t2 toolbar",
            "3 File",
            "4 Edit",
        ])
        let rows = ["3 File", "4 Edit"]

        let clickSave = build(goal: "click Save", full: full, compactRows: rows)
        XCTAssertEqual(clickSave.dropped[3], .menuBar)
        XCTAssertEqual(clickSave.dropped[4], .menuBar)

        let renameFile = build(goal: "rename the file", full: full, compactRows: rows)
        XCTAssertNil(renameFile.dropped[3], "goal mentions a word appearing in the menu-bar region, so it stays")
        XCTAssertNil(renameFile.dropped[4])

        let openEditMenu = build(goal: "open the Edit menu", full: full, compactRows: rows)
        XCTAssertNil(openEditMenu.dropped[3], "goal says \"menu\", the reserved word, so the rule never fires")
        XCTAssertNil(openEditMenu.dropped[4])
    }

    // MARK: - scroll_bar_part rule

    func testPruneRuleScrollBarPartDropsKnownScrollPartsOnly() {
        let set = build(
            goal: "do something unrelated",
            compactRows: [
                "1 scroll bar",
                "2 value indicator",
                "3 increment page",
                "4 scroll area",
            ]
        )

        XCTAssertEqual(set.dropped[1], .scrollBarPart)
        XCTAssertEqual(set.dropped[2], .scrollBarPart)
        XCTAssertEqual(set.dropped[3], .scrollBarPart)
        XCTAssertNil(set.dropped[4], "\"scroll area\" is not one of the named scroll-bar-part role phrases")
    }

    // MARK: - window_chrome rule

    func testPruneRuleWindowChromeDropsCloseButtonUnlessGoalMentionsClosing() {
        let unrelated = build(goal: "save the report", compactRows: ["5 close button"])
        XCTAssertEqual(unrelated.dropped[5], .windowChrome)

        let closing = build(goal: "close this window", compactRows: ["5 close button"])
        XCTAssertNil(closing.dropped[5])
    }

    // MARK: - duplicate_close rule

    func testPruneRuleDuplicateCloseDropsRepeatedCloseRowsUnlessGoalSaysClose() {
        let rows = [
            "1 button Close tab",
            "2 button Close tab",
            "3 button Close tab",
            "4 button Close",
        ]

        let openSettings = build(goal: "open settings", compactRows: rows)
        XCTAssertEqual(openSettings.dropped[1], .duplicateClose)
        XCTAssertEqual(openSettings.dropped[2], .duplicateClose)
        XCTAssertEqual(openSettings.dropped[3], .duplicateClose)
        XCTAssertNil(openSettings.dropped[4], "a single non-duplicated close row is kept")

        let closeDocsTab = build(goal: "close the docs tab", compactRows: rows)
        XCTAssertNil(closeDocsTab.dropped[1])
        XCTAssertNil(closeDocsTab.dropped[2])
        XCTAssertNil(closeDocsTab.dropped[3])
        XCTAssertNil(closeDocsTab.dropped[4])
    }

    // MARK: - ranking, paging, labels

    private func rankingFixtureRows() -> [String] {
        (1...120).map { i in
            i == 90 ? "\(i) button Export PDF" : "\(i) button Item \(i)"
        }
    }

    func testBuildRanksAndPagesWithMaxPagesFour() {
        let set = build(goal: "export as pdf", compactRows: rankingFixtureRows(), maxPages: 4)

        XCTAssertEqual(set.pages.count, 3)
        XCTAssertEqual(set.pages.map { $0.candidates.count }, [52, 52, 16])
        XCTAssertTrue(set.pages[0].candidates.contains { $0.elementIndex == 90 })
        XCTAssertEqual(set.pages[0].candidates.map(\.elementIndex), set.pages[0].candidates.map(\.elementIndex).sorted())
        XCTAssertEqual(set.pages[0].labels, Array(DecisionCandidateBuilder.labelAlphabet.prefix(52)))
    }

    func testBuildOverflowsBeyondMaxPagesAndReportsOverflow() {
        let set = build(goal: "export as pdf", compactRows: rankingFixtureRows(), maxPages: 1)

        XCTAssertEqual(set.pages.count, 1)
        XCTAssertEqual(set.pages[0].candidates.count, 52)
        XCTAssertEqual(set.dropped.values.filter { $0 == .overflow }.count, 68)
        XCTAssertTrue(set.offeredIndices.contains(90))
        XCTAssertNil(set.dropped[90])
    }

    // MARK: - determinism and offeredIndices invariants

    func testBuildIsDeterministicForIdenticalInputs() {
        let rows = rankingFixtureRows()
        let first = build(goal: "export as pdf", compactRows: rows, maxPages: 4)
        let second = build(goal: "export as pdf", compactRows: rows, maxPages: 4)

        XCTAssertEqual(first, second)
    }

    func testOfferedIndicesInvariantsHoldAgainstDroppedAndActionableCount() {
        let set = build(
            goal: "do something unrelated",
            compactRows: [
                "1 button (disabled) X",
                "2 button Y",
                "3 button Z",
            ]
        )

        let offered = Set(set.offeredIndices)
        XCTAssertEqual(set.offeredIndices, set.offeredIndices.sorted())
        XCTAssertTrue(offered.isDisjoint(with: Set(set.dropped.keys)))
        XCTAssertEqual(set.offeredIndices.count + set.dropped.count, set.actionableCount)
        XCTAssertEqual(set.actionableCount, 3)
    }
}
