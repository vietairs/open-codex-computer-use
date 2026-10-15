import AppKit
import CoreGraphics
import Foundation
import XCTest
@testable import OpenComputerUseKit

/// A node of an in-memory tree for the web-area probe.
private final class ProbeNode {
    let role: String
    let children: [ProbeNode]

    init(_ role: String, _ children: [ProbeNode] = []) {
        self.role = role
        self.children = children
    }
}

final class LazyWebAccessibilityTests: XCTestCase {
    // MARK: - Decision

    func testDecisionTable() {
        XCTAssertEqual(lazyWebRewalkDecision(lazyWeb: false, hasWebArea: false, visibleNow: true, waitAllowed: true, exhausted: false), .none)
        XCTAssertEqual(lazyWebRewalkDecision(lazyWeb: true, hasWebArea: true, visibleNow: false, waitAllowed: true, exhausted: false), .none)
        XCTAssertEqual(lazyWebRewalkDecision(lazyWeb: true, hasWebArea: false, visibleNow: true, waitAllowed: true, exhausted: false), .rewalk)
        XCTAssertEqual(
            lazyWebRewalkDecision(lazyWeb: true, hasWebArea: false, visibleNow: true, waitAllowed: false, exhausted: false),
            .none,
            "an action result never waits"
        )
        XCTAssertEqual(
            lazyWebRewalkDecision(lazyWeb: true, hasWebArea: false, visibleNow: true, waitAllowed: true, exhausted: true),
            .none,
            "a window that already used up its wait does not wait again"
        )
        XCTAssertEqual(lazyWebRewalkDecision(lazyWeb: true, hasWebArea: false, visibleNow: false, waitAllowed: true, exhausted: false), .hiddenNote)
        XCTAssertEqual(lazyWebRewalkDecision(lazyWeb: true, hasWebArea: false, visibleNow: false, waitAllowed: false, exhausted: true), .hiddenNote)
    }

    func testNoteOnlyPromisesTheKeepAliveWhereItWorks() {
        XCTAssertTrue(hiddenWebContentNote(keepAliveAvailable: true).hasSuffix("covering it afterwards keeps working."))
        XCTAssertTrue(hiddenWebContentNote(keepAliveAvailable: false).hasSuffix("Bring the window into view to read it."))
        XCTAssertFalse(hiddenWebContentNote(keepAliveAvailable: false).contains("keeps working"))
    }

    // MARK: - Probe and wait

    private func probe(_ root: ProbeNode, maxDepth: Int = 10, maxNodes: Int = 400, deadline: TimeInterval = 10, now: TimeInterval = 0) -> Bool {
        treeContainsWebArea(
            root: root,
            maxDepth: maxDepth,
            maxNodes: maxNodes,
            deadline: deadline,
            now: { now },
            isWebArea: { $0.role == "AXWebArea" },
            children: { $0.children }
        )
    }

    func testProbeFindsAWebAreaWithinItsBounds() {
        let tree = ProbeNode("AXWindow", [
            ProbeNode("AXButton"),
            ProbeNode("AXGroup", [ProbeNode("AXGroup", [ProbeNode("AXWebArea")])]),
        ])
        XCTAssertTrue(probe(tree))
        XCTAssertFalse(probe(tree, maxDepth: 2), "the web area sits at depth 3")
        XCTAssertFalse(probe(tree, maxNodes: 3), "the node budget runs out first")
        XCTAssertFalse(probe(tree, deadline: 1, now: 2), "past the deadline nothing is read")
        XCTAssertFalse(probe(ProbeNode("AXWindow", [ProbeNode("AXGroup")])))
    }

    func testWaitStopsAsSoonAsTheWebAreaAppears() {
        var clock: TimeInterval = 0
        var probes = 0
        let found = waitForLazyWebArea(
            limits: .standard,
            now: { clock },
            sleep: { clock += $0 },
            probe: { _ in probes += 1; return probes == 3 }
        )
        XCTAssertTrue(found)
        XCTAssertEqual(probes, 3)
        XCTAssertEqual(clock, 0.3, accuracy: 0.0001)
    }

    func testWaitIsBoundedByItsBudget() {
        var clock: TimeInterval = 0
        var probes = 0
        let found = waitForLazyWebArea(
            limits: .standard,
            now: { clock },
            sleep: { clock += $0 },
            probe: { _ in probes += 1; return false }
        )
        XCTAssertFalse(found)
        XCTAssertLessThanOrEqual(clock, LazyWebWaitLimits.standard.timeBudget + LazyWebWaitLimits.standard.pollInterval)
        XCTAssertLessThanOrEqual(probes, 21)
    }

    func testExhaustedWindowsAreRememberedAndBounded() {
        let windows = LazyWebExhaustedWindows(capacity: 2)
        windows.insert(1)
        windows.insert(2)
        XCTAssertTrue(windows.contains(1))
        XCTAssertTrue(windows.contains(2))
        windows.insert(3)
        XCTAssertEqual(windows.count, 1, "the set is cleared when full")
        XCTAssertTrue(windows.contains(3))
        XCTAssertFalse(windows.contains(1))
    }

    // MARK: - Engine detection

    func testFrameworkNamesIdentifyChromiumElectronAndCEF() {
        XCTAssertTrue(frameworkNamesIndicateLazyWebEngine(["Google Chrome Framework.framework"]))
        XCTAssertTrue(frameworkNamesIndicateLazyWebEngine(["Electron Framework.framework", "Squirrel.framework"]))
        XCTAssertTrue(frameworkNamesIndicateLazyWebEngine(["Chromium Embedded Framework.framework"]))
        XCTAssertTrue(frameworkNamesIndicateLazyWebEngine(["libcef.dylib"]))
        XCTAssertFalse(frameworkNamesIndicateLazyWebEngine(["Sparkle.framework", "WebKit.framework"]))
        XCTAssertFalse(frameworkNamesIndicateLazyWebEngine([]))
    }

    func testOnlyBundlesUnderTrustedRootsAreListed() {
        let roots = ["/Applications", "/Users/someone/Applications"]
        func trusted(_ path: String) -> Bool {
            bundleIsUnderTrustedRoot(URL(fileURLWithPath: path), roots: roots, isSymbolicLink: { _ in false })
        }
        XCTAssertTrue(trusted("/Applications/Google Chrome.app"))
        XCTAssertTrue(trusted("/Users/someone/Applications/Slack.app"))
        XCTAssertFalse(trusted("/Applications2/Slack.app"))
        XCTAssertFalse(trusted("/Users/someone/Downloads/Slack.app"))
        XCTAssertFalse(trusted("/Applications/../Users/someone/Desktop/X.app"))
        XCTAssertFalse(trusted("/Volumes/USB/X.app"))
    }

    func testSymbolicLinkBelowTheRootMakesTheBundleUntrusted() {
        let url = URL(fileURLWithPath: "/Applications/Tools/Slack.app")
        var asked: [String] = []
        XCTAssertTrue(bundleIsUnderTrustedRoot(url, roots: ["/Applications"], isSymbolicLink: { asked.append($0); return false }))
        XCTAssertEqual(asked, [
            "/Applications/Tools",
            "/Applications/Tools/Slack.app",
            "/Applications/Tools/Slack.app/Contents",
            "/Applications/Tools/Slack.app/Contents/Frameworks",
        ], "every path below the root up to the listed directory, in order")

        for link in asked {
            var checked: [String] = []
            XCTAssertFalse(
                bundleIsUnderTrustedRoot(url, roots: ["/Applications"], isSymbolicLink: { checked.append($0); return $0 == link }),
                "a link at \(link) leaves the trusted root"
            )
            XCTAssertEqual(checked.last, link, "nothing past the first link is examined")
        }
    }

    private func makeBundle(in root: URL, name: String, frameworks: [String]) throws -> URL {
        let bundle = root.appendingPathComponent(name, isDirectory: true)
        let frameworksDirectory = bundle.appendingPathComponent("Contents/Frameworks", isDirectory: true)
        try FileManager.default.createDirectory(at: frameworksDirectory, withIntermediateDirectories: true)
        for framework in frameworks {
            try FileManager.default.createDirectory(
                at: frameworksDirectory.appendingPathComponent(framework, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        return bundle
    }

    func testDetectorReadsTrustedBundlesOnceAndIgnoresOthers() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocu-lazy-web-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: base)
        }
        let trusted = base.appendingPathComponent("Applications", isDirectory: true)
        let untrusted = base.appendingPathComponent("Downloads", isDirectory: true)
        let chromeLike = try makeBundle(in: trusted, name: "Browser.app", frameworks: ["Browser Chromium Framework.framework"])
        let native = try makeBundle(in: trusted, name: "Notes.app", frameworks: ["Sparkle.framework"])
        let downloaded = try makeBundle(in: untrusted, name: "Electron.app", frameworks: ["Electron Framework.framework"])

        let detector = LazyWebEngineDetector(trustedRoots: [trusted.standardizedFileURL.path])
        XCTAssertTrue(detector.appHasLazyWebAccessibility(bundleURL: chromeLike))
        XCTAssertFalse(detector.appHasLazyWebAccessibility(bundleURL: native))
        XCTAssertFalse(detector.appHasLazyWebAccessibility(bundleURL: downloaded), "outside the trusted roots nothing is listed")
        XCTAssertFalse(detector.appHasLazyWebAccessibility(bundleURL: nil))

        // A link inside the trusted root that points at a bundle elsewhere is not followed.
        let linked = trusted.appendingPathComponent("Linked.app", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: downloaded)
        XCTAssertFalse(detector.appHasLazyWebAccessibility(bundleURL: linked), "a symbolic link below the root is untrusted")

        try FileManager.default.removeItem(at: chromeLike.appendingPathComponent("Contents/Frameworks"))
        XCTAssertTrue(detector.appHasLazyWebAccessibility(bundleURL: chromeLike), "the answer is cached per bundle")
    }

    // MARK: - Rendering

    private func makeSnapshot(note: String?) -> AppSnapshot {
        let field = ElementRecord(
            index: 0,
            identifier: nil,
            element: nil,
            localFrame: CGRect(x: 10, y: 10, width: 80, height: 24),
            role: "AXTextField",
            rawActions: [],
            prettyActions: []
        )
        return AppSnapshot(
            app: RunningAppDescriptor(
                name: "Google Chrome",
                bundleIdentifier: "com.google.Chrome",
                pid: 4242,
                runningApplication: NSRunningApplication.current
            ),
            windowTitle: "Docs",
            windowBounds: CGRect(x: 0, y: 0, width: 800, height: 600),
            targetWindowID: 77,
            targetWindowLayer: 0,
            screenshotData: nil,
            mode: .accessibility,
            treeLines: ["0 text field Address"],
            treeLineOffsets: [0: 0],
            focusedSummary: nil,
            focusedElement: nil,
            selectedText: nil,
            elements: [0: field],
            windowContentIsEmpty: false,
            hiddenWebContentNote: note
        )
    }

    func testHiddenContentNoteIsRenderedOnceInEveryStyle() {
        let note = hiddenWebContentNote(keepAliveAvailable: true)
        let snapshot = makeSnapshot(note: note)
        for style in [SnapshotTextStyle.fullState, .actionResult, .compactActionable] {
            let lines = snapshot.renderedText(style: style).components(separatedBy: "\n")
            XCTAssertEqual(lines.filter { $0 == note }.count, 1, "style \(style)")
            XCTAssertEqual(lines.firstIndex(of: note), 2, "the note follows the Window line")
        }
        XCTAssertFalse(makeSnapshot(note: nil).renderedText.contains("hides its web content"))
    }
}
