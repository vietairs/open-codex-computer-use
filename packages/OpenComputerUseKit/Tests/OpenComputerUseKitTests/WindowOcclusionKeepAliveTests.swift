import CoreGraphics
import Foundation
import XCTest
@testable import OpenComputerUseKit

private struct KeepAliveSessionProvider: MacSessionStateProvider {
    var isLocked = false
    var isUnknown = false

    func currentSnapshot() -> MacSessionSnapshot {
        MacSessionSnapshot(isLocked: isLocked || isUnknown, isUnknown: isUnknown, rawKeysSeen: [])
    }
}

/// Records every occlusion call in order, together with the journal writes, so tests can check the write-ahead order.
private final class KeepAliveEventLog {
    var events: [String] = []
}

private final class FakeOcclusionControl: WindowOcclusionControlling {
    var occlusionAvailability: WindowServerFeatureAvailability = .available
    /// The previous state the next disable call reports.
    var previousState: Bool? = true
    var failingEnables: Set<CGWindowID> = []
    var failingDisables: Set<CGWindowID> = []
    let log: KeepAliveEventLog

    init(log: KeepAliveEventLog) {
        self.log = log
    }

    func setWindowOcclusionNotificationsEnabled(_ enabled: Bool, windowID: CGWindowID) throws -> Bool? {
        log.events.append("\(enabled ? "enable" : "disable") \(windowID)")
        if enabled, failingEnables.contains(windowID) {
            throw ComputerUseError.message("enable failed")
        }
        if !enabled, failingDisables.contains(windowID) {
            throw ComputerUseError.message("disable failed")
        }
        return enabled ? false : previousState
    }
}

private final class FakeRestoreJournal: OcclusionRestoreJournaling {
    var written: [OcclusionRestoreEntry] = []
    var abandoned: [OcclusionRestoreEntry] = []
    var failsWrites = false
    var discarded = false
    var takeCount = 0
    let log: KeepAliveEventLog

    init(log: KeepAliveEventLog) {
        self.log = log
    }

    func write(_ entries: [OcclusionRestoreEntry]) throws {
        if failsWrites {
            throw ComputerUseError.message("journal write failed")
        }
        written = entries.sorted { $0.windowID < $1.windowID }
        log.events.append("journal \(written.map(\.windowID))")
    }

    func takeAbandonedEntries() -> [OcclusionRestoreEntry] {
        takeCount += 1
        defer { abandoned = [] }
        return abandoned
    }

    func discard() {
        discarded = true
    }
}

final class WindowOcclusionKeepAliveTests: XCTestCase {
    private let ownerA = UUID()
    private let ownerB = UUID()
    private var log = KeepAliveEventLog()
    private var control: FakeOcclusionControl!
    private var journal: FakeRestoreJournal!
    private var windowOwners: [CGWindowID: pid_t] = [:]
    /// Windows whose owner cannot be read, as when the window list is momentarily unavailable.
    private var unreadableOwners: Set<CGWindowID> = []

    override func setUp() {
        super.setUp()
        log = KeepAliveEventLog()
        control = FakeOcclusionControl(log: log)
        journal = FakeRestoreJournal(log: log)
        windowOwners = [10: 500, 11: 500, 12: 600]
        unreadableOwners = []
    }

    private func makeKeepAlive(session: MacSessionStateProvider = KeepAliveSessionProvider()) -> WindowOcclusionKeepAlive {
        WindowOcclusionKeepAlive(
            control: control,
            journal: journal,
            sessionState: session,
            windowOwner: { [unowned self] windowID in
                if self.unreadableOwners.contains(windowID) {
                    return .unknown
                }
                return self.windowOwners[windowID].map(WindowOwnerLookup.owner) ?? .gone
            }
        )
    }

    // MARK: - Geometry

    func testUnoccludedWhenAnySamplePointIsUncovered() {
        let bounds = CGRect(x: 100, y: 100, width: 400, height: 300)
        XCTAssertTrue(windowLooksUnoccluded(bounds: bounds, coveringBounds: []))
        XCTAssertTrue(windowLooksUnoccluded(
            bounds: bounds,
            coveringBounds: [CGRect(x: 100, y: 100, width: 350, height: 300)]
        ))
        XCTAssertFalse(windowLooksUnoccluded(
            bounds: bounds,
            coveringBounds: [CGRect(x: 0, y: 0, width: 1000, height: 1000)]
        ))
        XCTAssertFalse(windowLooksUnoccluded(
            bounds: bounds,
            coveringBounds: [CGRect(x: 100, y: 100, width: 200, height: 300), CGRect(x: 300, y: 100, width: 200, height: 300)]
        ))
    }

    func testEmptyOrNonFiniteBoundsNeverLookUnoccluded() {
        XCTAssertFalse(windowLooksUnoccluded(bounds: .zero, coveringBounds: []))
        XCTAssertFalse(windowLooksUnoccluded(bounds: CGRect(x: 0, y: 0, width: 0, height: 100), coveringBounds: []))
        XCTAssertFalse(windowLooksUnoccluded(bounds: CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100), coveringBounds: []))
        XCTAssertFalse(windowLooksUnoccluded(bounds: CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 100), coveringBounds: []))
        XCTAssertFalse(windowLooksUnoccluded(bounds: CGRect(x: 0, y: 0, width: 100, height: CGFloat.nan), coveringBounds: []))
    }

    func testNonFiniteCoveringRectFailsClosed() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertFalse(windowLooksUnoccluded(bounds: bounds, coveringBounds: [CGRect(x: CGFloat.nan, y: 0, width: 10, height: 10)]))
        XCTAssertFalse(windowLooksUnoccluded(
            bounds: bounds,
            coveringBounds: [CGRect(x: 500, y: 500, width: CGFloat.infinity, height: 10)]
        ))
        // A finite zero-size rect covers nothing.
        XCTAssertTrue(windowLooksUnoccluded(bounds: bounds, coveringBounds: [CGRect(x: 10, y: 10, width: 0, height: 0)]))
    }

    private func probes(
        minimized: Bool = false,
        hidden: Bool = false,
        unlocked: Bool = true,
        currentSpace: Bool? = true,
        covering: [CGRect] = [],
        calls: KeepAliveEventLog? = nil
    ) -> WindowVisibilityProbes {
        WindowVisibilityProbes(
            isMinimized: { calls?.events.append("minimized"); return minimized },
            appIsHidden: { calls?.events.append("hidden"); return hidden },
            sessionIsUnlocked: { calls?.events.append("unlocked"); return unlocked },
            isOnCurrentSpace: { calls?.events.append("space"); return currentSpace },
            coveringBounds: { calls?.events.append("covering"); return covering }
        )
    }

    func testVisibilityRequiresEveryCheck() {
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 200)
        XCTAssertTrue(windowIsVisibleToItsApp(bounds: bounds, isOnscreen: true, isOffStage: false, probes: probes()))

        XCTAssertFalse(windowIsVisibleToItsApp(bounds: bounds, isOnscreen: false, isOffStage: false, probes: probes()))
        XCTAssertFalse(windowIsVisibleToItsApp(bounds: bounds, isOnscreen: true, isOffStage: true, probes: probes()))
        XCTAssertFalse(windowIsVisibleToItsApp(
            bounds: CGRect(x: 0, y: 0, width: CGFloat.nan, height: 200), isOnscreen: true, isOffStage: false, probes: probes()
        ))
        XCTAssertFalse(windowIsVisibleToItsApp(bounds: bounds, isOnscreen: true, isOffStage: false, probes: probes(minimized: true)))
        XCTAssertFalse(windowIsVisibleToItsApp(bounds: bounds, isOnscreen: true, isOffStage: false, probes: probes(hidden: true)))
        XCTAssertFalse(windowIsVisibleToItsApp(bounds: bounds, isOnscreen: true, isOffStage: false, probes: probes(unlocked: false)))
        XCTAssertFalse(windowIsVisibleToItsApp(bounds: bounds, isOnscreen: true, isOffStage: false, probes: probes(currentSpace: false)))
        XCTAssertFalse(windowIsVisibleToItsApp(bounds: bounds, isOnscreen: true, isOffStage: false, probes: probes(currentSpace: nil)))
        XCTAssertFalse(windowIsVisibleToItsApp(
            bounds: bounds, isOnscreen: true, isOffStage: false, probes: probes(covering: [CGRect(x: -10, y: -10, width: 400, height: 400)])
        ))
    }

    func testVisibilityReadsNothingLiveForAnOffscreenWindow() {
        let calls = KeepAliveEventLog()
        _ = windowIsVisibleToItsApp(
            bounds: CGRect(x: 0, y: 0, width: 300, height: 200), isOnscreen: false, isOffStage: false, probes: probes(calls: calls)
        )
        XCTAssertEqual(calls.events, [])

        _ = windowIsVisibleToItsApp(
            bounds: CGRect(x: 0, y: 0, width: 300, height: 200), isOnscreen: true, isOffStage: false,
            probes: probes(currentSpace: false, calls: calls)
        )
        XCTAssertEqual(calls.events, ["minimized", "hidden", "unlocked", "space"])
    }

    // MARK: - Pins

    func testPinWritesTheJournalBeforeTheWindowServerCall() {
        let keepAlive = makeKeepAlive()
        XCTAssertTrue(keepAlive.pin(windowID: 10, windowOwnerPID: 500, owner: ownerA))
        XCTAssertEqual(log.events, ["journal [10]", "disable 10"])
        XCTAssertEqual(journal.written, [OcclusionRestoreEntry(windowID: 10, ownerPID: 500)])
        XCTAssertTrue(keepAlive.isPinned(windowID: 10))
    }

    func testTwoOwnersShareOnePinAndTheLastReleaseRestores() {
        let keepAlive = makeKeepAlive()
        XCTAssertTrue(keepAlive.pin(windowID: 10, windowOwnerPID: 500, owner: ownerA))
        XCTAssertTrue(keepAlive.retainExistingPin(windowID: 10, owner: ownerB))
        XCTAssertFalse(keepAlive.retainExistingPin(windowID: 11, owner: ownerB))
        XCTAssertEqual(log.events.filter { $0.hasPrefix("disable") }, ["disable 10"])

        keepAlive.release(owner: ownerA)
        XCTAssertTrue(keepAlive.isPinned(windowID: 10), "another owner still holds the window")
        XCTAssertFalse(log.events.contains("enable 10"))
        XCTAssertEqual(keepAlive.pinnedWindowIDs(owner: ownerA), [])
        XCTAssertEqual(keepAlive.pinnedWindowIDs(owner: ownerB), [10])

        keepAlive.release(owner: ownerB)
        XCTAssertFalse(keepAlive.isPinned(windowID: 10))
        XCTAssertEqual(log.events.filter { $0 == "enable 10" }.count, 1)
        XCTAssertEqual(journal.written, [])
    }

    func testReleaseOnlyTouchesTheOwnersWindows() {
        let keepAlive = makeKeepAlive()
        keepAlive.pin(windowID: 10, windowOwnerPID: 500, owner: ownerA)
        keepAlive.pin(windowID: 12, windowOwnerPID: 600, owner: ownerB)

        keepAlive.release(owner: ownerA)

        XCTAssertFalse(keepAlive.isPinned(windowID: 10))
        XCTAssertTrue(keepAlive.isPinned(windowID: 12))
        XCTAssertFalse(log.events.contains("enable 12"))
        XCTAssertEqual(journal.written, [OcclusionRestoreEntry(windowID: 12, ownerPID: 600)])
    }

    func testAlreadyDisabledWindowIsLeftToItsHolder() {
        control.previousState = false
        let keepAlive = makeKeepAlive()

        XCTAssertFalse(keepAlive.pin(windowID: 10, windowOwnerPID: 500, owner: ownerA))
        XCTAssertFalse(keepAlive.isPinned(windowID: 10))
        XCTAssertEqual(journal.written, [])

        keepAlive.releaseAll()
        XCTAssertFalse(log.events.contains("enable 10"), "never turn back on what another holder turned off")
    }

    func testUnknownPreviousStateIsRestoredToEnabled() {
        control.previousState = nil
        let keepAlive = makeKeepAlive()

        XCTAssertTrue(keepAlive.pin(windowID: 10, windowOwnerPID: 500, owner: ownerA))
        keepAlive.release(owner: ownerA)

        XCTAssertEqual(log.events.last, "journal []")
        XCTAssertTrue(log.events.contains("enable 10"))
    }

    func testFailedRestoreIsRetainedAndRetried() {
        let keepAlive = makeKeepAlive()
        keepAlive.pin(windowID: 10, windowOwnerPID: 500, owner: ownerA)
        control.failingEnables = [10]

        keepAlive.release(owner: ownerA)
        XCTAssertFalse(keepAlive.isPinned(windowID: 10))
        XCTAssertEqual(journal.written, [OcclusionRestoreEntry(windowID: 10, ownerPID: 500)], "a failed restore stays journaled")

        control.failingEnables = []
        keepAlive.release(owner: ownerB)
        XCTAssertEqual(log.events.filter { $0 == "enable 10" }.count, 2)
        XCTAssertEqual(journal.written, [])
    }

    func testFailedRestoreOfAVanishedWindowIsDropped() {
        let keepAlive = makeKeepAlive()
        keepAlive.pin(windowID: 10, windowOwnerPID: 500, owner: ownerA)
        control.failingEnables = [10]
        keepAlive.release(owner: ownerA)

        windowOwners[10] = nil
        keepAlive.releaseAll()

        XCTAssertEqual(journal.written, [])
        XCTAssertEqual(log.events.filter { $0 == "enable 10" }.count, 1, "a window that is gone is not called again")
    }

    func testWindowIDReusedByAnotherAppIsNotRestored() {
        let keepAlive = makeKeepAlive()
        keepAlive.pin(windowID: 10, windowOwnerPID: 500, owner: ownerA)
        windowOwners[10] = 999

        keepAlive.release(owner: ownerA)

        XCTAssertFalse(log.events.contains("enable 10"))
        XCTAssertEqual(journal.written, [])
    }

    func testRepinAfterFailedRestoreTakesTheWindowBack() {
        let keepAlive = makeKeepAlive()
        keepAlive.pin(windowID: 10, windowOwnerPID: 500, owner: ownerA)
        control.failingEnables = [10]
        keepAlive.release(owner: ownerA)

        XCTAssertTrue(keepAlive.pin(windowID: 10, windowOwnerPID: 500, owner: ownerB))
        XCTAssertEqual(log.events.filter { $0 == "disable 10" }.count, 1, "notifications are still off; no second call")
        XCTAssertEqual(keepAlive.pinnedWindowIDs(owner: ownerB), [10])
    }

    func testLockedOrUnknownSessionNeverPins() {
        for session in [KeepAliveSessionProvider(isLocked: true), KeepAliveSessionProvider(isUnknown: true)] {
            let keepAlive = makeKeepAlive(session: session)
            XCTAssertFalse(keepAlive.pin(windowID: 10, windowOwnerPID: 500, owner: ownerA))
            XCTAssertFalse(keepAlive.isPinned(windowID: 10))
        }
        XCTAssertEqual(log.events, [])
    }

    func testUnavailableOcclusionCallNeverPins() {
        control.occlusionAvailability = WindowServerFeatureAvailability(unavailableReason: "not verified")
        let keepAlive = makeKeepAlive()

        XCTAssertFalse(keepAlive.isAvailable)
        XCTAssertFalse(keepAlive.pin(windowID: 10, windowOwnerPID: 500, owner: ownerA))
        XCTAssertEqual(log.events, [])
    }

    func testJournalWriteFailurePinsNothing() {
        journal.failsWrites = true
        let keepAlive = makeKeepAlive()

        XCTAssertFalse(keepAlive.pin(windowID: 10, windowOwnerPID: 500, owner: ownerA))
        XCTAssertEqual(log.events, [], "no WindowServer write without a journal entry")
    }

    func testFailedDisableClearsTheJournalEntry() {
        control.failingDisables = [10]
        let keepAlive = makeKeepAlive()

        XCTAssertFalse(keepAlive.pin(windowID: 10, windowOwnerPID: 500, owner: ownerA))
        XCTAssertEqual(journal.written, [])
    }

    func testAbandonedJournalsAreRestoredOnceBeforeTheFirstPin() {
        journal.abandoned = [
            OcclusionRestoreEntry(windowID: 11, ownerPID: 500),
            OcclusionRestoreEntry(windowID: 12, ownerPID: 777),
            OcclusionRestoreEntry(windowID: 13, ownerPID: 500),
        ]
        let keepAlive = makeKeepAlive()

        keepAlive.pin(windowID: 10, windowOwnerPID: 500, owner: ownerA)
        keepAlive.pin(windowID: 10, windowOwnerPID: 500, owner: ownerB)
        keepAlive.recoverAbandonedJournals()

        XCTAssertEqual(journal.takeCount, 1)
        // 12 is owned by another pid now, 13 no longer exists.
        XCTAssertEqual(log.events.filter { $0.hasPrefix("enable") }, ["enable 11"])
        XCTAssertEqual(log.events.first, "enable 11", "recovery runs before the first pin")
    }

    func testRecoveryLeavesAWindowThisProcessPinnedAlone() {
        let keepAlive = makeKeepAlive()
        keepAlive.pin(windowID: 10, windowOwnerPID: 500, owner: ownerA)
        journal.abandoned = [OcclusionRestoreEntry(windowID: 10, ownerPID: 500)]

        keepAlive.recoverAbandonedJournals()

        XCTAssertFalse(log.events.contains("enable 10"))
    }

    func testReleaseAllAndExitCleanup() {
        let keepAlive = makeKeepAlive()
        keepAlive.pin(windowID: 10, windowOwnerPID: 500, owner: ownerA)
        keepAlive.pin(windowID: 12, windowOwnerPID: 600, owner: ownerB)
        control.failingEnables = [12]

        keepAlive.finishAtExit()
        XCTAssertFalse(journal.discarded, "a journal that still lists a failed restore is kept for the next process")
        XCTAssertEqual(journal.written, [OcclusionRestoreEntry(windowID: 12, ownerPID: 600)])

        control.failingEnables = []
        keepAlive.finishAtExit()
        XCTAssertTrue(journal.discarded)
        XCTAssertFalse(keepAlive.isPinned(windowID: 10))
        XCTAssertFalse(keepAlive.isPinned(windowID: 12))
    }

    func testWindowOwnerLookupTellsAMissingListFromAMissingWindow() {
        let entry: [String: Any] = [
            kCGWindowNumber as String: NSNumber(value: UInt32(10)),
            kCGWindowOwnerPID as String: NSNumber(value: Int32(500)),
        ]
        XCTAssertEqual(windowOwnerLookup(windowID: 10, windowInfo: [entry]), .owner(500))
        XCTAssertEqual(windowOwnerLookup(windowID: 11, windowInfo: [entry]), .gone)
        XCTAssertEqual(windowOwnerLookup(windowID: 11, windowInfo: []), .gone)
        XCTAssertEqual(windowOwnerLookup(windowID: 10, windowInfo: nil), .unknown, "a failed list read is not a gone window")
        XCTAssertEqual(
            windowOwnerLookup(windowID: 10, windowInfo: [[kCGWindowNumber as String: NSNumber(value: UInt32(10))]]),
            .unknown
        )
    }

    func testUnreadableOwnerKeepsTheWindowForALaterRelease() {
        let keepAlive = makeKeepAlive()
        keepAlive.pin(windowID: 10, windowOwnerPID: 500, owner: ownerA)
        unreadableOwners = [10]

        keepAlive.release(owner: ownerA)
        XCTAssertFalse(keepAlive.isPinned(windowID: 10))
        XCTAssertFalse(log.events.contains("enable 10"))
        XCTAssertEqual(journal.written, [OcclusionRestoreEntry(windowID: 10, ownerPID: 500)], "the window stays journaled")

        unreadableOwners = []
        keepAlive.release(owner: ownerB)
        XCTAssertEqual(log.events.filter { $0 == "enable 10" }.count, 1)
        XCTAssertEqual(journal.written, [])
    }

    func testFailedRecoveryRestoreIsAdoptedJournaledAndRetried() {
        journal.abandoned = [OcclusionRestoreEntry(windowID: 11, ownerPID: 500), OcclusionRestoreEntry(windowID: 12, ownerPID: 600)]
        control.failingEnables = [11]
        unreadableOwners = [12]
        let keepAlive = makeKeepAlive()

        keepAlive.recoverAbandonedJournals()
        XCTAssertEqual(journal.written, [
            OcclusionRestoreEntry(windowID: 11, ownerPID: 500),
            OcclusionRestoreEntry(windowID: 12, ownerPID: 600),
        ], "restores that could not finish move into this process's journal")

        control.failingEnables = []
        unreadableOwners = []
        keepAlive.release(owner: ownerA)
        XCTAssertEqual(log.events.filter { $0 == "enable 11" }.count, 2)
        XCTAssertEqual(log.events.filter { $0 == "enable 12" }.count, 1)
        XCTAssertEqual(journal.written, [])
    }

    func testSuccessfulRecoveryWritesNoJournal() {
        journal.abandoned = [OcclusionRestoreEntry(windowID: 11, ownerPID: 500)]
        let keepAlive = makeKeepAlive()

        keepAlive.recoverAbandonedJournals()

        XCTAssertEqual(log.events, ["enable 11"])
    }

    func testLockWatchReleasesEveryPinOnceTheSessionIsNotUnlocked() {
        final class SwitchableSession: MacSessionStateProvider, @unchecked Sendable {
            var snapshot = MacSessionSnapshot(isLocked: false, isUnknown: false, rawKeysSeen: [])
            func currentSnapshot() -> MacSessionSnapshot { snapshot }
        }
        let session = SwitchableSession()
        let keepAlive = makeKeepAlive(session: session)
        keepAlive.pin(windowID: 10, windowOwnerPID: 500, owner: ownerA)
        keepAlive.pin(windowID: 12, windowOwnerPID: 600, owner: ownerB)

        keepAlive.releaseAllUnlessStrictlyUnlocked()
        XCTAssertTrue(keepAlive.isPinned(windowID: 10), "nothing changes while the session is unlocked")

        session.snapshot = MacSessionSnapshot(isLocked: true, isUnknown: true, rawKeysSeen: [])
        keepAlive.releaseAllUnlessStrictlyUnlocked()
        XCTAssertFalse(keepAlive.isPinned(windowID: 10))
        XCTAssertFalse(keepAlive.isPinned(windowID: 12))
        XCTAssertTrue(log.events.contains("enable 10"))
        XCTAssertTrue(log.events.contains("enable 12"))
    }

    // MARK: - Snapshot pinning

    private func snapshotKeepAlive(_ keepAlive: WindowOcclusionKeepAlive, owner: UUID) -> SnapshotKeepAlive {
        SnapshotKeepAlive(keeper: keepAlive, owner: owner)
    }

    func testSnapshotPinsOnlyTheVisibleTreeWindow() {
        let keepAlive = makeKeepAlive()
        var visibilityReads = 0

        XCTAssertFalse(keepSnapshotWindowVisible(
            keepAlive: snapshotKeepAlive(keepAlive, owner: ownerA), windowID: 10, isAccessibilityRoot: false,
            windowOwnerPID: 500, isVisibleToItsApp: { visibilityReads += 1; return true }
        ), "a captured window that is not the tree's root is never pinned")
        XCTAssertEqual(visibilityReads, 0)

        XCTAssertFalse(keepSnapshotWindowVisible(
            keepAlive: snapshotKeepAlive(keepAlive, owner: ownerA), windowID: 10, isAccessibilityRoot: true,
            windowOwnerPID: 500, isVisibleToItsApp: { false }
        ))
        XCTAssertFalse(keepAlive.isPinned(windowID: 10))

        XCTAssertTrue(keepSnapshotWindowVisible(
            keepAlive: snapshotKeepAlive(keepAlive, owner: ownerA), windowID: 10, isAccessibilityRoot: true,
            windowOwnerPID: 500, isVisibleToItsApp: { true }
        ))
        XCTAssertEqual(keepAlive.pinnedWindowIDs(owner: ownerA), [10])
    }

    func testSnapshotJoinsAnExistingPinEvenWhenTheWindowIsNowCovered() {
        let keepAlive = makeKeepAlive()
        keepAlive.pin(windowID: 10, windowOwnerPID: 500, owner: ownerA)

        XCTAssertTrue(keepSnapshotWindowVisible(
            keepAlive: snapshotKeepAlive(keepAlive, owner: ownerB), windowID: 10, isAccessibilityRoot: true,
            windowOwnerPID: 500, isVisibleToItsApp: { XCTFail("a pinned window needs no visibility check"); return false }
        ))
        XCTAssertEqual(keepAlive.pinnedWindowIDs(owner: ownerB), [10])
    }

    func testSnapshotWithoutKeepAliveReportsVisibilityAndPinsNothing() {
        XCTAssertTrue(keepSnapshotWindowVisible(
            keepAlive: nil, windowID: 10, isAccessibilityRoot: true, windowOwnerPID: 500, isVisibleToItsApp: { true }
        ))
        XCTAssertEqual(log.events, [])
    }

    // MARK: - Session lifecycle

    func testOneShotServiceHoldsNoKeepAlive() {
        let service = ComputerUseService(windowKeepAlive: nil)
        service.releaseBackgroundWindowState()
        XCTAssertEqual(log.events, [])
    }

    func testEndSessionReleasesOnlyThatServersPins() {
        let keepAlive = makeKeepAlive()
        let serviceA = ComputerUseService(windowKeepAlive: keepAlive)
        let serviceB = ComputerUseService(windowKeepAlive: keepAlive)
        let serverA = StdioMCPServer(service: serviceA)
        let serverB = StdioMCPServer(service: serviceB)
        keepAlive.pin(windowID: 10, windowOwnerPID: 500, owner: serviceA.backgroundStateOwner)
        keepAlive.pin(windowID: 12, windowOwnerPID: 600, owner: serviceB.backgroundStateOwner)
        XCTAssertTrue(keepAlive.retainExistingPin(windowID: 12, owner: serviceA.backgroundStateOwner))

        serverA.endSession()

        XCTAssertFalse(keepAlive.isPinned(windowID: 10))
        XCTAssertTrue(keepAlive.isPinned(windowID: 12), "session B still holds its window")
        XCTAssertFalse(log.events.contains("enable 12"))

        serverB.endSession()
        XCTAssertFalse(keepAlive.isPinned(windowID: 12))
    }

    func testDiscardedServiceReleasesItsPins() {
        let keepAlive = makeKeepAlive()
        do {
            let service = ComputerUseService(windowKeepAlive: keepAlive)
            keepAlive.pin(windowID: 10, windowOwnerPID: 500, owner: service.backgroundStateOwner)
            XCTAssertTrue(keepAlive.isPinned(windowID: 10))
        }
        XCTAssertFalse(keepAlive.isPinned(windowID: 10))
        XCTAssertTrue(log.events.contains("enable 10"))
    }
}
