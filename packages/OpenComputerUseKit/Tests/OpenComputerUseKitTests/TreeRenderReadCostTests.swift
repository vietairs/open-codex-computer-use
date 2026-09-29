import ApplicationServices
import XCTest
@testable import OpenComputerUseKit

/// Renders a fake accessibility tree through the real tree walk. The rendered text and element numbering are pinned
/// byte for byte, and the number of accessibility round trips the walk makes is pinned per node, so a change that
/// reads fewer attributes cannot silently change what the snapshot says.
final class TreeRenderReadCostTests: XCTestCase {
    struct Fixture {
        let tree: FakeAccessibilityTree
        let menuBar: AXUIElement
        let table: AXUIElement
        let rows: [AXUIElement]
        /// Per row: the cells and every node below them that row-text flattening reads (depth 0-3).
        let rowTextNodes: [[AXUIElement]]
        /// Per row: a static text at depth 4 below a cell, past the flattening depth.
        let rowTooDeepTexts: [AXUIElement]
        let window: AXUIElement
        let reply: AXUIElement
        let checkbox: AXUIElement
        let menuItems: [AXUIElement]
    }

    struct Rendered: Equatable {
        let lines: [String]
        let records: [String]
        let focusCandidates: [String]
    }

    static let windowBounds = CGRect(x: 0, y: 0, width: 1_000, height: 800)
    static let rowCount = 40
    static let selectedRow = 5
    /// Rows are 15 points tall from y=70 and the table starts at y=100, so rows 2 through 27 intersect it.
    static let firstVisibleRow = 2

    /// A Mail-like window: toolbar with a search field, a message table with more visible rows than the row cap and
    /// one selected row, generic text groups (one with a link), a checkbox, a web area, a list, and a menu bar.
    static func makeFixture() -> Fixture {
        let tree = FakeAccessibilityTree()

        let searchField = tree.node(
            kAXTextFieldRole,
            [kAXSubroleAttribute: kAXSearchFieldSubrole, "AXPlaceholderValue": "Search", kAXFocusedAttribute: true],
            frame: CGRect(x: 700, y: 10, width: 250, height: 30),
            actions: [kAXConfirmAction],
            settable: [kAXValueAttribute, kAXFocusedAttribute]
        )
        let reply = tree.node(
            kAXButtonRole,
            [kAXDescriptionAttribute: "Reply", kAXHelpAttribute: "Reply to the message"],
            frame: CGRect(x: 10, y: 10, width: 40, height: 30),
            actions: [kAXPressAction]
        )
        let toolbar = tree.node(kAXToolbarRole, frame: CGRect(x: 0, y: 0, width: 1_000, height: 50), children: [reply, searchField])

        var rows: [AXUIElement] = []
        var rowTextNodes: [[AXUIElement]] = []
        var rowTooDeepTexts: [AXUIElement] = []
        for index in 0..<rowCount {
            let sender = tree.node(kAXStaticTextRole, [kAXValueAttribute: "Sender \(index)"])
            let subject = tree.node(kAXStaticTextRole, [kAXValueAttribute: "Subject \(index)\nsecond line"])
            let tooDeep = tree.node(kAXStaticTextRole, [kAXValueAttribute: "beyond the flatten depth \(index)"])
            let deep3 = tree.node(kAXGroupRole, children: [tooDeep])
            let deep2 = tree.node(kAXGroupRole, children: [deep3])
            let unread = tree.node(kAXImageRole, [kAXDescriptionAttribute: "Unread"])
            let subjectGroup = tree.node(kAXGroupRole, children: [subject, unread, deep2])
            let date = tree.node(kAXStaticTextRole, [kAXValueAttribute: "Yesterday"])
            let flag = tree.node(kAXTextFieldRole, [kAXTitleAttribute: "Flagged"])
            let duplicate = tree.node(kAXStaticTextRole, [kAXValueAttribute: "Sender \(index)"])
            let cell1 = tree.node(kAXCellRole, children: [sender, subjectGroup])
            let cell2 = tree.node(kAXCellRole, children: [date, flag, duplicate])
            let row = tree.node(
                kAXRowRole,
                [kAXSelectedAttribute: index == selectedRow],
                frame: CGRect(x: 0, y: 70 + CGFloat(index) * 15, width: 700, height: 15),
                children: [cell1, cell2],
                actions: index.isMultiple(of: 3) ? [kAXShowMenuAction] : []
            )
            rows.append(row)
            rowTextNodes.append([cell1, cell2, sender, subjectGroup, subject, unread, deep2, deep3, date, flag, duplicate])
            rowTooDeepTexts.append(tooDeep)
        }
        let table = tree.node(
            kAXTableRole,
            [kAXRowsAttribute: rows, kAXDescriptionAttribute: "Messages"],
            frame: CGRect(x: 0, y: 100, width: 700, height: 400),
            children: rows
        )
        let scroll = tree.node(kAXScrollAreaRole, frame: CGRect(x: 0, y: 100, width: 700, height: 400), children: [table])

        let hello = tree.node(kAXStaticTextRole, [kAXValueAttribute: "Hello"])
        let world = tree.node(kAXStaticTextRole, [kAXValueAttribute: "World"])
        let linkText = tree.node(kAXStaticTextRole, [kAXValueAttribute: "Example"])
        let link = tree.node("AXLink", [kAXURLAttribute: URL(string: "https://example.com/a")!], children: [linkText])
        let summaryGroup = tree.node(
            kAXGroupRole,
            frame: CGRect(x: 720, y: 100, width: 260, height: 80),
            children: [hello, world, link]
        )

        let cardText = tree.node(kAXStaticTextRole, [kAXValueAttribute: "Card title"])
        let cardLinkText = tree.node(kAXStaticTextRole, [kAXValueAttribute: "Open"])
        let cardLink = tree.node("AXLink", [kAXURLAttribute: URL(string: "https://example.com/card")!], children: [cardLinkText])
        let card = tree.node(
            kAXGroupRole,
            frame: CGRect(x: 720, y: 200, width: 260, height: 60),
            children: [cardText, cardLink],
            actions: [kAXPressAction]
        )

        let checkbox = tree.node(
            kAXCheckBoxRole,
            [kAXTitleAttribute: "Remember", kAXValueAttribute: NSNumber(value: 1)],
            frame: CGRect(x: 720, y: 300, width: 120, height: 20),
            actions: [kAXPressAction]
        )

        let paragraph = tree.node(kAXStaticTextRole, [kAXValueAttribute: "Paragraph text"])
        let docsText = tree.node(kAXStaticTextRole, [kAXValueAttribute: "Docs"])
        let docsLink = tree.node(
            "AXLink",
            [kAXURLAttribute: URL(string: "https://example.com/docs")!],
            frame: CGRect(x: 730, y: 420, width: 60, height: 20),
            children: [docsText],
            actions: [kAXPressAction]
        )
        let webGroup = tree.node(kAXGroupRole, children: [docsLink])
        let webArea = tree.node(
            "AXWebArea",
            [kAXDescriptionAttribute: "Message body"],
            frame: CGRect(x: 720, y: 400, width: 260, height: 200),
            children: [webGroup, paragraph]
        )

        let visibleItems = (0..<3).map { tree.node(kAXStaticTextRole, [kAXValueAttribute: "Mailbox \($0)"]) }
        let hiddenItem = tree.node(kAXStaticTextRole, [kAXValueAttribute: "Hidden mailbox"])
        let list = tree.node(
            kAXListRole,
            ["AXVisibleChildren": visibleItems],
            frame: CGRect(x: 0, y: 520, width: 200, height: 200),
            children: visibleItems + [hiddenItem]
        )

        let window = tree.node(
            kAXWindowRole,
            [kAXTitleAttribute: "Inbox", kAXSubroleAttribute: kAXStandardWindowSubrole],
            frame: windowBounds,
            children: [toolbar, scroll, summaryGroup, card, checkbox, webArea, list]
        )

        let menuItems = ["Apple", "Mail", "File", "Edit"].map {
            tree.node(kAXMenuBarItemRole, [kAXTitleAttribute: $0], actions: [kAXPressAction, kAXCancelAction])
        }
        let menuBar = tree.node(kAXMenuBarRole, children: menuItems)

        return Fixture(
            tree: tree,
            menuBar: menuBar,
            table: table,
            rows: rows,
            rowTextNodes: rowTextNodes,
            rowTooDeepTexts: rowTooDeepTexts,
            window: window,
            reply: reply,
            checkbox: checkbox,
            menuItems: menuItems
        )
    }

    /// Walks the window, then the menu bar, the way a snapshot build does.
    static func render(_ fixture: Fixture) -> Rendered {
        fixture.tree.serving {
            var renderer = TreeRenderer(
                context: RenderContext(
                    windowBounds: windowBounds,
                    focusedElement: nil,
                    textLimit: .defaults,
                    treeLimits: .defaults
                )
            )
            renderer.render(fixture.window)
            renderer.collectsFocusCandidates = false
            renderer.render(fixture.menuBar)

            let records = renderer.records.keys.sorted().map { index -> String in
                let record = renderer.records[index]!
                let frame = record.localFrame.map { "\($0.origin.x),\($0.origin.y),\($0.width),\($0.height)" } ?? "-"
                return "\(index) role=\(record.role ?? "-") id=\(record.identifier ?? "-") frame=\(frame)"
                    + " raw=\(record.rawActions) pretty=\(record.prettyActions) synthetic=\(record.isSyntheticText)"
            }
            return Rendered(
                lines: renderer.buffer.lines,
                records: records,
                focusCandidates: renderer.focusCandidates.map { "\($0.depth) \($0.role) \($0.lineBody)" }
            )
        }
    }

    func testRenderedTreeMatchesGolden() {
        let rendered = Self.render(Self.makeFixture())

        XCTAssertEqual(rendered.lines.joined(separator: "\n"), Self.goldenLines)
        XCTAssertEqual(rendered.records.joined(separator: "\n"), Self.goldenRecords)
        XCTAssertEqual(rendered.focusCandidates, Self.goldenFocusCandidates)
    }

    /// The batched reads must say exactly what one-attribute-at-a-time reads say.
    func testBatchedReadsRenderTheSameTreeAsSingleReads() {
        let batched = Self.makeFixture()
        let single = Self.makeFixture()
        single.tree.supportsMultipleAttributeReads = false

        XCTAssertEqual(Self.render(batched), Self.render(single))
    }

    /// The whole fixture walk. It made 1836 round trips when every attribute outside the render prefetch was read
    /// one at a time; a change here means the walk reads more or less than before, so check it on purpose.
    func testWalkRoundTripCountIsPinned() {
        let fixture = Self.makeFixture()
        _ = Self.render(fixture)

        XCTAssertEqual(fixture.tree.totalRoundTrips, 468)
    }

    /// A rendered node costs its attribute batch, its action names, and the value-settable check: title, role
    /// description, placeholder and child lists ride in the batch. A menu bar item's title is also read once more,
    /// before it is rendered, to leave out the Apple menu.
    func testRenderedNodeCostsThreeRoundTrips() {
        let fixture = Self.makeFixture()
        _ = Self.render(fixture)

        let expected: [FakeAccessibilityTree.Call: Int] = [.multiple: 1, .actions: 1, .settable(kAXValueAttribute): 1]
        for node in [fixture.window, fixture.reply, fixture.checkbox] {
            XCTAssertEqual(fixture.tree.calls(on: node), expected)
        }
        var menuItemExpected = expected
        menuItemExpected[.single(kAXTitleAttribute)] = 1
        for node in fixture.menuItems.dropFirst() {
            XCTAssertEqual(fixture.tree.calls(on: node), menuItemExpected)
        }
        XCTAssertEqual(fixture.tree.calls(on: fixture.menuItems[0]), [.single(kAXTitleAttribute): 1])
    }

    /// Flattening a row's text reads each node below its cells in one batch, and nothing past the flattening depth.
    func testRowTextFlatteningReadsEachNodeOnce() {
        let fixture = Self.makeFixture()
        _ = Self.render(fixture)

        for row in Self.firstVisibleRow..<(Self.firstVisibleRow + 20) where row != Self.selectedRow {
            for node in fixture.rowTextNodes[row] {
                XCTAssertEqual(fixture.tree.calls(on: node), [.multiple: 1], "row \(row)")
            }
            XCTAssertEqual(fixture.tree.calls(on: fixture.rowTooDeepTexts[row]), [:], "row \(row)")
        }
    }

    /// Only the first 20 visible rows are kept, so the rows after them are never read at all.
    func testRowsAfterTheVisibleRowCapAreNeverRead() {
        let fixture = Self.makeFixture()
        _ = Self.render(fixture)

        for row in (Self.firstVisibleRow + 20)..<Self.rowCount {
            XCTAssertEqual(fixture.tree.totalCalls(on: fixture.rows[row]), 0, "row \(row)")
            for node in fixture.rowTextNodes[row] {
                XCTAssertEqual(fixture.tree.totalCalls(on: node), 0, "row \(row)")
            }
        }
        for row in 0..<Self.firstVisibleRow {
            XCTAssertEqual(fixture.tree.calls(on: fixture.rows[row]), [.multiple: 1], "row \(row)")
        }
    }

    /// Nothing is cached across walks: a second walk reads the tree again and sees a changed value.
    func testSecondWalkReadsTheTreeAgain() {
        let fixture = Self.makeFixture()
        let first = Self.render(fixture)
        let firstRoundTrips = fixture.tree.totalRoundTrips
        fixture.tree.resetCounts()
        fixture.tree.setValue("Changed sender", attribute: kAXValueAttribute, of: fixture.rowTextNodes[3][2])

        let second = Self.render(fixture)

        XCTAssertEqual(fixture.tree.totalRoundTrips, firstRoundTrips)
        XCTAssertFalse(first.lines.contains { $0.contains("Changed sender") })
        XCTAssertTrue(first.lines.contains("\t\t\t7 row Sender 3"))
        XCTAssertTrue(second.lines.contains("\t\t\t7 row Changed sender"))
    }

    static let goldenFocusCandidates = [#"2 AXTextField 3 text field (settable) Placeholder: Search"#]
}

// Captured from the tree walk before its reads were batched; the batched walk must reproduce it byte for byte.
extension TreeRenderReadCostTests {
    static let goldenLines = #"""
0 standard window Inbox
	1 toolbar
		2 button Reply Help: Reply to the message
		3 text field (settable) Placeholder: Search
	4 scroll area
		5 table Description: Messages
			6 row Sender 2
Subject 2\nsecond line
Yesterday
Flagged
			7 row Sender 3
Subject 3\nsecond line
Yesterday
Flagged
			8 row Sender 4
Subject 4\nsecond line
Yesterday
Flagged
			9 row (selected) Sender 5
				10 cell
					11 static text Sender 5
					12 container
						13 text Subject 5\nsecond line beyond the flatten depth 5
						14 image Unread
				15 cell
					16 static text Yesterday
					17 text field Flagged
					18 static text Sender 5
			19 row Sender 6
Subject 6\nsecond line
Yesterday
Flagged
			20 row Sender 7
Subject 7\nsecond line
Yesterday
Flagged
			21 row Sender 8
Subject 8\nsecond line
Yesterday
Flagged
			22 row Sender 9
Subject 9\nsecond line
Yesterday
Flagged
			23 row Sender 10
Subject 10\nsecond line
Yesterday
Flagged
			24 row Sender 11
Subject 11\nsecond line
Yesterday
Flagged
			25 row Sender 12
Subject 12\nsecond line
Yesterday
Flagged
			26 row Sender 13
Subject 13\nsecond line
Yesterday
Flagged
			27 row Sender 14
Subject 14\nsecond line
Yesterday
Flagged
			28 row Sender 15
Subject 15\nsecond line
Yesterday
Flagged
			29 row Sender 16
Subject 16\nsecond line
Yesterday
Flagged
			30 row Sender 17
Subject 17\nsecond line
Yesterday
Flagged
			31 row Sender 18
Subject 18\nsecond line
Yesterday
Flagged
			32 row Sender 19
Subject 19\nsecond line
Yesterday
Flagged
			33 row Sender 20
Subject 20\nsecond line
Yesterday
Flagged
			34 row Sender 21
Subject 21\nsecond line
Yesterday
Flagged
	35 container Hello World [Example](https://example.com/a)
	36 static text Card title
	37 link
		38 static text Open
	39 check box Remember Value: on
	40 HTML 内容 Message body
		41 link
			42 static text Docs
		43 static text Paragraph text
	44 list
		45 static text Mailbox 0
		46 static text Mailbox 1
		47 static text Mailbox 2
48 menu bar
	49 Mail
	50 File
	51 Edit
"""#

    static let goldenRecords = #"""
0 role=AXWindow id=- frame=0.0,0.0,1000.0,800.0 raw=[] pretty=[] synthetic=false
1 role=AXToolbar id=- frame=0.0,0.0,1000.0,50.0 raw=[] pretty=[] synthetic=false
2 role=AXButton id=- frame=10.0,10.0,40.0,30.0 raw=["AXPress"] pretty=[] synthetic=false
3 role=AXTextField id=- frame=700.0,10.0,250.0,30.0 raw=["AXConfirm"] pretty=[] synthetic=false
4 role=AXScrollArea id=- frame=0.0,100.0,700.0,400.0 raw=[] pretty=[] synthetic=false
5 role=AXTable id=- frame=0.0,100.0,700.0,400.0 raw=[] pretty=[] synthetic=false
6 role=AXRow id=- frame=0.0,100.0,700.0,15.0 raw=[] pretty=[] synthetic=false
7 role=AXRow id=- frame=0.0,115.0,700.0,15.0 raw=["AXShowMenu"] pretty=[] synthetic=false
8 role=AXRow id=- frame=0.0,130.0,700.0,15.0 raw=[] pretty=[] synthetic=false
9 role=AXRow id=- frame=0.0,145.0,700.0,15.0 raw=[] pretty=[] synthetic=false
10 role=AXCell id=- frame=- raw=[] pretty=[] synthetic=false
11 role=AXStaticText id=- frame=- raw=[] pretty=[] synthetic=false
12 role=AXGroup id=- frame=- raw=[] pretty=[] synthetic=false
13 role=- id=- frame=- raw=[] pretty=[] synthetic=true
14 role=AXImage id=- frame=- raw=[] pretty=[] synthetic=false
15 role=AXCell id=- frame=- raw=[] pretty=[] synthetic=false
16 role=AXStaticText id=- frame=- raw=[] pretty=[] synthetic=false
17 role=AXTextField id=- frame=- raw=[] pretty=[] synthetic=false
18 role=AXStaticText id=- frame=- raw=[] pretty=[] synthetic=false
19 role=AXRow id=- frame=0.0,160.0,700.0,15.0 raw=["AXShowMenu"] pretty=[] synthetic=false
20 role=AXRow id=- frame=0.0,175.0,700.0,15.0 raw=[] pretty=[] synthetic=false
21 role=AXRow id=- frame=0.0,190.0,700.0,15.0 raw=[] pretty=[] synthetic=false
22 role=AXRow id=- frame=0.0,205.0,700.0,15.0 raw=["AXShowMenu"] pretty=[] synthetic=false
23 role=AXRow id=- frame=0.0,220.0,700.0,15.0 raw=[] pretty=[] synthetic=false
24 role=AXRow id=- frame=0.0,235.0,700.0,15.0 raw=[] pretty=[] synthetic=false
25 role=AXRow id=- frame=0.0,250.0,700.0,15.0 raw=["AXShowMenu"] pretty=[] synthetic=false
26 role=AXRow id=- frame=0.0,265.0,700.0,15.0 raw=[] pretty=[] synthetic=false
27 role=AXRow id=- frame=0.0,280.0,700.0,15.0 raw=[] pretty=[] synthetic=false
28 role=AXRow id=- frame=0.0,295.0,700.0,15.0 raw=["AXShowMenu"] pretty=[] synthetic=false
29 role=AXRow id=- frame=0.0,310.0,700.0,15.0 raw=[] pretty=[] synthetic=false
30 role=AXRow id=- frame=0.0,325.0,700.0,15.0 raw=[] pretty=[] synthetic=false
31 role=AXRow id=- frame=0.0,340.0,700.0,15.0 raw=["AXShowMenu"] pretty=[] synthetic=false
32 role=AXRow id=- frame=0.0,355.0,700.0,15.0 raw=[] pretty=[] synthetic=false
33 role=AXRow id=- frame=0.0,370.0,700.0,15.0 raw=[] pretty=[] synthetic=false
34 role=AXRow id=- frame=0.0,385.0,700.0,15.0 raw=["AXShowMenu"] pretty=[] synthetic=false
35 role=AXGroup id=- frame=720.0,100.0,260.0,80.0 raw=[] pretty=[] synthetic=false
36 role=AXStaticText id=- frame=- raw=[] pretty=[] synthetic=false
37 role=AXLink id=- frame=- raw=[] pretty=[] synthetic=false
38 role=AXStaticText id=- frame=- raw=[] pretty=[] synthetic=false
39 role=AXCheckBox id=- frame=720.0,300.0,120.0,20.0 raw=["AXPress"] pretty=[] synthetic=false
40 role=AXWebArea id=- frame=720.0,400.0,260.0,200.0 raw=[] pretty=[] synthetic=false
41 role=AXLink id=- frame=730.0,420.0,60.0,20.0 raw=["AXPress"] pretty=[] synthetic=false
42 role=AXStaticText id=- frame=- raw=[] pretty=[] synthetic=false
43 role=AXStaticText id=- frame=- raw=[] pretty=[] synthetic=false
44 role=AXList id=- frame=0.0,520.0,200.0,200.0 raw=[] pretty=[] synthetic=false
45 role=AXStaticText id=- frame=- raw=[] pretty=[] synthetic=false
46 role=AXStaticText id=- frame=- raw=[] pretty=[] synthetic=false
47 role=AXStaticText id=- frame=- raw=[] pretty=[] synthetic=false
48 role=AXMenuBar id=- frame=- raw=[] pretty=[] synthetic=false
49 role=AXMenuBarItem id=- frame=- raw=["AXPress", "AXCancel"] pretty=[] synthetic=false
50 role=AXMenuBarItem id=- frame=- raw=["AXPress", "AXCancel"] pretty=[] synthetic=false
51 role=AXMenuBarItem id=- frame=- raw=["AXPress", "AXCancel"] pretty=[] synthetic=false
"""#
}
