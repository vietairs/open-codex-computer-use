import CoreGraphics
import Foundation
import XCTest
@testable import OpenComputerUseKit

/// `SkyClickDispatcher.validate` with every live read replaced, so each refusal is checked without posting events.
final class SkyClickValidationTests: XCTestCase {
    private static let target = SkyClickTarget(
        screenPoint: CGPoint(x: 150, y: 150),
        windowPoint: CGPoint(x: 50, y: 50),
        windowBounds: CGRect(x: 100, y: 100, width: 400, height: 300),
        windowID: 42,
        pid: 4_242
    )
    private static var unlocked: MacSessionSnapshot {
        MacSessionSnapshot(isLocked: false, isUnknown: false, rawKeysSeen: [])
    }
    private static var locked: MacSessionSnapshot {
        MacSessionSnapshot(isLocked: true, isUnknown: false, rawKeysSeen: [])
    }

    private struct Reads {
        var isOnscreen = true
        var isMinimized: Bool? = false
        var session = SkyClickValidationTests.unlocked
        var isOnCurrentSpace: Bool? = true
        var frontmostPID: pid_t? = 1
        var focusedWindowID: CGWindowID? = 7
        var windowError: Error?
    }

    private func validate(_ reads: Reads, log: ((String) -> Void)? = nil) throws -> Bool {
        try SkyClickDispatcher.validate(
            target: Self.target,
            probes: SkyClickValidationProbes(
                targetWindow: { _, _ in
                    log?("window")
                    if let error = reads.windowError {
                        throw error
                    }
                    return SkyLightTargetWindowState(isOnscreen: reads.isOnscreen, isMinimized: reads.isMinimized)
                },
                session: { log?("session"); return reads.session },
                isOnCurrentSpace: { _ in log?("space"); return reads.isOnCurrentSpace },
                frontmostPID: { log?("frontmost"); return reads.frontmostPID },
                focusedWindowID: { _ in log?("focused"); return reads.focusedWindowID }
            )
        )
    }

    private func assertRefused(_ reads: Reads, containing text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try validate(reads), file: file, line: line) { error in
            let message = (error as? ComputerUseError)?.errorDescription ?? ""
            XCTAssertTrue(message.contains(text), "unexpected message: \(message)", file: file, line: line)
        }
    }

    // MARK: - Pure rules

    func testOffscreenTargetNeedsAPositiveNotMinimizedRead() {
        XCTAssertTrue(skyClickTargetVisibilityAllowed(isOnscreen: true, isMinimized: false))
        XCTAssertTrue(skyClickTargetVisibilityAllowed(isOnscreen: true, isMinimized: nil))
        XCTAssertFalse(skyClickTargetVisibilityAllowed(isOnscreen: true, isMinimized: true))
        XCTAssertTrue(skyClickTargetVisibilityAllowed(isOnscreen: false, isMinimized: false))
        XCTAssertFalse(skyClickTargetVisibilityAllowed(isOnscreen: false, isMinimized: nil), "an unreadable state fails closed")
        XCTAssertFalse(skyClickTargetVisibilityAllowed(isOnscreen: false, isMinimized: true))
    }

    func testFrontmostTargetMustBeFocusedAndOnTheCurrentSpace() {
        XCTAssertTrue(skyClickFrontmostTargetAllowed(focusedWindowID: 42, targetWindowID: 42, isOnCurrentSpace: true))
        XCTAssertFalse(skyClickFrontmostTargetAllowed(focusedWindowID: 7, targetWindowID: 42, isOnCurrentSpace: true))
        XCTAssertFalse(skyClickFrontmostTargetAllowed(focusedWindowID: nil, targetWindowID: 42, isOnCurrentSpace: true))
        XCTAssertFalse(skyClickFrontmostTargetAllowed(focusedWindowID: 42, targetWindowID: 42, isOnCurrentSpace: false))
        XCTAssertFalse(skyClickFrontmostTargetAllowed(focusedWindowID: 42, targetWindowID: 42, isOnCurrentSpace: nil))
    }

    // MARK: - Validation sequence

    func testBackgroundTargetUsesSyntheticFocus() throws {
        var calls: [String] = []
        XCTAssertTrue(try validate(Reads(), log: { calls.append($0) }))
        XCTAssertEqual(calls, ["window", "session", "frontmost"], "the Space is not read when nothing depends on it")
    }

    func testWindowRefusalIsPassedThrough() {
        var reads = Reads()
        reads.windowError = ComputerUseError.stateUnavailable("sky_click target window is minimized")
        assertRefused(reads, containing: "minimized")
    }

    func testOffscreenTargetWithUnknownMinimizedStateIsRefused() throws {
        var reads = Reads()
        reads.isOnscreen = false
        reads.isMinimized = nil
        assertRefused(reads, containing: "could not confirm that it is not minimized")

        reads.isMinimized = false
        XCTAssertTrue(try validate(reads))
    }

    func testLockedSessionAllowsOnlyAnOnscreenWindowOnTheCurrentSpace() throws {
        var reads = Reads()
        reads.session = Self.locked
        XCTAssertTrue(try validate(reads), "the lock opt-in keeps covering the current Space")

        reads.isOnCurrentSpace = false
        assertRefused(reads, containing: "cannot run while macOS is locked")

        reads.isOnCurrentSpace = nil
        assertRefused(reads, containing: "cannot run while macOS is locked")

        reads.isOnCurrentSpace = true
        reads.isOnscreen = false
        assertRefused(reads, containing: "cannot run while macOS is locked")
    }

    func testUnlockedSessionAcceptsAnotherSpace() throws {
        var reads = Reads()
        reads.isOnCurrentSpace = false
        XCTAssertTrue(try validate(reads))
    }

    func testFrontmostAppNeedsItsFocusedWindowOnTheCurrentSpace() throws {
        var reads = Reads()
        reads.frontmostPID = Self.target.pid
        reads.focusedWindowID = Self.target.windowID
        XCTAssertFalse(try validate(reads), "a frontmost target is clicked without synthetic focus")

        reads.focusedWindowID = 7
        assertRefused(reads, containing: "not its focused window on the current Space")

        reads.focusedWindowID = Self.target.windowID
        reads.isOnCurrentSpace = false
        assertRefused(reads, containing: "not its focused window on the current Space")

        reads.isOnCurrentSpace = nil
        assertRefused(reads, containing: "not its focused window on the current Space")
    }

    func testSpaceIsReadOnceWhenBothRulesNeedIt() throws {
        var reads = Reads()
        reads.session = Self.locked
        reads.frontmostPID = Self.target.pid
        reads.focusedWindowID = Self.target.windowID
        var calls: [String] = []
        XCTAssertFalse(try validate(reads, log: { calls.append($0) }))
        XCTAssertEqual(calls.filter { $0 == "space" }.count, 1)
    }

    func testBadGeometryIsRefusedBeforeAnyRead() {
        var calls: [String] = []
        let target = SkyClickTarget(
            screenPoint: CGPoint(x: CGFloat.nan, y: 0),
            windowPoint: CGPoint(x: 10, y: 10),
            windowBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
            windowID: 42,
            pid: 4_242
        )
        XCTAssertThrowsError(
            try SkyClickDispatcher.validate(
                target: target,
                probes: SkyClickValidationProbes(
                    targetWindow: { _, _ in calls.append("window"); return SkyLightTargetWindowState(isOnscreen: true, isMinimized: false) },
                    session: { calls.append("session"); return Self.unlocked },
                    isOnCurrentSpace: { _ in calls.append("space"); return true },
                    frontmostPID: { calls.append("frontmost"); return nil },
                    focusedWindowID: { _ in calls.append("focused"); return nil }
                )
            )
        )
        XCTAssertEqual(calls, [])
    }
}
