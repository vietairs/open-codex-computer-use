import AppKit
import CoreGraphics
import Foundation
import XCTest
@testable import OpenComputerUseKit

/// Opt-in live regression: a snapshot taken while an isolated Chrome window is visible pins its visible state, so
/// after the fixture app fully covers it the next snapshot still holds the web content and the page stays visible.
/// Releasing the session's owner unpins the window. Run from Terminal.app with Accessibility and Screen Recording
/// granted to the test runner:
/// `OPEN_COMPUTER_USE_RUN_OCCLUSION_LIVE_TEST=1 swift test --filter OcclusionKeepAliveLiveTests`
@MainActor
final class OcclusionKeepAliveLiveTests: XCTestCase {
    func testCoveredChromeKeepsWebContentAfterVisibleSnapshot() throws {
        guard ProcessInfo.processInfo.environment["OPEN_COMPUTER_USE_RUN_OCCLUSION_LIVE_TEST"] == "1" else {
            throw XCTSkip("Set OPEN_COMPUTER_USE_RUN_OCCLUSION_LIVE_TEST=1 to run the isolated Chrome live test")
        }
        let keepAlive = WindowOcclusionKeepAlive.shared
        guard keepAlive.isAvailable else {
            throw XCTSkip(
                "SkyLight occlusion call unavailable: "
                    + (SkyLightWindowServerSPI.shared.occlusionAvailability.unavailableReason ?? "unknown")
            )
        }
        guard FileManager.default.isExecutableFile(atPath: LiveWindowTestSupport.chromeExecutable.path) else {
            throw XCTSkip("Google Chrome is not installed at the standard path")
        }
        guard FileManager.default.isExecutableFile(atPath: LiveWindowTestSupport.fixtureExecutable.path) else {
            throw XCTSkip("Build OpenComputerUseFixture before running the live test")
        }
        let originalFrontApp = NSWorkspace.shared.frontmostApplication
        defer {
            if let originalFrontApp {
                _ = originalFrontApp.activate(options: [.activateAllWindows])
            }
        }

        let paths = try LiveWindowTestSupport.makeChromeTestRoot(prefix: "ocu-occlusion-live", html: Self.liveTestHTML, testCase: self)
        let chrome = try LiveWindowTestSupport.launchChrome(profile: paths.profile, page: paths.page)
        defer {
            LiveWindowTestSupport.stop(chrome)
        }
        let window = try LiveWindowTestSupport.waitForWindow(
            pid: chrome.processIdentifier, nameContaining: "ocu-occlusion-", onScreenOnly: true
        )
        let descriptor = try LiveWindowTestSupport.descriptor(for: window.pid)
        let owner = UUID()
        defer {
            keepAlive.release(owner: owner)
        }
        let session = SnapshotKeepAlive(keeper: keepAlive, owner: owner)

        // Chrome is visible: this snapshot must see the web content and pin the window.
        _ = descriptor.runningApplication.activate(options: [.activateAllWindows])
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        let visibleSnapshot = try SnapshotBuilder.build(
            for: descriptor, recoveryPolicy: .readOnly, keepAlive: session, waitsForLazyWebContent: true
        )
        XCTAssertEqual(visibleSnapshot.targetWindowID, window.id)
        XCTAssertTrue(visibleSnapshot.treeLines.contains { $0.contains("sky probe") }, "visible snapshot must include the web content")
        XCTAssertTrue(keepAlive.isPinned(windowID: window.id), "the visible window must be pinned")

        let cover = try LiveWindowTestSupport.launch(executable: LiveWindowTestSupport.fixtureExecutable)
        defer {
            LiveWindowTestSupport.stop(cover)
        }
        _ = try LiveWindowTestSupport.waitForWindow(
            pid: cover.processIdentifier, nameContaining: "OpenComputerUseFixture", onScreenOnly: true
        )
        RunLoop.current.run(until: Date().addingTimeInterval(2.5))
        let coverBounds = try LiveWindowTestSupport.waitForWindow(
            pid: cover.processIdentifier, nameContaining: "OpenComputerUseFixture", onScreenOnly: true
        ).bounds
        XCTAssertTrue(coverBounds.contains(window.bounds), "the fixture must fully cover Chrome")
        XCTAssertNotEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, window.pid)

        let pageTitle = try LiveWindowTestSupport.waitForWindow(
            pid: window.pid, nameContaining: "ocu-occlusion-", onScreenOnly: false
        ).name
        XCTAssertTrue(pageTitle.hasSuffix("vis=visible"), "Chrome must still consider the covered page visible, got \(pageTitle)")

        let coveredSnapshot = try SnapshotBuilder.build(
            for: descriptor, recoveryPolicy: .readOnly, keepAlive: session, waitsForLazyWebContent: true
        )
        XCTAssertTrue(coveredSnapshot.treeLines.contains { $0.contains("sky probe") }, "covered snapshot must still include the web content")
        XCTAssertNil(coveredSnapshot.hiddenWebContentNote)
        XCTAssertNotNil(coveredSnapshot.screenshotData)
        XCTAssertNotEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, window.pid, "snapshots must not activate Chrome")

        keepAlive.release(owner: owner)
        XCTAssertFalse(keepAlive.isPinned(windowID: window.id), "ending the session releases its pin")
    }

    private static let liveTestHTML = #"""
    <!doctype html>
    <meta charset="utf-8">
    <title>ocu-occlusion-ready</title>
    <p>sky probe paragraph</p>
    <input id="target" autofocus placeholder="sky probe">
    <script>
      const update = () => { document.title = `ocu-occlusion-${document.visibilityState === 'visible' ? 'vis=visible' : 'vis=hidden'}`; };
      document.addEventListener('visibilitychange', update);
      update();
    </script>
    """#
}
