import AppKit
import Darwin
import Dispatch
import Foundation

public enum UrlOpenVerdict: Equatable {
    case allowed(handler: URL)
    case rejected(String)
}

/// Decides whether a URL may be opened on the agent's behalf.
///
/// This policy is friction, not a boundary: `run_script` can still `open location` or drive Finder, so it only keeps
/// a well-behaved agent away from handlers that execute code or mount remote volumes.
public enum UrlOpenPolicy {
    public static let blockedSchemes: Set<String> = [
        "file", "shortcuts", "x-man-page", "ssh", "telnet",
        "smb", "afp", "nfs", "cifs", "ftp", "ftps", "sftp", "vnc", "help",
    ]

    /// Stored lowercased; compared lowercased. Entries marked unverified were not installed on the machine where the
    /// list was written and should be confirmed against the app's `Info.plist` where available.
    public static let blockedHandlerBundleIdentifiers: Set<String> = [
        "com.apple.terminal",
        "com.apple.scripteditor2",
        "com.apple.shortcuts",
        "com.apple.automator",
        "com.apple.netauthagent",
        "com.microsoft.vscode",
        "com.runningwithcrayons.alfred",
        // Unverified:
        "com.googlecode.iterm2",
        "com.apple.screensharing",
        "com.apple.helpviewer",
        "com.todesktop.230313mzl4w4u92",
        "com.raycast.macos",
        "org.hammerspoon.hammerspoon",
        "com.hegenberg.bettertouchtool",
        "com.stairways.keyboardmaestro.engine",
        "com.microsoft.vscodeinsiders",
        "com.vscodium",
        "com.exafunction.windsurf",
        "dev.zed.zed",
        "com.jetbrains.toolbox",
        "dev.warp.warp-stable",
    ]

    /// Handlers blocked by bundle id prefix, for apps that ship one id per major version (Script Debugger is
    /// `com.latenightsw.ScriptDebugger8` and so on). Stored lowercased; compared lowercased.
    public static let blockedHandlerBundleIdentifierPrefixes: [String] = [
        "com.latenightsw.scriptdebugger",
    ]

    public static func evaluate(
        _ url: URL,
        handlerResolver: (URL) -> URL?,
        bundleIdentifierResolver: (URL) -> String?
    ) -> UrlOpenVerdict {
        guard let scheme = url.scheme?.lowercased(), !scheme.isEmpty else {
            return .rejected("URL has no scheme")
        }
        if blockedSchemes.contains(scheme) {
            return .rejected("the \(scheme): scheme is blocked")
        }
        guard let handler = handlerResolver(url) else {
            return .rejected("no app is registered to open \(scheme): URLs")
        }
        guard handler.pathExtension.lowercased() == "app" else {
            return .rejected("the handler for \(scheme): URLs is not an app bundle")
        }
        // A handler whose identity cannot be read cannot be checked against the lists, so it is refused.
        guard let identifier = bundleIdentifierResolver(handler)?.lowercased(), !identifier.isEmpty else {
            return .rejected("the handler for \(scheme): URLs has no readable bundle identifier")
        }
        if blockedHandlerBundleIdentifiers.contains(identifier)
            || blockedHandlerBundleIdentifierPrefixes.contains(where: identifier.hasPrefix) {
            return .rejected("the handler for \(scheme): URLs (\(identifier)) is blocked")
        }
        return .allowed(handler: handler)
    }
}

public enum ShortcutAndUrlLauncherError: Error, Equatable {
    case invalidURL(String)
    case rejected(String)
    case openFailed(String)
    case invalidShortcutName(String)
}

/// Opens URLs through a vetted handler and runs or lists Shortcuts through the confined child runner.
public struct ShortcutAndUrlLauncher {
    public static let defaultShortcutsExecutablePath = "/usr/bin/shortcuts"
    private static let openTimeoutSeconds = 10
    private static let maximumErrorMessageCharacters = 2_048

    private let handlerResolver: (URL) -> URL?
    private let bundleIdentifierResolver: (URL) -> String?
    private let opener: (_ url: URL, _ handler: URL) -> Bool
    private let shortcutsExecutablePath: String
    private let temporaryRoot: URL
    private let baseEnvironment: [String: String]

    public init(
        handlerResolver: @escaping (URL) -> URL? = { NSWorkspace.shared.urlForApplication(toOpen: $0) },
        bundleIdentifierResolver: @escaping (URL) -> String? = { Bundle(url: $0)?.bundleIdentifier },
        opener: @escaping (_ url: URL, _ handler: URL) -> Bool = ShortcutAndUrlLauncher.openWithCheckedHandler,
        shortcutsExecutablePath: String = ShortcutAndUrlLauncher.defaultShortcutsExecutablePath,
        temporaryRoot: URL = FileManager.default.temporaryDirectory,
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.handlerResolver = handlerResolver
        self.bundleIdentifierResolver = bundleIdentifierResolver
        self.opener = opener
        self.shortcutsExecutablePath = shortcutsExecutablePath
        self.temporaryRoot = temporaryRoot
        self.baseEnvironment = baseEnvironment
    }

    // MARK: - URLs

    /// The handler that passed the policy is the handler that opens the URL: it is resolved once and handed to the
    /// opener, so it cannot change between the check and the launch.
    public func openURL(_ rawURL: String) throws -> String {
        guard let url = URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw ShortcutAndUrlLauncherError.invalidURL(rawURL)
        }
        switch UrlOpenPolicy.evaluate(
            url,
            handlerResolver: handlerResolver,
            bundleIdentifierResolver: bundleIdentifierResolver
        ) {
        case .rejected(let reason):
            throw ShortcutAndUrlLauncherError.rejected(reason)
        case .allowed(let handler):
            guard opener(url, handler) else {
                throw ShortcutAndUrlLauncherError.openFailed(url.absoluteString)
            }
            return "Opened \(url.absoluteString) with \(handler.deletingPathExtension().lastPathComponent)."
        }
    }

    public static func openWithCheckedHandler(_ url: URL, handler: URL) -> Bool {
        let finished = DispatchSemaphore(value: 0)
        let outcome = OpenOutcome()
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: handler,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            outcome.succeeded = (error == nil)
            finished.signal()
        }
        guard finished.wait(timeout: .now() + .seconds(openTimeoutSeconds)) == .success else {
            return false
        }
        return outcome.succeeded
    }

    /// Written by the completion handler, read only after the semaphore signals.
    private final class OpenOutcome: @unchecked Sendable {
        var succeeded = false
    }

    // MARK: - Shortcuts

    static func shortcutRunArguments(name: String, inputPath: String?) -> [String] {
        var arguments = ["run", name]
        if let inputPath {
            arguments += ["--input-path", inputPath]
        }
        return arguments
    }

    public func runShortcut(name: String, input: String?, timeout: TimeInterval) throws -> ScriptRunOutcome {
        guard !name.isEmpty, !name.hasPrefix("-"), !name.contains("\0") else {
            throw ShortcutAndUrlLauncherError.invalidShortcutName(name)
        }

        var inputDirectory: URL?
        defer {
            if let inputDirectory {
                try? FileManager.default.removeItem(at: inputDirectory)
            }
        }
        var inputPath: String?
        if let input {
            let directory = temporaryRoot.appendingPathComponent(
                "shortcut-input-\(UUID().uuidString)",
                isDirectory: true
            )
            guard mkdir(directory.path, 0o700) == 0 else { throw Self.posixError() }
            inputDirectory = directory
            let file = directory.appendingPathComponent("input.txt")
            try Self.writePrivateFile(Data(input.utf8), to: file.path)
            inputPath = file.path
        }

        let result = try ConfinedChildProcessRunner.run(
            ConfinedChildProcessRequest(
                executablePath: shortcutsExecutablePath,
                arguments: Self.shortcutRunArguments(name: name, inputPath: inputPath),
                environment: ConfinedChildProcessRunner.scrubbedEnvironment(from: baseEnvironment),
                timeout: timeout
            )
        )

        var resultText = OsascriptChildRunner.decodeOutput(result.standardOutput)
        if resultText.hasSuffix("\n") {
            resultText.removeLast()
        }
        let standardError = OsascriptChildRunner.decodeOutput(result.standardError)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ScriptRunOutcome(
            resultText: resultText,
            errorNumber: nil,
            errorMessage: standardError.isEmpty ? nil : String(standardError.prefix(Self.maximumErrorMessageCharacters)),
            timedOut: result.timedOut,
            exitStatus: result.exitStatus,
            durationMilliseconds: Int(result.duration * 1000),
            outputTruncated: result.standardOutputTruncated || result.standardErrorTruncated
        )
    }

    public func listShortcuts(timeout: TimeInterval) throws -> String {
        let result = try ConfinedChildProcessRunner.run(
            ConfinedChildProcessRequest(
                executablePath: shortcutsExecutablePath,
                arguments: ["list"],
                environment: ConfinedChildProcessRunner.scrubbedEnvironment(from: baseEnvironment),
                timeout: timeout
            )
        )
        let listing = OsascriptChildRunner.decodeOutput(result.standardOutput)
        if listing.isEmpty, result.timedOut || result.exitStatus != 0 {
            let reason = OsascriptChildRunner.decodeOutput(result.standardError)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let status = result.timedOut ? "timed out" : "exit \(result.exitStatus.map(String.init) ?? "signal")"
            return "shortcuts list failed (\(status))" + (reason.isEmpty ? "" : ": \(reason.prefix(Self.maximumErrorMessageCharacters))")
        }
        return listing
    }

    // MARK: - Files

    /// Created exclusively, without following links, owner read/write only.
    private static func writePrivateFile(_ data: Data, to path: String) throws {
        let descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw posixError() }
        defer { close(descriptor) }
        _ = fchmod(descriptor, 0o600)

        var written = 0
        let bytes = [UInt8](data)
        while written < bytes.count {
            let count = bytes.withUnsafeBytes { pointer -> Int in
                guard let base = pointer.baseAddress else { return -1 }
                return write(descriptor, base + written, bytes.count - written)
            }
            if count > 0 {
                written += count
            } else if count < 0 && errno == EINTR {
                continue
            } else {
                throw posixError()
            }
        }
    }

    private static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
