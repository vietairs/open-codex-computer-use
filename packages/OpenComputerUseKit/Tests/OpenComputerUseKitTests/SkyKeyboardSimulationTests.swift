import ApplicationServices
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

/// Records the synthetic-focus calls `deliver` makes, in order, and fails the ones a test asks it to.
private final class FakeSyntheticFocus: SyntheticFocusControlling {
    var keyboardCapability = SkyLightSPICapability(missingSymbols: [], feature: "keyboard")
    var beginError: Error?
    var makeKeyError: Error?
    var endError: Error?
    private(set) var calls: [String] = []
    private(set) var beginWindowIDs: [CGWindowID] = []

    func beginSyntheticTargetFocus(
        targetPID: pid_t,
        targetWindowID: CGWindowID,
        methodLabel: String
    ) throws -> SkyLightSyntheticFocusContext {
        calls.append("begin")
        beginWindowIDs.append(targetWindowID)
        if let beginError {
            throw beginError
        }
        return SkyLightSyntheticFocusContext(
            deactivateTarget: SkyLightActivationCommand(psn: [0, 0, 0, 0, 0, 0, 0, 1], windowID: targetWindowID, focused: false)
        )
    }

    func makeSyntheticTargetWindowKey(_ context: SkyLightSyntheticFocusContext) throws {
        calls.append("makeKey")
        if let makeKeyError {
            throw makeKeyError
        }
    }

    func endSyntheticTargetFocus(_ context: SkyLightSyntheticFocusContext, methodLabel: String) throws {
        calls.append("end")
        if let endError {
            throw endError
        }
    }
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

    // MARK: - Keyboard capability text

    func testKeyboardCapabilityNamesTheKeyboardPath() {
        XCTAssertEqual(SkyLightSPI.shared.keyboardCapability.feature, "keyboard")
        XCTAssertEqual(SkyLightSPI.shared.keyboardCapability.missingSymbols, SkyLightSPI.shared.capability.missingSymbols)
    }

    func testUnavailableErrorNamesKeyMethodSkyKeyAndTheKeyboardSymbols() {
        let focus = FakeSyntheticFocus()
        focus.keyboardCapability = SkyLightSPICapability(missingSymbols: ["SLPSPostEventRecordTo"], feature: "keyboard")
        var bodyRuns = 0

        XCTAssertThrowsError(try deliver(focus: focus) { bodyRuns += 1; return nil }) { error in
            XCTAssertEqual(
                (error as? ComputerUseError)?.errorDescription,
                "key_method 'sky_key' is unavailable: missing private keyboard symbols: SLPSPostEventRecordTo"
            )
        }
        XCTAssertEqual(focus.calls, [])
        XCTAssertEqual(bodyRuns, 0)
    }

    // MARK: - Menu press outcome

    func testMenuPressSuccessHasNoNote() throws {
        XCTAssertNil(try skyMenuPressNote(result: .success, key: "cmd+a"))
    }

    /// A timed-out press may have run the command, so it is a success with a note, never an error that invites a retry.
    func testMenuPressTimeoutIsSuccessWithAMayHaveRunNote() throws {
        let note = try XCTUnwrap(skyMenuPressNote(result: .cannotComplete, key: "cmd+delete"))
        XCTAssertTrue(note.contains("may have run"), note)
        XCTAssertTrue(note.contains("get_app_state"), note)
        XCTAssertTrue(note.contains("'cmd+delete'"), note)
        XCTAssertTrue(note.contains("\(AXError.cannotComplete.rawValue)"), note)
    }

    func testMenuPressFailureIsAnError() {
        for result in [AXError.actionUnsupported, .invalidUIElement, .failure] {
            XCTAssertThrowsError(try skyMenuPressNote(result: result, key: "cmd+a")) { error in
                XCTAssertEqual(
                    (error as? ComputerUseError)?.errorDescription,
                    "sky_key could not press the menu item for 'cmd+a' (AXError \(result.rawValue))"
                )
            }
        }
    }

    // MARK: - Minimized window

    func testMinimizedStateMatchesOnlyTheTargetWindow() {
        let windows: [(id: CGWindowID?, minimized: Bool?)] = [(7, true), (42, false), (nil, true), (50, nil), (60, false), (60, nil)]
        func state(_ windows: [(id: CGWindowID?, minimized: Bool?)], _ windowID: CGWindowID) -> Bool? {
            skyLightWindowMinimizedState(windows: windows, windowID: windowID, windowIDOf: \.id, minimizedState: \.minimized)
        }

        XCTAssertEqual(state(windows, 7), true)
        XCTAssertEqual(state(windows, 42), false, "only a positive read is not minimized")
        XCTAssertNil(state(windows, 50), "an unreadable value is unknown")
        XCTAssertNil(state(windows, 60), "one unreadable match makes the answer unknown")
        XCTAssertNil(state(windows, 99), "a window that is not listed is unknown")
        XCTAssertNil(state([], 7))
        XCTAssertEqual(state([(7, false), (7, true)], 7), true, "any match reporting minimized wins")
    }

    // MARK: - Delivery sequence

    private static let deliveryTarget = SkyKeyboardTarget(windowID: 42, pid: 4_242)

    private func deliver(
        focus: FakeSyntheticFocus,
        frontmostPID: pid_t? = 1,
        focusedWindowID: @escaping (pid_t) -> CGWindowID? = { _ in 42 },
        validate: @escaping (SkyKeyboardTarget) throws -> Void = { _ in },
        _ body: () throws -> String?
    ) throws -> SkyKeyboardDelivery {
        try SkyKeyboardDispatcher.deliver(
            to: Self.deliveryTarget,
            focus: focus,
            sessionState: FixedSessionProvider(snapshot: Self.unlocked),
            probes: SkyKeyboardDeliveryProbes(
                validate: validate,
                frontmostPID: { frontmostPID },
                focusedWindowID: focusedWindowID
            ),
            body
        )
    }

    func testBackgroundDeliveryMakesKeySendsOnceAndReleases() throws {
        let focus = FakeSyntheticFocus()
        var bodyRuns = 0

        let delivery = try deliver(focus: focus) {
            bodyRuns += 1
            return nil
        }

        XCTAssertEqual(delivery, SkyKeyboardDelivery(releaseWarning: nil, outcomeNote: nil))
        XCTAssertEqual(focus.calls, ["begin", "makeKey", "end"])
        XCTAssertEqual(focus.beginWindowIDs, [42])
        XCTAssertEqual(bodyRuns, 1)
    }

    func testBodyNoteIsReturnedWithTheDelivery() throws {
        let delivery = try deliver(focus: FakeSyntheticFocus()) { "Note: may have run" }
        XCTAssertEqual(delivery.outcomeNote, "Note: may have run")
        XCTAssertNil(delivery.releaseWarning)
    }

    func testFailedBeginSendsNothingAndHasNothingToRelease() {
        let focus = FakeSyntheticFocus()
        focus.beginError = ComputerUseError.message("begin failed")
        var bodyRuns = 0

        XCTAssertThrowsError(try deliver(focus: focus) { bodyRuns += 1; return nil }) { error in
            XCTAssertEqual((error as? ComputerUseError)?.errorDescription, "begin failed")
        }
        XCTAssertEqual(focus.calls, ["begin"])
        XCTAssertEqual(bodyRuns, 0)
    }

    func testFailedMakeKeyReleasesTheTargetOnceAndSendsNothing() {
        let focus = FakeSyntheticFocus()
        focus.makeKeyError = ComputerUseError.message("make key failed")
        var bodyRuns = 0

        XCTAssertThrowsError(try deliver(focus: focus) { bodyRuns += 1; return nil }) { error in
            XCTAssertEqual((error as? ComputerUseError)?.errorDescription, "make key failed")
        }
        XCTAssertEqual(focus.calls, ["begin", "makeKey", "end"])
        XCTAssertEqual(bodyRuns, 0)
    }

    func testUnconfirmedKeyWindowReleasesTheTargetOnceAndSendsNothing() {
        let focus = FakeSyntheticFocus()
        var bodyRuns = 0

        XCTAssertThrowsError(
            try deliver(focus: focus, focusedWindowID: { _ in 7 }) { bodyRuns += 1; return nil }
        ) { error in
            guard case let .stateUnavailable(message)? = error as? ComputerUseError else {
                return XCTFail("\(error)")
            }
            XCTAssertTrue(message.contains("could not make the snapshot's window the key window"), message)
        }
        XCTAssertEqual(focus.calls, ["begin", "makeKey", "end"])
        XCTAssertEqual(bodyRuns, 0)
    }

    func testFailedBodyReleasesTheTargetOnceAndRethrows() {
        let focus = FakeSyntheticFocus()

        XCTAssertThrowsError(try deliver(focus: focus) { throw ComputerUseError.message("keys failed") }) { error in
            XCTAssertEqual((error as? ComputerUseError)?.errorDescription, "keys failed")
        }
        XCTAssertEqual(focus.calls, ["begin", "makeKey", "end"])
    }

    func testFailedReleaseOfAFailedSequenceKeepsTheOriginalError() {
        let focus = FakeSyntheticFocus()
        focus.makeKeyError = ComputerUseError.message("make key failed")
        focus.endError = ComputerUseError.message("end failed")

        XCTAssertThrowsError(try deliver(focus: focus) { nil }) { error in
            XCTAssertEqual((error as? ComputerUseError)?.errorDescription, "make key failed")
        }
        XCTAssertEqual(focus.calls, ["begin", "makeKey", "end"])
    }

    /// The keys were delivered, so a failed release must be a warning on a successful delivery, never a thrown error
    /// that would invite a resend.
    func testFailedReleaseAfterDeliveryIsAWarningNotAnError() throws {
        let focus = FakeSyntheticFocus()
        focus.endError = ComputerUseError.message("OSStatus -600")
        var bodyRuns = 0

        let delivery = try deliver(focus: focus) {
            bodyRuns += 1
            return "Note: may have run"
        }

        XCTAssertEqual(delivery.releaseWarning, "OSStatus -600")
        XCTAssertEqual(delivery.outcomeNote, "Note: may have run")
        XCTAssertEqual(focus.calls, ["begin", "makeKey", "end"])
        XCTAssertEqual(bodyRuns, 1)
    }

    func testFrontmostTargetWithKeyWindowSendsWithoutAnySyntheticFocus() throws {
        let focus = FakeSyntheticFocus()
        var bodyRuns = 0

        let delivery = try deliver(focus: focus, frontmostPID: Self.deliveryTarget.pid) {
            bodyRuns += 1
            return nil
        }

        XCTAssertEqual(delivery, SkyKeyboardDelivery(releaseWarning: nil))
        XCTAssertEqual(focus.calls, [])
        XCTAssertEqual(bodyRuns, 1)
    }

    /// Making a window key in the frontmost app would change the user's own key window, so it is refused instead.
    func testFrontmostTargetWhoseWindowIsNotKeyIsRefusedWithoutAnySyntheticFocus() {
        let focus = FakeSyntheticFocus()
        var bodyRuns = 0

        XCTAssertThrowsError(
            try deliver(focus: focus, frontmostPID: Self.deliveryTarget.pid, focusedWindowID: { _ in 7 }) {
                bodyRuns += 1
                return nil
            }
        )
        XCTAssertEqual(focus.calls, [])
        XCTAssertEqual(bodyRuns, 0)
    }

    func testFailedValidationPostsNoRecord() {
        let focus = FakeSyntheticFocus()
        var bodyRuns = 0

        XCTAssertThrowsError(
            try deliver(focus: focus, validate: { _ in throw ComputerUseError.stateUnavailable("minimized") }) {
                bodyRuns += 1
                return nil
            }
        )
        XCTAssertEqual(focus.calls, [])
        XCTAssertEqual(bodyRuns, 0)
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
