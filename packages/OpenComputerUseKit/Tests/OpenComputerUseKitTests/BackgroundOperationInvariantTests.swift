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
///
/// No default path raises a window or makes one main or focused, including a click on a window element.
final class BackgroundOperationInvariantTests: XCTestCase {
    /// `file:function` pairs allowed to contain `.activate(`.
    private static let allowedActivateSites: Set<String> = [
        "InputSimulation.swift:prepareAppForGlobalPointerInput",
    ]

    /// `file:function` pairs allowed to name the raise action or the main-window attribute. The global pointer
    /// preparation is opt-in; `clickPriority` only reads them to rank hit-test candidates.
    private static let allowedRaiseOrMainWindowSites: Set<String> = [
        "InputSimulation.swift:raiseAppWindowViaAccessibility",
        "ComputerUseService.swift:clickPriority",
    ]

    /// `file:function` pairs allowed to write `AXFocused`: the opt-in global pointer preparation (on a window) and
    /// the text-field focus write after a click (on the clicked text-entry element only).
    private static let allowedFocusedWriteSites: Set<String> = [
        "InputSimulation.swift:raiseAppWindowViaAccessibility",
        "ComputerUseService.swift:click",
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

    func testWindowRaiseAndMainWindowWritesStayOnOptInPaths() throws {
        let raiseOrMainTokens = ["kAXRaiseAction", "\"AXRaise\"", "kAXMainAttribute", "\"AXMain\""]
        let writeTokens = ["PerformAction", "performAction(", "SetAttributeValue", "setBoolAttribute("]
        var raiseOrMainSites: [String] = []
        var focusedWriteSites: [String] = []
        for source in try kitSources() {
            for (index, line) in source.lines.enumerated() where !isComment(line) {
                let site = "\(source.name):\(enclosingFunction(in: source.lines, before: index))"
                if raiseOrMainTokens.contains(where: line.contains) {
                    raiseOrMainSites.append(site)
                    if site == "ComputerUseService.swift:clickPriority" {
                        XCTAssertFalse(writeTokens.contains(where: line.contains), "click ranking must only read: \(line)")
                    }
                }
                if line.contains("kAXFocusedAttribute"), writeTokens.contains(where: line.contains) {
                    focusedWriteSites.append(site)
                }
            }
        }

        let unexpectedRaise = raiseOrMainSites.filter { !Self.allowedRaiseOrMainWindowSites.contains($0) }
        XCTAssertTrue(unexpectedRaise.isEmpty, "default-path raise or main-window write found at: \(unexpectedRaise)")
        XCTAssertEqual(Set(raiseOrMainSites), Self.allowedRaiseOrMainWindowSites)

        let unexpectedFocus = focusedWriteSites.filter { !Self.allowedFocusedWriteSites.contains($0) }
        XCTAssertTrue(unexpectedFocus.isEmpty, "unexpected AXFocused write at: \(unexpectedFocus)")
        XCTAssertEqual(Set(focusedWriteSites), Self.allowedFocusedWriteSites)
    }

    /// The element click sequence ends when no press-style action handles the target; it has no window fallback.
    func testClickSequenceHasNoWindowFallback() throws {
        let service = try XCTUnwrap(try kitSources().first { $0.name == "ComputerUseService.swift" })
        let start = try XCTUnwrap(service.lines.firstIndex { $0.contains("func performAXClickSequence(") })
        let end = try XCTUnwrap(
            service.lines[(start + 1)...].firstIndex { $0.hasPrefix("    private func ") || $0.hasPrefix("    func ") }
        )
        for line in service.lines[start..<end] where !isComment(line) {
            for forbidden in ["Raise", "kAXMainAttribute", "kAXFocusedAttribute", "setBoolAttribute(", ".activate("] {
                XCTAssertFalse(line.contains(forbidden), "click sequence uses \(forbidden): \(line)")
            }
        }
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

    func testStageManagerOffStageDetectionOnlyReadsFrames() throws {
        let sources = try kitSources()
        let offStageFile = try XCTUnwrap(sources.first { $0.name == "StageManagerOffStageWindow.swift" })
        let forbidden = [
            ".activate(", "AXRaise", "AXAddToStage", "AXPress", "AXUIElementPerformAction", "AXUIElementSetAttributeValue",
            "SLS", "SkyLight", "CGEventPost", "CGWarpMouseCursorPosition", "setFrontmost",
        ]
        for line in offStageFile.lines where !isComment(line) {
            for token in forbidden {
                XCTAssertFalse(line.contains(token), "off-stage detection uses \(token): \(line)")
            }
        }
    }

    /// Every service function that posts pointer events at a screen position refuses an off-stage window first.
    func testPointerEventPathsRefuseOffStageWindows() throws {
        let service = try XCTUnwrap(try kitSources().first { $0.name == "ComputerUseService.swift" })
        for function in ["performScrollEvent", "performDragEvent", "performNonAXClickFallback", "performExplicitMouseClick"] {
            let start = try XCTUnwrap(
                service.lines.firstIndex { $0.contains("func \(function)(") }, "\(function) not found"
            )
            let body = service.lines[start..<min(start + 14, service.lines.count)].joined(separator: "\n")
            XCTAssertTrue(
                body.contains("try rejectCoordinateInputWhenOffStage(snapshot.isOffStage)"),
                "\(function) does not refuse off-stage windows"
            )
        }
    }

    func testNoWindowErrorKeepsOfficialPrefixAndSaysWhy() {
        let message = noBackgroundWindowMessage(appName: "Mail")
        XCTAssertTrue(message.hasPrefix(computerUseNoWindowFoundMessage))
        XCTAssertTrue(message.contains("Mail has no visible window"))
        XCTAssertTrue(message.contains("does not activate, raise, or unminimize"))
        XCTAssertTrue(message.contains("get_app_state"))
    }
}
