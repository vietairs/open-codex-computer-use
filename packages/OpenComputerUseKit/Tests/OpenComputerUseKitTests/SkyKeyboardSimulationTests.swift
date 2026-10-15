import CoreGraphics
import Foundation
import XCTest
@testable import OpenComputerUseKit

private struct FixedSessionProvider: MacSessionStateProvider {
    let snapshot: MacSessionSnapshot

    func currentSnapshot() -> MacSessionSnapshot {
        snapshot
    }
}

/// A menu node for the pure walk: `matches` stands in for the live attribute reads.
private struct MenuNode: Equatable {
    let name: String
    var matches = false
    var children: [MenuNode] = []
}

final class SkyKeyboardSimulationTests: XCTestCase {
    private static var locked: MacSessionSnapshot { MacSessionSnapshot(isLocked: true, isUnknown: false, rawKeysSeen: ["CGSSessionScreenIsLocked"]) }
    private static var unknown: MacSessionSnapshot { MacSessionSnapshot(isLocked: true, isUnknown: true, rawKeysSeen: []) }
    private static var unlocked: MacSessionSnapshot { MacSessionSnapshot(isLocked: false, isUnknown: false, rawKeysSeen: ["CGSSessionScreenIsLocked"]) }

    // MARK: - Key-window records and capability text

    func testKeyWindowRecordsFollowTheMakeKeyLayout() {
        let records = skyLightKeyWindowRecords(windowID: 0x1234_5678)
        XCTAssertEqual(records.map(\.count), [0xF8, 0xF8])
        XCTAssertEqual(records.map { $0[0x08] }, [0x01, 0x02])
        for record in records {
            XCTAssertEqual(record[0x04], 0xF8)
            XCTAssertEqual(record[0x3A], 0x10)
            XCTAssertEqual(Array(record[0x3C...0x3F]), [0x78, 0x56, 0x34, 0x12])
            XCTAssertEqual(Array(record[0x20..<0x30]), [UInt8](repeating: 0xFF, count: 0x10))
            XCTAssertEqual(record[0x8A], 0, "key-window records must not carry the activation focus marker")
        }
    }

    func testCapabilityTextNamesTheFeature() {
        XCTAssertEqual(
            SkyLightSPICapability(missingSymbols: ["SLPSPostEventRecordTo"]).unavailableReason,
            "missing private click symbols: SLPSPostEventRecordTo"
        )
        XCTAssertEqual(
            SkyLightSPICapability(missingSymbols: ["SLPSPostEventRecordTo"], feature: "key").unavailableReason,
            "missing private key symbols: SLPSPostEventRecordTo"
        )
    }

    // MARK: - Menu key equivalents

    func testMenuKeyEquivalentOnlyCoversCommandCharacterChords() throws {
        XCTAssertEqual(
            skyMenuKeyEquivalent(for: try KeyPressParser.parse("cmd+a")),
            SkyMenuKeyEquivalent(character: "A", modifiers: 0)
        )
        XCTAssertEqual(
            skyMenuKeyEquivalent(for: try KeyPressParser.parse("cmd+shift+option+ctrl+z")),
            SkyMenuKeyEquivalent(character: "Z", modifiers: 7)
        )
        XCTAssertNil(skyMenuKeyEquivalent(for: try KeyPressParser.parse("shift+a")), "non-command chords are key events")
        XCTAssertNil(
            skyMenuKeyEquivalent(for: try KeyPressParser.parse("cmd+shift+left")),
            "navigation chords are key bindings, not menu items"
        )
        XCTAssertNil(skyMenuKeyEquivalent(for: try KeyPressParser.parse("return")))
    }

    func testMenuItemMatchingIsCaseInsensitiveAndNeedsAConfirmedEnabledItem() {
        let selectAll = SkyMenuKeyEquivalent(character: "A", modifiers: 0)
        XCTAssertTrue(skyMenuItemMatches(cmdChar: "a", cmdModifiers: nil, enabled: true, equivalent: selectAll))
        XCTAssertTrue(skyMenuItemMatches(cmdChar: "A", cmdModifiers: 0, enabled: true, equivalent: selectAll))
        XCTAssertFalse(skyMenuItemMatches(cmdChar: "A", cmdModifiers: 1, enabled: true, equivalent: selectAll))
        XCTAssertFalse(skyMenuItemMatches(cmdChar: "A", cmdModifiers: 0, enabled: false, equivalent: selectAll))
        XCTAssertFalse(
            skyMenuItemMatches(cmdChar: "A", cmdModifiers: 0, enabled: nil, equivalent: selectAll),
            "an unknown enabled state counts as disabled"
        )
        XCTAssertFalse(skyMenuItemMatches(cmdChar: nil, cmdModifiers: 0, enabled: true, equivalent: selectAll))
    }

    // MARK: - Menu walk

    private func menuBar(apple: [MenuNode] = [], application: [MenuNode] = [], others: [[MenuNode]] = []) -> [MenuNode] {
        func barItem(_ name: String, _ items: [MenuNode]) -> MenuNode {
            MenuNode(name: name, children: [MenuNode(name: "\(name) menu", children: items)])
        }
        return [barItem("Apple", apple), barItem("App", application)]
            + others.enumerated().map { barItem("Menu \($0.offset)", $0.element) }
    }

    private func find(
        _ bar: [MenuNode],
        limits: SkyMenuWalkLimits = .standard,
        now: @escaping () -> TimeInterval = { 0 }
    ) -> SkyMenuSearchResult<MenuNode> {
        skyFindMenuItem(menuBarItems: bar, limits: limits, now: now, children: \.children, matches: \.matches)
    }

    func testMenuWalkFindsTheSingleMatchingItem() {
        let selectAll = MenuNode(name: "Select All", matches: true)
        let bar = menuBar(others: [[MenuNode(name: "Undo"), selectAll]])
        XCTAssertEqual(find(bar), .match(selectAll))
    }

    func testMenuWalkNeverSearchesTheAppleMenu() {
        let logOut = MenuNode(name: "Log Out", matches: true)
        XCTAssertEqual(find(menuBar(apple: [logOut])), .noMatch)
    }

    func testMenuWalkSearchesApplicationMenuItemsButNotItsSubmenus() {
        let quit = MenuNode(name: "Quit", matches: true)
        XCTAssertEqual(find(menuBar(application: [quit])), .match(quit))

        let services = MenuNode(
            name: "Services",
            children: [MenuNode(name: "Services menu", children: [MenuNode(name: "New Terminal", matches: true)])]
        )
        XCTAssertEqual(find(menuBar(application: [services])), .noMatch)
    }

    func testMenuWalkFailsWhenMoreThanOneEnabledItemMatches() {
        let bar = menuBar(others: [
            [MenuNode(name: "Find", matches: true)],
            [MenuNode(name: "Find Again", matches: true)],
        ])
        XCTAssertEqual(find(bar), .ambiguous)
    }

    func testMenuWalkStopsBelowTheDepthLimit() {
        let deep = MenuNode(name: "Deep", matches: true)
        let nested = MenuNode(name: "Folder", children: [
            MenuNode(name: "Folder menu", children: [
                MenuNode(name: "Subfolder", children: [MenuNode(name: "Subfolder menu", children: [deep])]),
            ]),
        ])
        XCTAssertEqual(find(menuBar(others: [[nested]])), .noMatch)

        let shallow = MenuNode(name: "Folder", children: [MenuNode(name: "Folder menu", children: [deep])])
        XCTAssertEqual(find(menuBar(others: [[shallow]])), .match(deep), "one submenu level is searched")
    }

    func testMenuWalkGivesUpWhenTheNodeBudgetRunsOut() {
        let items = (0..<20).map { MenuNode(name: "Item \($0)") } + [MenuNode(name: "Last", matches: true)]
        let limits = SkyMenuWalkLimits(maxNodes: 10, maxDepth: 4, timeBudget: 60)
        XCTAssertEqual(find(menuBar(others: [items]), limits: limits), .budgetExhausted)
    }

    func testMenuWalkGivesUpWhenTheTimeBudgetRunsOut() {
        var clock: TimeInterval = 0
        let items = (0..<20).map { MenuNode(name: "Item \($0)") }
        let limits = SkyMenuWalkLimits(maxNodes: 1_000, maxDepth: 4, timeBudget: 1.0)
        let result = find(menuBar(others: [items]), limits: limits, now: {
            clock += 0.1
            return clock
        })
        XCTAssertEqual(result, .budgetExhausted)
    }

    // MARK: - Window owner check

    func testKeyWindowValidationAllowsOffScreenWindowsOfTheSameOwner() {
        let offScreen: [String: Any] = [
            kCGWindowNumber as String: NSNumber(value: UInt32(321)),
            kCGWindowOwnerPID as String: NSNumber(value: Int32(1234)),
            kCGWindowIsOnscreen as String: NSNumber(value: false),
        ]
        XCTAssertTrue(skyKeyWindowMatchesTarget(windowInfo: [offScreen], windowID: 321, pid: 1234))
        XCTAssertFalse(skyKeyWindowMatchesTarget(windowInfo: [offScreen], windowID: 321, pid: 1235))
        XCTAssertFalse(skyKeyWindowMatchesTarget(windowInfo: [offScreen], windowID: 322, pid: 1234))
        XCTAssertFalse(skyKeyWindowMatchesTarget(windowInfo: [], windowID: 321, pid: 1234))
    }

    // MARK: - Lock rule

    func testSkyKeyRefusesWhenLockedOrUnknownEvenWithTheLockedOptIn() throws {
        setenv(MacSessionLockPolicy.environmentKey, "1", 1)
        addTeardownBlock { unsetenv(MacSessionLockPolicy.environmentKey) }
        XCTAssertEqual(MacSessionLockPolicy.fromEnvironment(), .allowWhileLocked)

        for snapshot in [Self.locked, Self.unknown, MacSessionSnapshot(isLocked: false, isUnknown: true, rawKeysSeen: [])] {
            XCTAssertThrowsError(try requireUnlockedForSkyKey(snapshot)) { error in
                XCTAssertTrue(
                    (error as? ComputerUseError)?.errorDescription?.contains("cannot run while macOS is locked") == true,
                    "\(error)"
                )
            }
        }
        XCTAssertNoThrow(try requireUnlockedForSkyKey(Self.unlocked))
    }

    func testDispatcherChecksTheLockBeforeAnyOtherStep() throws {
        setenv(MacSessionLockPolicy.environmentKey, "1", 1)
        addTeardownBlock { unsetenv(MacSessionLockPolicy.environmentKey) }
        // A window id that exists nowhere: if the lock check did not run first, validation would fail instead.
        let target = SkyKeyboardTarget(windowID: 0, pid: getpid())

        for snapshot in [Self.locked, Self.unknown] {
            let provider = FixedSessionProvider(snapshot: snapshot)
            XCTAssertThrowsError(try SkyKeyboardDispatcher.typeText(target: target, text: "x", sessionState: provider)) { error in
                XCTAssertTrue(ComputerUseError.isLockRefusal(error), "\(error)")
            }
            XCTAssertThrowsError(try SkyKeyboardDispatcher.pressKey(target: target, key: "cmd+a", sessionState: provider)) { error in
                XCTAssertTrue(ComputerUseError.isLockRefusal(error), "\(error)")
            }
        }

        // Unlocked, the same call gets past the lock check and fails closed on the missing window (or on a missing
        // SkyLight symbol) without sending anything.
        let provider = FixedSessionProvider(snapshot: Self.unlocked)
        XCTAssertThrowsError(try SkyKeyboardDispatcher.typeText(target: target, text: "x", sessionState: provider)) { error in
            XCTAssertFalse(ComputerUseError.isLockRefusal(error), "\(error)")
        }
    }

    // MARK: - Release failure and source invariants

    func testReleaseWarningSaysTheKeysWereDeliveredAndMustNotBeResent() {
        let note = skyKeyReleaseWarningNote("OSStatus -600")
        XCTAssertTrue(note.contains("delivered the keys"))
        XCTAssertTrue(note.contains("Do not send the keys again"))
        XCTAssertTrue(note.contains("OSStatus -600"))
    }

    private static let kitSourcesDirectory: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            url.deleteLastPathComponent()
        }
        return url.appendingPathComponent("Sources/OpenComputerUseKit", isDirectory: true)
    }()

    private func kitSource(_ name: String) throws -> String {
        try String(contentsOf: Self.kitSourcesDirectory.appendingPathComponent(name), encoding: .utf8)
    }

    /// Both synthetic-focus methods serialize on one lock, so concurrent sessions cannot interleave focus records.
    func testSkyClickAndSkyKeyShareOneSyntheticFocusLock() throws {
        for name in ["SkyClickSimulation.swift", "SkyKeyboardSimulation.swift"] {
            let source = try kitSource(name)
            XCTAssertTrue(source.contains("SkyLightSPI.syntheticFocusLock.lock()"), "\(name) must take the shared lock")
            XCTAssertTrue(source.contains("SkyLightSPI.syntheticFocusLock.unlock()"), "\(name) must release the shared lock")
            XCTAssertFalse(source.contains("NSLock()"), "\(name) must not declare a lock of its own")
        }
    }

    /// Values read from the target app's menu bar are type-checked, never force-cast.
    func testSkyKeyboardSourceHasNoForcedCast() throws {
        let source = try kitSource("SkyKeyboardSimulation.swift")
        XCTAssertFalse(source.contains(" as! "))
    }
}

private extension ComputerUseError {
    static func isLockRefusal(_ error: Error) -> Bool {
        guard case let .stateUnavailable(message)? = error as? ComputerUseError else {
            return false
        }
        return message.contains("cannot run while macOS is locked")
    }
}
