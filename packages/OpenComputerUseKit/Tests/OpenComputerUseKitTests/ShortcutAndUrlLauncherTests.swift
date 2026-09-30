import Foundation
import XCTest
@testable import OpenComputerUseKit

/// Resolvers and the opener are injected, so no test opens a URL, asks LaunchServices anything or launches an app.
/// Shortcut runs go through throwaway executable scripts written into a private temporary directory; the real
/// `/usr/bin/shortcuts` is never executed.
final class ShortcutAndUrlLauncherTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("shortcut-launcher-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    private static let safari = URL(fileURLWithPath: "/Applications/Safari.app")

    /// Records every `opener` invocation.
    private final class OpenerRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [(url: URL, handler: URL)] = []
        var result = true

        var calls: [(url: URL, handler: URL)] {
            lock.lock()
            defer { lock.unlock() }
            return recorded
        }

        func record(_ url: URL, _ handler: URL) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            recorded.append((url, handler))
            return result
        }
    }

    private final class CallCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        func increment() {
            lock.lock()
            defer { lock.unlock() }
            value += 1
        }
    }

    private func evaluate(
        _ rawURL: String,
        handler: URL? = ShortcutAndUrlLauncherTests.safari,
        bundleIdentifier: String? = "com.apple.Safari"
    ) throws -> UrlOpenVerdict {
        let url = try XCTUnwrap(URL(string: rawURL), "fixture URL must parse: \(rawURL)")
        return UrlOpenPolicy.evaluate(
            url,
            handlerResolver: { _ in handler },
            bundleIdentifierResolver: { _ in bundleIdentifier }
        )
    }

    private func assertRejected(
        _ verdict: UrlOpenVerdict,
        _ label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .rejected(let reason) = verdict else {
            return XCTFail("\(label) should be rejected, got \(verdict)", file: file, line: line)
        }
        XCTAssertFalse(reason.isEmpty, "\(label) must carry a reason", file: file, line: line)
    }

    /// Writes an executable shell script and returns its path.
    private func writeExecutable(named name: String, body: String) throws -> String {
        let url = root.appendingPathComponent(name)
        try "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url.path
    }

    // MARK: - URL policy

    func testUrlPolicyTable() throws {
        let blockedSchemeURLs = [
            "file:///etc/hosts",
            "FILE:///etc/hosts",
            "ssh://h",
            "telnet://h",
            "x-man-page://ls",
            "shortcuts://run-shortcut?name=x",
            "smb://h/s",
            "afp://h/s",
            "nfs://h/s",
            "cifs://h/s",
            "ftp://h/f",
            "vnc://h",
            "help:anchor=x",
        ]
        for raw in blockedSchemeURLs {
            assertRejected(try evaluate(raw), raw)
        }

        assertRejected(try evaluate("example.com"), "a URL without a scheme")

        assertRejected(
            try evaluate(
                "myterm://x",
                handler: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
                bundleIdentifier: "com.apple.Terminal"
            ),
            "a URL handled by Terminal"
        )

        XCTAssertFalse(UrlOpenPolicy.blockedHandlerBundleIdentifiers.isEmpty)
        for identifier in UrlOpenPolicy.blockedHandlerBundleIdentifiers {
            XCTAssertEqual(identifier, identifier.lowercased(), "blocked handler ids are stored lowercased")
            assertRejected(try evaluate("myscheme://x", bundleIdentifier: identifier), "handler id \(identifier)")
        }
        let sample = try XCTUnwrap(UrlOpenPolicy.blockedHandlerBundleIdentifiers.sorted().first)
        assertRejected(
            try evaluate("myscheme://x", bundleIdentifier: sample.uppercased()),
            "upper-case variant of \(sample)"
        )

        assertRejected(try evaluate("myscheme://x", handler: nil), "an unresolved handler")
        assertRejected(
            try evaluate("myscheme://x", handler: URL(fileURLWithPath: "/tmp/evil.command")),
            "a handler that is not an app bundle"
        )

        XCTAssertEqual(
            try evaluate("https://example.com"),
            .allowed(handler: Self.safari)
        )
    }

    func testBlockedSetsCoverTheVerifiedEntries() throws {
        XCTAssertEqual(
            UrlOpenPolicy.blockedSchemes,
            ["file", "shortcuts", "x-man-page", "ssh", "telnet", "smb", "afp", "nfs", "cifs", "ftp", "ftps", "sftp", "vnc", "help"]
        )
        for identifier in [
            "com.apple.terminal", "com.apple.scripteditor2", "com.apple.shortcuts", "com.apple.automator",
            "com.apple.netauthagent", "com.microsoft.vscode", "com.runningwithcrayons.alfred",
            "com.microsoft.vscodeinsiders", "com.vscodium", "com.exafunction.windsurf", "dev.zed.zed",
            "com.jetbrains.toolbox", "dev.warp.warp-stable",
        ] {
            XCTAssertTrue(UrlOpenPolicy.blockedHandlerBundleIdentifiers.contains(identifier), identifier)
        }
        for identifier in ["com.latenightsw.ScriptDebugger", "com.latenightsw.ScriptDebugger8"] {
            assertRejected(try evaluate("applescript://x", bundleIdentifier: identifier), "handler id \(identifier)")
        }
    }

    func testHandlerWithoutReadableBundleIdentifierIsRejected() throws {
        assertRejected(try evaluate("myscheme://x", bundleIdentifier: nil), "a handler with no bundle id")
    }

    // MARK: - Opening URLs

    /// The real opener must never activate the handler app: it would take focus from the app the user works in.
    func testRealOpenerDoesNotActivateTheHandler() {
        XCTAssertFalse(ShortcutAndUrlLauncher.backgroundOpenConfiguration().activates)
    }

    func testOpenerIsCalledOnlyWhenAllowed() throws {
        let recorder = OpenerRecorder()
        let launcher = ShortcutAndUrlLauncher(
            handlerResolver: { url in
                url.scheme?.lowercased() == "myscheme" ? nil : Self.safari
            },
            bundleIdentifierResolver: { _ in "com.apple.Safari" },
            opener: { url, handler in recorder.record(url, handler) }
        )

        let table = [
            "https://example.com",
            "file:///etc/hosts",
            "FILE:///etc/hosts",
            "ssh://h",
            "shortcuts://run-shortcut?name=x",
            "smb://h/s",
            "help:anchor=x",
            "myscheme://x",
        ]
        var opened = 0
        for raw in table {
            do {
                _ = try launcher.openURL(raw)
                opened += 1
            } catch let error as ShortcutAndUrlLauncherError {
                guard case .rejected = error else { return XCTFail("\(raw): expected rejected, got \(error)") }
            }
        }

        XCTAssertEqual(opened, 1)
        XCTAssertEqual(recorder.calls.count, 1)
        XCTAssertEqual(recorder.calls.first?.url.absoluteString, "https://example.com")
    }

    func testOpenerReceivesTheCheckedHandler() throws {
        let recorder = OpenerRecorder()
        let resolutions = CallCounter()
        let launcher = ShortcutAndUrlLauncher(
            handlerResolver: { _ in
                resolutions.increment()
                return Self.safari
            },
            bundleIdentifierResolver: { _ in "com.apple.Safari" },
            opener: { url, handler in recorder.record(url, handler) }
        )

        let message = try launcher.openURL("https://example.com")

        XCTAssertEqual(recorder.calls.count, 1)
        XCTAssertEqual(recorder.calls.first?.handler, Self.safari)
        XCTAssertEqual(resolutions.count, 1, "the handler is resolved once, so the checked app is the one that opens")
        XCTAssertTrue(message.hasPrefix("Opened https://example.com with"), message)
        XCTAssertTrue(message.contains("Safari"), message)
    }

    func testOpenFailureIsReported() {
        let recorder = OpenerRecorder()
        recorder.result = false
        let launcher = ShortcutAndUrlLauncher(
            handlerResolver: { _ in Self.safari },
            bundleIdentifierResolver: { _ in "com.apple.Safari" },
            opener: { url, handler in recorder.record(url, handler) }
        )

        XCTAssertThrowsError(try launcher.openURL("https://example.com")) { error in
            guard case ShortcutAndUrlLauncherError.openFailed = error else {
                return XCTFail("expected openFailed, got \(error)")
            }
        }
    }

    func testUnparseableURLIsRejectedBeforeAnyResolution() {
        let recorder = OpenerRecorder()
        let launcher = ShortcutAndUrlLauncher(
            handlerResolver: { _ in Self.safari },
            bundleIdentifierResolver: { _ in "com.apple.Safari" },
            opener: { url, handler in recorder.record(url, handler) }
        )

        XCTAssertThrowsError(try launcher.openURL("")) { error in
            guard case ShortcutAndUrlLauncherError.invalidURL = error else {
                return XCTFail("expected invalidURL, got \(error)")
            }
        }
        XCTAssertTrue(recorder.calls.isEmpty)
    }

    // MARK: - Shortcuts

    func testShortcutNameCannotInjectOptions() {
        // The executable does not exist: a name that slipped past validation would fail differently.
        let launcher = ShortcutAndUrlLauncher(
            shortcutsExecutablePath: root.appendingPathComponent("missing-shortcuts").path,
            temporaryRoot: root
        )

        for name in ["-i", "--output-path", ""] {
            XCTAssertThrowsError(try launcher.runShortcut(name: name, input: nil, timeout: 5), name) { error in
                guard case ShortcutAndUrlLauncherError.invalidShortcutName = error else {
                    return XCTFail("\(name): expected invalidShortcutName, got \(error)")
                }
            }
        }
    }

    func testShortcutRunArguments() {
        XCTAssertEqual(
            ShortcutAndUrlLauncher.shortcutRunArguments(name: "Mail Digest", inputPath: nil),
            ["run", "Mail Digest"]
        )
        XCTAssertEqual(
            ShortcutAndUrlLauncher.shortcutRunArguments(name: "Mail Digest", inputPath: "/tmp/in.txt"),
            ["run", "Mail Digest", "--input-path", "/tmp/in.txt"]
        )
    }

    func testShortcutInputFileIsPrivateAndRemoved() throws {
        let markers = root.appendingPathComponent("markers", isDirectory: true)
        try FileManager.default.createDirectory(at: markers, withIntermediateDirectories: true)
        let inputs = root.appendingPathComponent("inputs", isDirectory: true)
        try FileManager.default.createDirectory(at: inputs, withIntermediateDirectories: true)
        let executable = try writeExecutable(
            named: "fake-shortcuts",
            body: """
            /usr/bin/stat -f %Lp "$4" > "\(markers.path)/file-mode"
            /usr/bin/dirname "$4" > "\(markers.path)/input-directory"
            /usr/bin/stat -f %Lp "$(/usr/bin/dirname "$4")" > "\(markers.path)/directory-mode"
            /bin/cat "$4" > "\(markers.path)/content"
            """
        )
        let launcher = ShortcutAndUrlLauncher(
            shortcutsExecutablePath: executable,
            temporaryRoot: inputs,
            baseEnvironment: ["PATH": "/usr/bin:/bin", "HOME": root.path]
        )

        let outcome = try launcher.runShortcut(name: "x", input: "hi", timeout: 5)

        XCTAssertEqual(outcome.exitStatus, 0)
        func marker(_ name: String) throws -> String {
            try String(contentsOf: markers.appendingPathComponent(name), encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        XCTAssertEqual(try marker("file-mode"), "600")
        XCTAssertEqual(try marker("directory-mode"), "700")
        XCTAssertEqual(try marker("content"), "hi")
        let inputDirectory = try marker("input-directory")
        XCTAssertTrue(inputDirectory.hasPrefix(inputs.path) || inputDirectory.hasPrefix("/private" + inputs.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: inputDirectory), "the input directory is removed")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: inputs.path), [])
    }

    func testShortcutWithoutInputPassesNoInputPath() throws {
        let executable = try writeExecutable(named: "fake-shortcuts", body: "echo \"count:$# args:$*\"")
        let launcher = ShortcutAndUrlLauncher(
            shortcutsExecutablePath: executable,
            temporaryRoot: root,
            baseEnvironment: ["PATH": "/usr/bin:/bin", "HOME": root.path]
        )

        let outcome = try launcher.runShortcut(name: "Mail Digest", input: nil, timeout: 5)

        XCTAssertEqual(outcome.exitStatus, 0)
        XCTAssertTrue(outcome.resultText.contains("count:2 args:run Mail Digest"), outcome.resultText)
        XCTAssertNil(outcome.errorNumber)
    }

    func testListShortcutsRunsTheListSubcommand() throws {
        let executable = try writeExecutable(named: "fake-shortcuts", body: "echo \"args:$*\"; echo Alpha; echo Beta")
        let launcher = ShortcutAndUrlLauncher(
            shortcutsExecutablePath: executable,
            temporaryRoot: root,
            baseEnvironment: ["PATH": "/usr/bin:/bin", "HOME": root.path]
        )

        let listing = try launcher.listShortcuts(timeout: 5)

        XCTAssertTrue(listing.contains("args:list"), listing)
        XCTAssertTrue(listing.contains("Alpha"), listing)
        XCTAssertTrue(listing.contains("Beta"), listing)
    }
}
