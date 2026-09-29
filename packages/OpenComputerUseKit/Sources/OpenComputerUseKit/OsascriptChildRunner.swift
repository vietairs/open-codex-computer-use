import Foundation

public struct ScriptRunOutcome: Equatable, Sendable {
    public let resultText: String
    public let errorNumber: Int?
    public let errorMessage: String?
    public let timedOut: Bool
    public let exitStatus: Int32?
    public let durationMilliseconds: Int
    public let outputTruncated: Bool
}

public enum OsascriptChildRunnerError: Error, Equatable {
    case sourceTooLarge(byteCount: Int)
}

/// Runs script source through `/usr/bin/osascript` as a confined child, reading the source from standard input.
public struct OsascriptChildRunner: Sendable {
    public static let defaultExecutablePath = "/usr/bin/osascript"
    public static let defaultTimeout: TimeInterval = 20
    public static let maximumTimeout: TimeInterval = 60
    public static let firstContactMinimumTimeout: TimeInterval = 30
    public static let maximumSourceBytes = 65_536
    private static let maximumErrorMessageCharacters = 2_048

    public let executablePath: String
    public let baseEnvironment: [String: String]

    public init(
        executablePath: String = OsascriptChildRunner.defaultExecutablePath,
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.executablePath = executablePath
        self.baseEnvironment = baseEnvironment
    }

    public static func arguments(for language: ScriptLanguage) -> [String] {
        switch language {
        case .applescript:
            return ["-l", "AppleScript", "-"]
        case .javascript:
            return ["-l", "JavaScript", "-"]
        }
    }

    /// The last `(<signed integer>)` in the text, e.g. `execution error: ... (-1743)` gives -1743.
    public static func parseErrorNumber(fromStandardError text: String) -> Int? {
        guard let expression = try? NSRegularExpression(pattern: "\\((-?[0-9]+)\\)") else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = expression.matches(in: text, range: range).last,
              let numberRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Int(text[numberRange])
    }

    /// Nil or non-positive requests use the default, everything is clamped to the maximum, and a first call to a
    /// target app is raised to `firstContactFloor` (a permission prompt may be waiting on the user).
    public static func effectiveTimeout(
        requested: TimeInterval?,
        isFirstContactWithTarget: Bool,
        firstContactFloor: TimeInterval = OsascriptChildRunner.firstContactMinimumTimeout
    ) -> TimeInterval {
        var value = defaultTimeout
        if let requested, requested > 0 {
            value = requested
        }
        value = min(value, maximumTimeout)
        if isFirstContactWithTarget {
            value = max(value, firstContactFloor)
        }
        return value
    }

    public static func userFacingMessage(errorNumber: Int, app: String) -> String? {
        switch errorNumber {
        case -1743:
            return "Automation permission denied: the app that launched this MCP server (your terminal, or the "
                + "Claude/Codex app) may not control \(app). Approve it in System Settings > Privacy & Security > "
                + "Automation, then retry."
        case -600:
            return "\(app) is not running."
        case -1712:
            return "\(app) did not answer in time; keep queries small (one mailbox, first N results)."
        default:
            return nil
        }
    }

    /// Never `String(data:encoding:)`: it returns nil when the byte cap splits a multi-byte character.
    static func decodeOutput(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }

    public func run(source: String, language: ScriptLanguage, timeout: TimeInterval) throws -> ScriptRunOutcome {
        let sourceBytes = Data(source.utf8)
        guard sourceBytes.count <= Self.maximumSourceBytes else {
            throw OsascriptChildRunnerError.sourceTooLarge(byteCount: sourceBytes.count)
        }
        let result = try ConfinedChildProcessRunner.run(
            ConfinedChildProcessRequest(
                executablePath: executablePath,
                arguments: Self.arguments(for: language),
                standardInput: sourceBytes,
                environment: ConfinedChildProcessRunner.scrubbedEnvironment(from: baseEnvironment),
                timeout: timeout
            )
        )

        var resultText = Self.decodeOutput(result.standardOutput)
        if resultText.hasSuffix("\n") {
            resultText.removeLast()
        }
        let standardError = Self.decodeOutput(result.standardError).trimmingCharacters(in: .whitespacesAndNewlines)
        let errorMessage = standardError.isEmpty ? nil : String(standardError.prefix(Self.maximumErrorMessageCharacters))
        let errorNumber = result.exitStatus != 0 ? Self.parseErrorNumber(fromStandardError: standardError) : nil

        return ScriptRunOutcome(
            resultText: resultText,
            errorNumber: errorNumber,
            errorMessage: errorMessage,
            timedOut: result.timedOut,
            exitStatus: result.exitStatus,
            durationMilliseconds: Int(result.duration * 1000),
            outputTruncated: result.standardOutputTruncated || result.standardErrorTruncated
        )
    }
}
