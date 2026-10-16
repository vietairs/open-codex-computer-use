import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import XCTest
@testable import OpenComputerUseKit

/// Shared helpers for the opt-in live tests that drive an isolated Chrome window and the fixture app. Nothing here
/// runs unless a live test's environment gate is set.
struct LiveWindowRecord {
    let id: CGWindowID
    let pid: pid_t
    let bounds: CGRect
    let name: String
    let onScreen: Bool
}

enum LiveWindowTestSupport {
    static let chromeExecutable = URL(fileURLWithPath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")

    static let packageRoot: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            url.deleteLastPathComponent()
        }
        return url
    }()

    static var fixtureExecutable: URL {
        packageRoot.appendingPathComponent(".build/debug/OpenComputerUseFixture")
    }

    /// A temp directory under `.build` holding a Chrome profile and the page; removed when the test ends.
    static func makeChromeTestRoot(prefix: String, html: String, testCase: XCTestCase) throws -> (profile: URL, page: URL) {
        let root = packageRoot.appendingPathComponent(".build/\(prefix)-\(UUID().uuidString)", isDirectory: true)
        let profile = root.appendingPathComponent("chrome-profile", isDirectory: true)
        let page = root.appendingPathComponent("index.html")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        try html.write(to: page, atomically: false, encoding: .utf8)
        testCase.addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return (profile, page)
    }

    static func launchChrome(profile: URL, page: URL) throws -> Process {
        let chrome = Process()
        chrome.executableURL = chromeExecutable
        chrome.arguments = [
            "--user-data-dir=\(profile.path)", "--no-first-run", "--no-default-browser-check",
            "--disable-background-networking", "--disable-component-update",
            "--window-position=200,200", "--window-size=600,420", "--app=\(page.absoluteString)",
        ]
        chrome.standardOutput = FileHandle.nullDevice
        chrome.standardError = FileHandle.nullDevice
        try chrome.run()
        return chrome
    }

    static func launch(executable: URL) throws -> Process {
        let process = Process()
        process.executableURL = executable
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }

    static func stop(_ process: Process) {
        if process.isRunning {
            process.terminate()
            let deadline = Date().addingTimeInterval(5)
            while process.isRunning, Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }

    static func waitForWindow(pid: pid_t, nameContaining marker: String, onScreenOnly: Bool) throws -> LiveWindowRecord {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            let options: CGWindowListOption = onScreenOnly ? [.optionOnScreenOnly, .excludeDesktopElements] : [.optionAll]
            let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
            for info in raw {
                guard
                    let number = info[kCGWindowNumber as String] as? NSNumber,
                    let owner = info[kCGWindowOwnerPID as String] as? NSNumber, owner.int32Value == pid,
                    let name = info[kCGWindowName as String] as? String, name.contains(marker),
                    let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                    let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                    bounds.width > 0
                else {
                    continue
                }
                return LiveWindowRecord(
                    id: number.uint32Value,
                    pid: pid,
                    bounds: bounds,
                    name: name,
                    onScreen: (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
                )
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        throw ComputerUseError.message("Timed out waiting for a window title containing \(marker)")
    }

    /// Fails the live test up front when the process running it (Terminal, say) lacks Accessibility or Screen
    /// Recording. Without Screen Recording the window list has no window names, so every `waitForWindow` would time out.
    static func requirePermissions() throws {
        guard AXIsProcessTrusted() else {
            throw ComputerUseError.message("Grant Accessibility to the app running the tests, then run the test again")
        }
        guard CGPreflightScreenCaptureAccess() else {
            throw ComputerUseError.message(
                "Grant Screen Recording to the app running the tests: without it window names are not readable, "
                    + "so the test cannot find its windows"
            )
        }
    }

    /// Whether Stage Manager is turned on. Under Stage Manager another app's window moves the previous app off stage
    /// instead of covering it.
    static var stageManagerIsOn: Bool {
        UserDefaults(suiteName: "com.apple.WindowManager")?.bool(forKey: "GloballyEnabled") ?? false
    }

    /// Moves the app's first window over `target` with a margin, growing it when it is smaller, through
    /// accessibility; then waits until the window server reports the window covering `target`.
    static func coverWindow(pid: pid_t, windowNamed marker: String, over target: CGRect) throws -> LiveWindowRecord {
        let margin: CGFloat = 20
        let current = try waitForWindow(pid: pid, nameContaining: marker, onScreenOnly: true)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &value) == .success,
              let window = (value as? [AXUIElement])?.first
        else {
            throw ComputerUseError.message("Could not read the accessibility window of pid \(pid)")
        }
        var origin = CGPoint(x: target.minX - margin, y: target.minY - margin)
        var size = CGSize(
            width: max(current.bounds.width, target.width + 2 * margin),
            height: max(current.bounds.height, target.height + 2 * margin)
        )
        guard let originValue = AXValueCreate(.cgPoint, &origin), let sizeValue = AXValueCreate(.cgSize, &size) else {
            throw ComputerUseError.message("Could not build the accessibility frame values")
        }
        let sizeResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        let originResult = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, originValue)
        guard sizeResult == .success, originResult == .success else {
            throw ComputerUseError.message("Could not move the window of pid \(pid): size \(sizeResult.rawValue), position \(originResult.rawValue)")
        }
        let deadline = Date().addingTimeInterval(5)
        var moved = current
        while Date() < deadline {
            moved = try waitForWindow(pid: pid, nameContaining: marker, onScreenOnly: true)
            if moved.bounds.contains(target) {
                return moved
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        throw ComputerUseError.message("The window of pid \(pid) at \(moved.bounds) does not cover \(target)")
    }

    static func descriptor(for pid: pid_t) throws -> RunningAppDescriptor {
        guard let running = NSRunningApplication(processIdentifier: pid) else {
            throw ComputerUseError.message("pid \(pid) is not a running application")
        }
        return RunningAppDescriptor(
            name: running.localizedName ?? "Google Chrome",
            bundleIdentifier: running.bundleIdentifier,
            pid: pid,
            runningApplication: running
        )
    }
}
