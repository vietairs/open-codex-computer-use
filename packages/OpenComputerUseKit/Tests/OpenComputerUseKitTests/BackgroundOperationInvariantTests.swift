import Foundation
import XCTest
@testable import OpenComputerUseKit

/// Source-level invariants that keep the default path from taking focus away from the user's frontmost app.
///
/// Opt-in paths that may change focus, and why none of them other than the first needs an `.activate(` call:
/// - `InputSimulation.prepareAppForGlobalPointerInput`: only reached through the global pointer paths gated by
///   `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1`. The one allowed `.activate(` site.
/// - `click_method=sky_click`: SkyLight synthetic focus records, no activation call.
/// - `perform_secondary_action` with an explicit Raise: an accessibility action the caller asked for.
/// - The AXWindow click fallback (`activateClickTarget`): AXRaise / AXMain / AXFocused on a window, no activation call.
final class BackgroundOperationInvariantTests: XCTestCase {
    /// `file:function` pairs allowed to contain `.activate(`.
    private static let allowedActivateSites: Set<String> = [
        "InputSimulation.swift:prepareAppForGlobalPointerInput",
    ]

    private static let kitSourcesDirectory: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            url.deleteLastPathComponent()
        }
        return url.appendingPathComponent("Sources/OpenComputerUseKit", isDirectory: true)
    }()

    private func kitSources() throws -> [(name: String, lines: [String])] {
        let names = try FileManager.default.contentsOfDirectory(atPath: Self.kitSourcesDirectory.path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()
        XCTAssertFalse(names.isEmpty, "no kit sources found at \(Self.kitSourcesDirectory.path)")
        return try names.map { name in
            let text = try String(contentsOf: Self.kitSourcesDirectory.appendingPathComponent(name), encoding: .utf8)
            return (name, text.components(separatedBy: "\n"))
        }
    }

    private static let functionDeclaration = try! NSRegularExpression(pattern: #"\bfunc\s+([A-Za-z_][A-Za-z0-9_]*)"#)

    private func enclosingFunction(in lines: [String], before lineIndex: Int) -> String {
        for index in stride(from: lineIndex, through: 0, by: -1) {
            let line = lines[index]
            let range = NSRange(line.startIndex..., in: line)
            if let match = Self.functionDeclaration.firstMatch(in: line, range: range),
               let nameRange = Range(match.range(at: 1), in: line) {
                return String(line[nameRange])
            }
        }
        return "<file scope>"
    }

    private func isComment(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*")
    }

    func testActivateIsCalledOnlyFromOptInGlobalPointerPath() throws {
        var sites: [String] = []
        for source in try kitSources() {
            for (index, line) in source.lines.enumerated() where line.contains(".activate(") && !isComment(line) {
                sites.append("\(source.name):\(enclosingFunction(in: source.lines, before: index))")
            }
        }

        let unexpected = sites.filter { !Self.allowedActivateSites.contains($0) }
        XCTAssertTrue(unexpected.isEmpty, "default-path activation found at: \(unexpected)")
        // Keeps the allowlist honest: a moved or renamed opt-in site must be re-listed here, not silently dropped.
        XCTAssertEqual(Set(sites), Self.allowedActivateSites)
    }

    func testKitNeverShellsOutToOpen() throws {
        for source in try kitSources() {
            for line in source.lines where !isComment(line) {
                XCTAssertFalse(line.contains("\"/usr/bin/open\""), "\(source.name) runs /usr/bin/open: \(line)")
            }
        }
    }

    func testAppLaunchDoesNotActivate() throws {
        let appDiscovery = try XCTUnwrap(try kitSources().first { $0.name == "AppDiscovery.swift" })
        let body = appDiscovery.lines.joined(separator: "\n")
        XCTAssertTrue(body.contains("configuration.activates = false"))
        XCTAssertFalse(body.contains("activates = true"))
    }

    func testClickTextEntryFocusIsAnAccessibilityWriteOnly() throws {
        let sources = try kitSources()
        let focusFile = try XCTUnwrap(sources.first { $0.name == "ClickTextEntryFocus.swift" })
        for line in focusFile.lines where !isComment(line) {
            for forbidden in [".activate(", "kAXRaiseAction", "AXRaise", "SLS", "CGS", "setFrontmost"] {
                XCTAssertFalse(line.contains(forbidden), "click focus path uses \(forbidden): \(line)")
            }
        }

        // The live wiring writes AXFocused on the clicked element and nothing that brings the app forward.
        let service = try XCTUnwrap(sources.first { $0.name == "ComputerUseService.swift" })
        let wiring = try XCTUnwrap(service.lines.firstIndex { $0.contains("focusTextEntryAfterClick(") })
        let block = service.lines[wiring..<min(wiring + 10, service.lines.count)].joined(separator: "\n")
        XCTAssertTrue(block.contains("kAXFocusedAttribute as CFString, kCFBooleanTrue"))
        XCTAssertFalse(block.contains(".activate("))
        XCTAssertFalse(block.contains("Raise"))
    }

    func testNoWindowErrorKeepsOfficialPrefixAndSaysWhy() {
        let message = noBackgroundWindowMessage(appName: "Mail")
        XCTAssertTrue(message.hasPrefix(computerUseNoWindowFoundMessage))
        XCTAssertTrue(message.contains("Mail has no visible window"))
        XCTAssertTrue(message.contains("does not activate, raise, or unminimize"))
        XCTAssertTrue(message.contains("get_app_state"))
    }
}
