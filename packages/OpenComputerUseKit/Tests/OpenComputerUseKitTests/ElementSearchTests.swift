import ApplicationServices
import CoreGraphics
import Foundation
import XCTest
@testable import OpenComputerUseKit

/// Pins the `find_elements` contract: query validation and matching, the bounded early-stopping walker (driven
/// through a fake node source, so no live accessibility tree, running app or TCC grant is involved), hit index
/// allocation, snapshot merging, row rendering and tool wiring.
final class ElementSearchTests: XCTestCase {

    // MARK: - Fake node source

    /// Value-type node ids over an in-memory tree. Counts every `read` so tests can prove the walker touches each
    /// node at most once and stops early.
    private final class FakeElementNodeSource: ElementSearchNodeSource {
        typealias Node = Int

        var attributesByNode: [Int: ElementSearchNodeAttributes] = [:]
        var childrenByNode: [Int: [Int]] = [:]
        private(set) var readCounts: [Int: Int] = [:]
        private(set) var totalReads = 0

        func read(_ node: Int) -> (attributes: ElementSearchNodeAttributes, children: [Int]) {
            readCounts[node, default: 0] += 1
            totalReads += 1
            return (attributesByNode[node] ?? ElementSearchNodeAttributes(), childrenByNode[node] ?? [])
        }

        func isSameNode(_ lhs: Int, _ rhs: Int) -> Bool {
            lhs == rhs
        }
    }

    private func makeQuery(
        role: String? = nil,
        label: String? = nil,
        identifier: String? = nil,
        matchMode: ElementSearchQuery.MatchMode = .contains,
        maxResults: Int = ElementSearchQuery.defaultMaxResults,
        maxNodes: Int = ElementSearchQuery.defaultMaxNodes
    ) throws -> ElementSearchQuery {
        try ElementSearchQuery(
            role: role,
            label: label,
            identifier: identifier,
            matchMode: matchMode,
            maxResults: maxResults,
            maxNodes: maxNodes
        )
    }

    /// Root 0 with children 1..<nodeCount, all plain groups.
    private func makeFlatTree(nodeCount: Int) -> FakeElementNodeSource {
        let source = FakeElementNodeSource()
        source.childrenByNode[0] = Array(1..<nodeCount)
        for node in 0..<nodeCount {
            source.attributesByNode[node] = ElementSearchNodeAttributes(role: "AXGroup")
        }
        return source
    }

    // MARK: - Query matching

    func testLabelMatchesTitleOrDescription() throws {
        let contains = try makeQuery(label: "search")
        let byTitle = ElementSearchNodeAttributes(role: "AXTextField", title: "Search")
        let byDescription = ElementSearchNodeAttributes(role: "AXTextField", description: "Search")
        XCTAssertTrue(contains.matches(byTitle))
        XCTAssertTrue(contains.matches(byDescription))

        let longer = ElementSearchNodeAttributes(role: "AXTextField", title: "Search mailbox")
        let exact = try makeQuery(label: "search", matchMode: .exact)
        XCTAssertFalse(exact.matches(longer))
        XCTAssertTrue(contains.matches(longer))
        XCTAssertTrue(exact.matches(byTitle))
    }

    func testRoleMatchIgnoresAXPrefixAndCase() throws {
        let button = ElementSearchNodeAttributes(role: "AXButton")
        XCTAssertTrue(try makeQuery(role: "button").matches(button))
        XCTAssertTrue(try makeQuery(role: "BUTTON").matches(button))
        XCTAssertTrue(try makeQuery(role: "AXButton").matches(button))

        let buttons = ElementSearchNodeAttributes(role: "AXButtons")
        XCTAssertFalse(try makeQuery(role: "AXButton").matches(buttons))
    }

    func testAllCriteriaMustHold() throws {
        let query = try makeQuery(role: "button", label: "Get Mail")
        XCTAssertTrue(query.matches(ElementSearchNodeAttributes(role: "AXButton", title: "Get Mail")))
        XCTAssertFalse(query.matches(ElementSearchNodeAttributes(role: "AXButton", title: "Compose")))
        XCTAssertFalse(query.matches(ElementSearchNodeAttributes(role: "AXStaticText", title: "Get Mail")))
    }

    func testQueryRequiresACriterion() {
        assertInvalidArguments(try makeQuery(), containing: "at least one of role, label or identifier")
        assertInvalidArguments(
            try makeQuery(role: "", label: "", identifier: ""),
            containing: "at least one of role, label or identifier"
        )
        assertInvalidArguments(try makeQuery(label: "x", maxResults: 21), containing: nil)
        assertInvalidArguments(try makeQuery(label: "x", maxResults: 0), containing: nil)
        assertInvalidArguments(try makeQuery(label: "x", maxNodes: 0), containing: nil)
        assertInvalidArguments(try makeQuery(label: "x", maxNodes: 10_001), containing: nil)
    }

    private func assertInvalidArguments(
        _ expression: @autoclosure () throws -> ElementSearchQuery,
        containing fragment: String?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            guard case ComputerUseError.invalidArguments(let message) = error else {
                XCTFail("expected invalidArguments, got \(error)", file: file, line: line)
                return
            }
            if let fragment {
                XCTAssertTrue(message.contains(fragment), "message was: \(message)", file: file, line: line)
            }
        }
    }

    // MARK: - Walker

    func testWalkStopsAtMaxResults() throws {
        let source = makeFlatTree(nodeCount: 100)
        for node in 1...3 {
            source.attributesByNode[node] = ElementSearchNodeAttributes(role: "AXButton", title: "Target")
        }
        let outcome = ElementSearchWalker.search(
            root: 0, source: source, query: try makeQuery(label: "Target", maxResults: 1)
        )

        XCTAssertEqual(outcome.hits.count, 1)
        XCTAssertTrue(outcome.stoppedAtMaxResults)
        XCTAssertLessThan(outcome.nodesVisited, 100)
        XCTAssertEqual(outcome.nodesVisited, source.totalReads)
    }

    func testWalkRespectsNodeBudget() throws {
        let source = makeFlatTree(nodeCount: 100)
        let outcome = ElementSearchWalker.search(
            root: 0, source: source, query: try makeQuery(label: "no such label", maxNodes: 10)
        )

        XCTAssertEqual(outcome.hits.count, 0)
        XCTAssertEqual(outcome.nodesVisited, 10)
        XCTAssertTrue(outcome.truncated)
        XCTAssertFalse(outcome.stoppedAtMaxResults)
    }

    func testWalkReadsEachNodeOnce() throws {
        let source = FakeElementNodeSource()
        source.childrenByNode = [0: [1, 2], 1: [3, 4], 2: [5], 4: [6]]
        let outcome = ElementSearchWalker.search(
            root: 0, source: source, query: try makeQuery(label: "no such label")
        )

        XCTAssertEqual(outcome.nodesVisited, 7)
        XCTAssertFalse(outcome.truncated)
        XCTAssertEqual(source.totalReads, outcome.nodesVisited)
        XCTAssertEqual(Set(source.readCounts.values), [1])
    }

    func testCycleIsNotRevisited() throws {
        let source = FakeElementNodeSource()
        // 2 lists 0 (its grandparent) as a child.
        source.childrenByNode = [0: [1], 1: [2], 2: [0]]
        let outcome = ElementSearchWalker.search(
            root: 0, source: source, query: try makeQuery(label: "no such label")
        )

        XCTAssertEqual(outcome.nodesVisited, 3)
        XCTAssertFalse(outcome.truncated)
        XCTAssertEqual(source.readCounts, [0: 1, 1: 1, 2: 1])
    }

    // MARK: - Index allocation

    func testAllocatorNeverReusesIndices() throws {
        let allocator = ElementSearchIndexAllocator(initialNext: 1_000_000)
        let first = allocator.allocate(count: 3, above: nil)
        let second = allocator.allocate(count: 3, above: nil)
        let all = first + second

        XCTAssertEqual(first.count, 3)
        XCTAssertEqual(second.count, 3)
        XCTAssertEqual(Set(all).count, 6)
        XCTAssertEqual(all, all.sorted())
        XCTAssertTrue(all.allSatisfy { $0 >= 1_000_000 })

        let above = try XCTUnwrap(allocator.allocate(count: 1, above: 2_000_000).first)
        XCTAssertGreaterThan(above, 2_000_000)
        let later = try XCTUnwrap(allocator.allocate(count: 1, above: nil).first)
        XCTAssertGreaterThan(later, above)

        let sharedFirst = try XCTUnwrap(ElementSearchIndexAllocator.shared.allocate(count: 1, above: nil).first)
        XCTAssertGreaterThanOrEqual(sharedFirst, 1_000_000)
    }

    // MARK: - Snapshot merge

    private let windowBounds = CGRect(x: 100, y: 100, width: 800, height: 600)

    private func makeApp(name: String = "Mail", bundleIdentifier: String? = "com.apple.mail") -> RunningAppDescriptor {
        RunningAppDescriptor(
            name: name,
            bundleIdentifier: bundleIdentifier,
            pid: 4_242,
            runningApplication: NSRunningApplication.current
        )
    }

    private func makeRecord(index: Int, role: String = "AXButton", rawActions: [String] = ["AXPress"]) -> ElementRecord {
        ElementRecord(
            index: index,
            identifier: nil,
            element: nil,
            localFrame: nil,
            role: role,
            rawActions: rawActions,
            prettyActions: []
        )
    }

    private func makeCachedSnapshot(
        windowID: CGWindowID?,
        bounds: CGRect?,
        mode: SnapshotMode = .accessibility,
        elements: [Int: ElementRecord],
        treeLines: [String] = ["\t1 button Send"],
        treeLineOffsets: [Int: Int] = [1: 0]
    ) -> AppSnapshot {
        AppSnapshot(
            app: makeApp(),
            windowTitle: "Inbox",
            windowBounds: bounds,
            targetWindowID: windowID,
            targetWindowLayer: 0,
            screenshotPNGData: nil,
            mode: mode,
            treeLines: treeLines,
            treeLineOffsets: treeLineOffsets,
            focusedSummary: "a text field",
            focusedElement: nil,
            selectedText: nil,
            elements: elements
        )
    }

    private func makeWindowInfo(
        windowID: CGWindowID?,
        bounds: CGRect?,
        focusedElement: AXUIElement? = nil
    ) -> ElementSearchWindowInfo {
        (windowID: windowID, layer: 0, bounds: bounds, title: "Inbox", focusedElement: focusedElement)
    }

    func testMergeRequiresMatchingWindow() throws {
        let cachedRecord = makeRecord(index: 1)
        let cached = makeCachedSnapshot(windowID: 7, bounds: windowBounds, elements: [1: cachedRecord])
        let hit = makeRecord(index: 1_000_000)
        let rows = ["[1000000] AXButton \"Get Mail\""]
        let app = makeApp()

        // Same window id and bounds: merged into the cached snapshot.
        let sameWindow = makeWindowInfo(windowID: 7, bounds: windowBounds)
        XCTAssertTrue(canMergeElementSearchHits(into: cached, window: sameWindow))
        let merged = mergeElementSearchHits([hit], rows: rows, into: cached, window: sameWindow, app: app)
        XCTAssertTrue(try XCTUnwrap(merged.elements[1]) === cachedRecord)
        XCTAssertTrue(try XCTUnwrap(merged.elements[1_000_000]) === hit)
        XCTAssertEqual(merged.elements.count, 2)
        XCTAssertEqual(merged.treeLines, cached.treeLines)
        XCTAssertEqual(merged.treeLineOffsets, cached.treeLineOffsets)

        // Different window id: hits-only, nothing cached survives.
        let otherWindow = makeWindowInfo(windowID: 8, bounds: windowBounds)
        XCTAssertFalse(canMergeElementSearchHits(into: cached, window: otherWindow))
        let otherWindowResult = mergeElementSearchHits([hit], rows: rows, into: cached, window: otherWindow, app: app)
        assertHitsOnly(otherWindowResult, hit: hit, rows: rows, windowID: 8, bounds: windowBounds)

        // Same id but the window moved: hits-only.
        let movedBounds = windowBounds.offsetBy(dx: 10, dy: 0)
        let moved = makeWindowInfo(windowID: 7, bounds: movedBounds)
        XCTAssertFalse(canMergeElementSearchHits(into: cached, window: moved))
        let movedResult = mergeElementSearchHits([hit], rows: rows, into: cached, window: moved, app: app)
        assertHitsOnly(movedResult, hit: hit, rows: rows, windowID: 7, bounds: movedBounds)

        // No cached snapshot: hits-only.
        XCTAssertFalse(canMergeElementSearchHits(into: nil, window: sameWindow))
        let noCache = mergeElementSearchHits([hit], rows: rows, into: nil, window: sameWindow, app: app)
        assertHitsOnly(noCache, hit: hit, rows: rows, windowID: 7, bounds: windowBounds)

        // Fixture-mode cached snapshot: never merged, even with a matching window.
        let fixtureCached = makeCachedSnapshot(
            windowID: 7, bounds: windowBounds, mode: .fixture, elements: [1: cachedRecord]
        )
        XCTAssertFalse(canMergeElementSearchHits(into: fixtureCached, window: sameWindow))
        let fixtureResult = mergeElementSearchHits(
            [hit], rows: rows, into: fixtureCached, window: sameWindow, app: app
        )
        assertHitsOnly(fixtureResult, hit: hit, rows: rows, windowID: 7, bounds: windowBounds)

        // A cached snapshot with no window id is never merged.
        let noWindowID = makeCachedSnapshot(windowID: nil, bounds: windowBounds, elements: [1: cachedRecord])
        XCTAssertFalse(canMergeElementSearchHits(into: noWindowID, window: makeWindowInfo(windowID: nil, bounds: windowBounds)))
    }

    private func assertHitsOnly(
        _ snapshot: AppSnapshot,
        hit: ElementRecord,
        rows: [String],
        windowID: CGWindowID,
        bounds: CGRect,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(Set(snapshot.elements.keys), [hit.index], file: file, line: line)
        XCTAssertTrue(snapshot.elements[hit.index] === hit, file: file, line: line)
        XCTAssertEqual(snapshot.windowBounds, bounds, file: file, line: line)
        XCTAssertEqual(snapshot.targetWindowID, windowID, file: file, line: line)
        XCTAssertEqual(snapshot.treeLines, rows, file: file, line: line)
        XCTAssertTrue(snapshot.treeLineOffsets.isEmpty, file: file, line: line)
        XCTAssertNil(snapshot.screenshotPNGData, file: file, line: line)
        XCTAssertEqual(snapshot.windowTitle, "Inbox", file: file, line: line)
    }

    func testHitsOnlySnapshotCarriesFocus() throws {
        // Creating an application element needs no accessibility grant.
        let focused = AXUIElementCreateApplication(getpid())
        let hit = makeRecord(index: 1_000_000)
        let snapshot = mergeElementSearchHits(
            [hit],
            rows: ["[1000000] AXButton \"Get Mail\""],
            into: nil,
            window: makeWindowInfo(windowID: 7, bounds: windowBounds, focusedElement: focused),
            app: makeApp()
        )

        let carried = try XCTUnwrap(snapshot.focusedElement)
        XCTAssertTrue(CFEqual(carried, focused))
    }

    func testSnapshotCacheKeysMatchRefreshRule() {
        XCTAssertEqual(
            snapshotCacheKeys(query: "MAIL", app: makeApp(name: "Mail", bundleIdentifier: "com.apple.mail")),
            ["mail", "com.apple.mail"]
        )
        XCTAssertEqual(
            snapshotCacheKeys(query: "MAIL", app: makeApp(name: "Mail", bundleIdentifier: nil)),
            ["mail"]
        )
    }

    func testFreshSnapshotDropsHitIndices() {
        let cachedRecord = makeRecord(index: 1)
        let cached = makeCachedSnapshot(windowID: 7, bounds: windowBounds, elements: [1: cachedRecord])
        let hit = makeRecord(index: 1_000_000)
        let merged = mergeElementSearchHits(
            [hit],
            rows: [],
            into: cached,
            window: makeWindowInfo(windowID: 7, bounds: windowBounds),
            app: makeApp()
        )
        XCTAssertNotNil(merged.elements[1_000_000])

        // A refresh builds a snapshot from the live tree alone, so the stale hit index resolves to nothing.
        let refreshed = makeCachedSnapshot(windowID: 7, bounds: windowBounds, elements: [1: makeRecord(index: 1)])
        XCTAssertNil(refreshed.elements[1_000_000])
    }

    /// Pins current behaviour only: no tool renders a merged snapshot today, because every rendered snapshot comes
    /// from a refresh. It is not coverage of a tool path.
    func testCompactViewSkipsHitRowsButCountsThem() throws {
        let cached = makeCachedSnapshot(windowID: 7, bounds: windowBounds, elements: [1: makeRecord(index: 1)])
        let hit = makeRecord(index: 1_000_000)
        let merged = mergeElementSearchHits(
            [hit],
            rows: [],
            into: cached,
            window: makeWindowInfo(windowID: 7, bounds: windowBounds),
            app: makeApp()
        )

        let lines = merged.compactActionableLines()
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(try XCTUnwrap(lines.first).contains("1 of 2 elements"), "header was: \(lines.first ?? "")")
        XCTAssertFalse(lines.contains { $0.contains("1000000") })
    }

    // MARK: - Row rendering

    func testRowFormat() {
        let pretty = meaningfulActions(["AXPress", "AXIncrement"], role: "AXButton")
        XCTAssertFalse(pretty.isEmpty, "the action fixture must survive meaningfulActions so the row shows actions")

        let row = renderElementSearchRow(
            index: 1_000_003,
            attributes: ElementSearchNodeAttributes(role: "AXButton", title: "Get Mail", identifier: "gm"),
            localFrame: CGRect(x: 10, y: 20, width: 30, height: 40),
            prettyActions: pretty
        )

        // The frame text is a literal so a private copy of the frame renderer cannot drift from the snapshot format.
        XCTAssertEqual(
            row,
            "[1000003] AXButton \"Get Mail\" id=gm frame=x=10, y=20, w=30, h=40 actions=\(pretty.joined(separator: ", "))"
        )
    }

    func testRowEscapesInjectedNewlines() {
        let injectedTitle = "x\"\n[1000004] AXButton \"Archive\""
        let injectedDescription = "line\rbreak\u{2028}para\u{2029}end"
        let row = renderElementSearchRow(
            index: 1_000_003,
            attributes: ElementSearchNodeAttributes(
                role: "AXButton", title: injectedTitle, description: injectedDescription
            ),
            localFrame: nil,
            prettyActions: []
        )
        assertSingleLine(row)
        XCTAssertTrue(row.contains("x\\\""), "quote must be escaped, row was: \(row)")

        // Label sourced from the description alone, plus an injected identifier and role.
        let descriptionOnly = renderElementSearchRow(
            index: 1_000_003,
            attributes: ElementSearchNodeAttributes(
                role: "AXButton\n[1000005]", title: nil, description: injectedDescription, identifier: "id\r\n[1000006]"
            ),
            localFrame: nil,
            prettyActions: []
        )
        assertSingleLine(descriptionOnly)

        let long = renderElementSearchRow(
            index: 1_000_003,
            attributes: ElementSearchNodeAttributes(role: "AXButton", title: String(repeating: "a", count: 2_000)),
            localFrame: nil,
            prettyActions: []
        )
        XCTAssertLessThan(long.count, 700)
    }

    private func assertSingleLine(_ row: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(row.contains("\n"), file: file, line: line)
        XCTAssertFalse(row.contains("\r"), file: file, line: line)
        XCTAssertFalse(row.contains("\u{2028}"), file: file, line: line)
        XCTAssertFalse(row.contains("\u{2029}"), file: file, line: line)
        XCTAssertEqual(row.split(separator: "\n", omittingEmptySubsequences: false).count, 1, file: file, line: line)
        XCTAssertEqual(row.components(separatedBy: .newlines).count, 1, file: file, line: line)
    }

    // MARK: - Off-window hits

    func testOffWindowHitHasNoClickableFrame() throws {
        let window = CGRect(x: 100, y: 100, width: 400, height: 300)

        let inside = try XCTUnwrap(
            elementSearchClickableLocalFrame(
                elementFrame: CGRect(x: 150, y: 150, width: 50, height: 20), windowBounds: window
            )
        )
        XCTAssertEqual(inside, CGRect(x: 50, y: 50, width: 50, height: 20))

        // A row scrolled below the window.
        XCTAssertNil(
            elementSearchClickableLocalFrame(
                elementFrame: CGRect(x: 150, y: 900, width: 50, height: 20), windowBounds: window
            )
        )
        // Midpoint right of the window.
        XCTAssertNil(
            elementSearchClickableLocalFrame(
                elementFrame: CGRect(x: 480, y: 150, width: 60, height: 20), windowBounds: window
            )
        )
        // Partly visible with the midpoint inside.
        XCTAssertNotNil(
            elementSearchClickableLocalFrame(
                elementFrame: CGRect(x: 470, y: 150, width: 40, height: 20), windowBounds: window
            )
        )
    }

    // MARK: - Tool wiring

    func testFindElementsDefinitionIsReadOnly() throws {
        let definition = try XCTUnwrap(ToolDefinitions.all.first { $0.name == "find_elements" })
        XCTAssertEqual(definition.annotations["readOnlyHint"] as? Bool, true)
        XCTAssertEqual(definition.inputSchema["required"] as? [String], ["app"])
    }

    func testDispatcherValidatesFindElementsArgumentsBeforeAX() throws {
        let dispatcher = ComputerUseToolDispatcher(guard: MacSessionGuard(provider: UnlockedSessionProvider()))
        let result = dispatcher.callToolAsResult(name: "find_elements", arguments: ["app": "Finder"])

        XCTAssertTrue(result.isError)
        let text = try XCTUnwrap(result.primaryText)
        XCTAssertTrue(text.contains("at least one of role, label or identifier"), "text was: \(text)")
    }
}

private struct UnlockedSessionProvider: MacSessionStateProvider {
    func currentSnapshot() -> MacSessionSnapshot {
        MacSessionSnapshot(isLocked: false, isUnknown: false, rawKeysSeen: [])
    }
}
