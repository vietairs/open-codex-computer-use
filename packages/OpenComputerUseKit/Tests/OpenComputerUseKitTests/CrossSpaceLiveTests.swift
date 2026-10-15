import AppKit
import CoreGraphics
import Foundation
import XCTest
@testable import OpenComputerUseKit

/// Opt-in live regression: a Chrome window on another Desktop can be snapshotted (tree and screenshot), clicked with
/// `sky_click` and typed into with `sky_key` from the Desktop the user is on, without switching Spaces or activating
/// Chrome.
///
/// The test never switches Desktops itself: `SLSManagedDisplaySetCurrentSpace` from a third-party process does not
/// switch on macOS 27.2, and the test must not move the user's display around anyway. The user does the one switch:
/// 1. Create a second Desktop in Mission Control.
/// 2. On the Desktop where Chrome should open (Desktop 2, say), run from the repository root in Terminal.app:
///    `OPEN_COMPUTER_USE_RUN_CROSS_SPACE_LIVE_TEST=1 swift test --filter CrossSpaceLiveTests`
/// 3. The test opens an isolated Chrome window on that Desktop and reads it once. When it beeps and prints
///    "switch to another Desktop now", switch to any other Desktop (Control-Left Arrow, say) within 60 seconds and
///    leave Chrome behind. Do not click anything until the test ends.
/// 4. The test opens the fixture on the Desktop you switched to, runs the checks against the Chrome window left on
///    the other Desktop, quits Chrome and the fixture, and reactivates the app that was frontmost when it started,
///    which brings that app's Desktop back.
///
/// The app running the tests needs Accessibility and Screen Recording; without Screen Recording the window list has
/// no window names, so the test cannot find its windows and fails up front.
@MainActor
final class CrossSpaceLiveTests: XCTestCase {
    private typealias MainConnection = @convention(c) () -> UInt32
    private typealias CopyManagedDisplaySpaces = @convention(c) (UInt32) -> Unmanaged<CFArray>?
    private typealias ActiveSpace = @convention(c) (UInt32) -> UInt64
    private typealias CopySpacesForWindows = @convention(c) (UInt32, Int32, CFArray) -> Unmanaged<CFArray>?

    /// How long the test waits for the user to switch Desktops.
    private static let desktopSwitchTimeout: TimeInterval = 60

    func testWindowOnAnotherSpaceIsReadableClickableAndTypable() throws {
        guard ProcessInfo.processInfo.environment["OPEN_COMPUTER_USE_RUN_CROSS_SPACE_LIVE_TEST"] == "1" else {
            throw XCTSkip("Set OPEN_COMPUTER_USE_RUN_CROSS_SPACE_LIVE_TEST=1 to run the cross-Space live test")
        }
        let spi = SkyLightSPI.shared
        guard spi.capability.isAvailable, WindowOcclusionKeepAlive.shared.isAvailable else {
            throw XCTSkip("SkyLight SPI unavailable on this macOS version")
        }
        guard let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let mainPointer = dlsym(skyLight, "SLSMainConnectionID"),
              let copyPointer = dlsym(skyLight, "SLSCopyManagedDisplaySpaces"),
              let activePointer = dlsym(skyLight, "SLSGetActiveSpace"),
              let spacesPointer = dlsym(skyLight, "SLSCopySpacesForWindows")
        else {
            throw XCTSkip("Space SPIs unavailable")
        }
        let connection = unsafeBitCast(mainPointer, to: MainConnection.self)()
        let copySpaces = unsafeBitCast(copyPointer, to: CopyManagedDisplaySpaces.self)
        let activeSpace = unsafeBitCast(activePointer, to: ActiveSpace.self)
        let copySpacesForWindows = unsafeBitCast(spacesPointer, to: CopySpacesForWindows.self)

        let displays = copySpaces(connection)?.takeRetainedValue() as? [[String: Any]] ?? []
        let userSpaces = displays.flatMap { display in
            ((display["Spaces"] as? [[String: Any]]) ?? []).compactMap { space -> UInt64? in
                guard (space["type"] as? NSNumber)?.intValue == 0 else { return nil }
                return (space["id64"] as? NSNumber)?.uint64Value
            }
        }
        func spacesOfWindow(_ id: CGWindowID) -> [UInt64] {
            ((copySpacesForWindows(connection, 0x7, [NSNumber(value: id)] as CFArray)?.takeRetainedValue() as? [NSNumber]) ?? [])
                .map(\.uint64Value)
        }

        guard FileManager.default.isExecutableFile(atPath: LiveWindowTestSupport.chromeExecutable.path) else {
            throw XCTSkip("Google Chrome is not installed at the standard path")
        }
        guard FileManager.default.isExecutableFile(atPath: LiveWindowTestSupport.fixtureExecutable.path) else {
            throw XCTSkip("Build OpenComputerUseFixture before running the live test")
        }
        guard userSpaces.count >= 2 else {
            throw XCTSkip("Create a second Desktop in Mission Control to run the cross-Space live test")
        }
        let chromeSpace = activeSpace(connection)
        guard userSpaces.contains(chromeSpace) else {
            throw XCTSkip("Start the cross-Space live test from a Desktop, not a full-screen Space")
        }
        try LiveWindowTestSupport.requirePermissions()
        let originalFrontApp = NSWorkspace.shared.frontmostApplication
        defer {
            if let originalFrontApp {
                _ = originalFrontApp.activate(options: [.activateAllWindows])
            }
        }

        // Chrome opens on the Desktop the test was started from.
        let paths = try LiveWindowTestSupport.makeChromeTestRoot(prefix: "ocu-cross-space", html: Self.liveTestHTML, testCase: self)
        let chrome = try LiveWindowTestSupport.launchChrome(profile: paths.profile, page: paths.page)
        defer {
            LiveWindowTestSupport.stop(chrome)
        }
        let window = try LiveWindowTestSupport.waitForWindow(pid: chrome.processIdentifier, nameContaining: "ocu-space-", onScreenOnly: true)
        let descriptor = try LiveWindowTestSupport.descriptor(for: window.pid)
        _ = descriptor.runningApplication.activate(options: [.activateAllWindows])
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        XCTAssertEqual(spacesOfWindow(window.id), [chromeSpace], "Chrome must open on the Desktop the test started from")

        let owner = UUID()
        let keepAlive = WindowOcclusionKeepAlive.shared
        defer {
            keepAlive.release(owner: owner)
        }
        let session = SnapshotKeepAlive(keeper: keepAlive, owner: owner)

        // Visible on its Desktop: the snapshot sees the web content and pins the window.
        let visibleSnapshot = try SnapshotBuilder.build(
            for: descriptor, recoveryPolicy: .readOnly, keepAlive: session, waitsForLazyWebContent: true
        )
        XCTAssertTrue(visibleSnapshot.treeLines.contains { $0.contains("sky probe") }, "visible snapshot must include web content")
        XCTAssertTrue(keepAlive.isPinned(windowID: window.id))
        XCTAssertEqual(activeSpace(connection), chromeSpace, "stay on Chrome's Desktop until the test beeps")

        // The user switches Desktops; the test only waits for it.
        FileHandle.standardError.write(Data(
            "CrossSpaceLiveTests: switch to another Desktop now (Control-Left Arrow, say); waiting up to \(Int(Self.desktopSwitchTimeout)) seconds\n".utf8
        ))
        NSSound.beep()
        let switchDeadline = Date().addingTimeInterval(Self.desktopSwitchTimeout)
        var homeSpace = activeSpace(connection)
        while homeSpace == chromeSpace || !userSpaces.contains(homeSpace) {
            guard Date() < switchDeadline else {
                throw ComputerUseError.message(
                    "Timed out waiting for a switch to another Desktop; switch within \(Int(Self.desktopSwitchTimeout)) seconds of the beep"
                )
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            homeSpace = activeSpace(connection)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        XCTAssertEqual(activeSpace(connection), homeSpace, "stay on the Desktop you switched to until the test ends")

        // On the other Desktop with the fixture in front.
        let fixture = try LiveWindowTestSupport.launch(executable: LiveWindowTestSupport.fixtureExecutable)
        defer {
            LiveWindowTestSupport.stop(fixture)
        }
        _ = try LiveWindowTestSupport.waitForWindow(pid: fixture.processIdentifier, nameContaining: "OpenComputerUseFixture", onScreenOnly: true)
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        let parked = try LiveWindowTestSupport.waitForWindow(pid: window.pid, nameContaining: "ocu-space-", onScreenOnly: false)
        XCTAssertEqual(spacesOfWindow(window.id), [chromeSpace], "the window must stay on its Desktop")
        XCTAssertEqual(SkyLightWindowServerSPI.shared.windowIsOnCurrentSpace(window.id), false)
        XCTAssertNotEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, window.pid)
        // Evidence for the docs: what the window server reports as on screen for a window on another Desktop.
        let parkedIsOnscreen = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? [])
            .first { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == window.id }
            .flatMap { ($0[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue }
        let onscreenRecord = "kCGWindowIsOnscreen for a window on another Desktop: "
            + (parkedIsOnscreen.map { String($0) } ?? "absent")
        print(onscreenRecord)
        let attachment = XCTAttachment(string: onscreenRecord)
        attachment.lifetime = .keepAlways
        add(attachment)

        // Production paths against the window on the other Space.
        let parkedSnapshot = try SnapshotBuilder.build(
            for: descriptor, recoveryPolicy: .readOnly, keepAlive: session, waitsForLazyWebContent: true
        )
        XCTAssertEqual(parkedSnapshot.targetWindowID, window.id, "the snapshot must resolve the window on the other Space")
        XCTAssertTrue(parkedSnapshot.treeLines.contains { $0.contains("sky probe") }, "the snapshot must include web content")
        XCTAssertNotNil(parkedSnapshot.screenshotData, "the window on the other Space must be captured")
        XCTAssertEqual(activeSpace(connection), homeSpace, "the snapshot must not switch Spaces")
        XCTAssertNotEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, window.pid, "the snapshot must not activate Chrome")

        let windowPoint = CGPoint(x: parked.bounds.width / 2, y: parked.bounds.height - 60)
        try SkyClickDispatcher.click(
            target: SkyClickTarget(
                screenPoint: CGPoint(x: parked.bounds.minX + windowPoint.x, y: parked.bounds.minY + windowPoint.y),
                windowPoint: windowPoint,
                windowBounds: parked.bounds,
                windowID: window.id,
                pid: window.pid
            ),
            clickCount: 1,
            spi: spi
        )
        _ = try LiveWindowTestSupport.waitForWindow(pid: window.pid, nameContaining: "clicks=1", onScreenOnly: false)

        let target = SkyKeyboardTarget(windowID: window.id, pid: window.pid)
        try SkyKeyboardDispatcher.typeText(target: target, text: "s2")
        try SkyKeyboardDispatcher.pressKey(target: target, key: "cmd+a")
        try SkyKeyboardDispatcher.typeText(target: target, text: "Ok")
        let typed = try LiveWindowTestSupport.waitForWindow(pid: window.pid, nameContaining: "ocu-space-Ok|", onScreenOnly: false)
        XCTAssertTrue(typed.name.hasPrefix("ocu-space-Ok|clicks=1|"), "sky_key must type and select-all on the window, got \(typed.name)")

        XCTAssertEqual(activeSpace(connection), homeSpace, "actions must not switch Spaces")
        XCTAssertNotEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, window.pid, "actions must not activate Chrome")
        XCTAssertEqual(spacesOfWindow(window.id), [chromeSpace], "the window must stay on its Desktop")
    }

    private static let liveTestHTML = #"""
    <!doctype html><meta charset="utf-8"><title>ocu-space-ready</title>
    <style>html,body{margin:0;height:100%} input{width:90%;font:22px system-ui;margin:20px} button{position:absolute;left:0;right:0;bottom:0;height:120px;font:22px system-ui;background:#5b8def;color:#fff;border:0}</style>
    <p>sky probe paragraph</p><input id="t" autofocus placeholder="sky probe"><button id="b">click probe</button>
    <script>
      let clicks = 0; const input = document.querySelector('#t');
      const update = () => { document.title = `ocu-space-${input.value}|clicks=${clicks}|${document.visibilityState}`; };
      document.querySelector('#b').addEventListener('click', () => { clicks += 1; update(); });
      input.addEventListener('input', update); document.addEventListener('visibilitychange', update); update();
    </script>
    """#
}
