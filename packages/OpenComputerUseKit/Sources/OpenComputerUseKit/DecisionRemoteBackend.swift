import Darwin
import Foundation

// Backend selection and the remote jev-engine config file for the decide_next_action advisory tool.
//
// Trust model (why the file, not the per-call environment): the app agent applies per-call `environment` from any
// same-uid socket peer (see `MacSessionLockPolicy.sanitizePeerEnvironment`). If a remote URL and bearer key could
// arrive per call, any unprivileged same-uid process could make the TCC-privileged agent ship another app's
// accessibility rows to a host of its choosing. So the destination, model name, and key are read only from
// `~/Library/Application Support/OpenComputerUse/decision-model/remote-backend.json` — the same trust root as the
// llama sidecar's pid file (outside every sandbox container; see `DecisionSidecarVerifier.swift`). Per-call
// environment may only select which backend to use, via `DecisionBackendSelection`, never the destination itself.
// Residual (documented, same as the sidecar): a non-sandboxed same-uid process can rewrite the file; it already has
// the user's full file access.

/// Which decision-model backend a call uses, resolved once from the per-call environment before any file or network
/// access. `.remote` never reads `OPEN_COMPUTER_USE_DECISION_MODEL_URL`; it always loads the trusted config file.
public enum DecisionBackendSelection: Equatable, Sendable {
    case llama
    case remote

    public static let environmentKey = "OPEN_COMPUTER_USE_DECISION_MODEL_BACKEND"

    /// Absent, blank, or "llama" (case-insensitive) -> `.llama`, today's behaviour exactly. "remote" -> `.remote`.
    /// Any other value throws. "remote" combined with a non-empty `OPEN_COMPUTER_USE_DECISION_MODEL_URL` also
    /// throws: the combination is ambiguous about which endpoint the call means.
    public static func resolve(environment: [String: String]) throws -> DecisionBackendSelection {
        let raw = environment[environmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasLlamaURL = !(environment[DecisionModelEndpoint.environmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        switch raw.lowercased() {
        case "", "llama":
            return .llama
        case "remote":
            guard !hasLlamaURL else {
                throw DecisionModelError.remoteConfig(
                    "\(environmentKey)=remote cannot be combined with a non-empty "
                        + "\(DecisionModelEndpoint.environmentKey); unset one of them"
                )
            }
            return .remote
        default:
            throw DecisionModelError.remoteConfig("\(environmentKey) must be \"llama\" or \"remote\"")
        }
    }
}

/// The validated contents of the remote-backend config file: a base URL, a model name, and a bearer key.
public struct DecisionRemoteBackendConfig: Equatable, Sendable {
    /// "https://<host>[:<port>]" — no path, no trailing slash.
    public let baseURL: URL
    public let model: String
    public let apiKey: String

    public init(baseURL: URL, model: String, apiKey: String) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
    }

    /// baseURL + "/v1/completions"
    public var completionsURL: URL { URL(string: baseURL.absoluteString + "/v1/completions")! }
    /// baseURL + "/tokenize"
    public var tokenizeURL: URL { URL(string: baseURL.absoluteString + "/tokenize")! }
}

/// Redacts `apiKey` from every textual/reflective representation, so a stray `String(describing:)`,
/// `String(reflecting:)`, `dump(_:)`, or `po` in a debugger never prints it — even though nothing in this codebase
/// currently logs a `DecisionRemoteBackendConfig`.
extension DecisionRemoteBackendConfig: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "DecisionRemoteBackendConfig(baseURL: \(baseURL), model: \(model), apiKey: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["baseURL": baseURL, "model": model, "apiKey": "<redacted>"])
    }
}

/// Loads and validates `remote-backend.json`. Every failure names the file path and the failing field; none ever
/// echoes a config value, so a squatting or misconfigured file can never leak `api_key` into a tool result or log.
public enum DecisionRemoteBackendConfigLoader {
    public static var defaultConfigFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/OpenComputerUse/decision-model/remote-backend.json")
    }

    /// Same cap as the sidecar's other trusted files: large enough for the three fields, small enough to bound
    /// parsing cost regardless of who last wrote the file.
    static let maxFileSizeBytes = 16 * 1024
    static let maxModelCharacters = 200
    static let maxAPIKeyCharacters = 512

    public static func load(from url: URL = defaultConfigFileURL) throws -> DecisionRemoteBackendConfig {
        let data = try readValidated(path: url.path)
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw DecisionModelError.remoteConfig("\(url.path) is not a JSON object")
        }

        // Unknown keys are ignored: only these three fields are read.
        guard let rawBaseURL = object["base_url"] as? String, !rawBaseURL.isEmpty else {
            throw DecisionModelError.remoteConfig("\(url.path): base_url is missing or not a string")
        }
        let baseURL = try parseBaseURL(rawBaseURL, path: url.path)

        guard let model = object["model"] as? String, isValidModel(model) else {
            throw DecisionModelError.remoteConfig(
                "\(url.path): model must be 1-\(maxModelCharacters) characters with no control characters"
            )
        }

        guard let apiKey = object["api_key"] as? String, isValidAPIKey(apiKey) else {
            throw DecisionModelError.remoteConfig(
                "\(url.path): api_key must be 1-\(maxAPIKeyCharacters) printable ASCII characters with no whitespace"
            )
        }

        return DecisionRemoteBackendConfig(baseURL: baseURL, model: model, apiKey: apiKey)
    }

    /// Opens the file by path exactly once and validates the *opened descriptor*, not a separate `lstat`/`stat` of
    /// the path: `O_NOFOLLOW` refuses a symlink at `open(2)` itself (no TOCTOU window where the path could be
    /// swapped between a check and a later open), `O_NONBLOCK` keeps a FIFO from blocking this call forever if the
    /// path were ever swapped for one, and every check below (`fstat`, size, the read loop) runs against that same
    /// fd — so nothing here re-resolves the path a second time.
    private static func readValidated(path: String) throws -> Data {
        let fd = path.withCString { open($0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC) }
        guard fd >= 0 else {
            if errno == ELOOP {
                throw DecisionModelError.remoteConfig("\(path) must be a regular file, not a symlink")
            }
            throw DecisionModelError.remoteConfig("no remote-backend config file at \(path)")
        }
        defer { close(fd) }

        var status = stat()
        guard fstat(fd, &status) == 0 else {
            throw DecisionModelError.remoteConfig("\(path) could not be inspected")
        }
        // A symlink cannot reach here (O_NOFOLLOW above), but a FIFO, device, or other non-regular file opened
        // without blocking still can; refuse anything that is not a plain regular file before ever reading it.
        guard status.st_mode & S_IFMT == S_IFREG else {
            throw DecisionModelError.remoteConfig("\(path) must be a regular file, not a symlink")
        }
        guard status.st_uid == getuid() else {
            throw DecisionModelError.remoteConfig("\(path) must be owned by the current user")
        }
        guard status.st_mode & 0o077 == 0 else {
            throw DecisionModelError.remoteConfig("\(path) must not be readable or writable by group or other")
        }
        guard status.st_size <= maxFileSizeBytes else {
            throw DecisionModelError.remoteConfig("\(path) exceeds the \(maxFileSizeBytes)-byte size cap")
        }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let bytesRead = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if bytesRead < 0 {
                throw DecisionModelError.remoteConfig("\(path) is unreadable")
            }
            if bytesRead == 0 { break }
            data.append(buffer, count: bytesRead)
            // Defence in depth beyond the fstat size check above: never buffer more than the cap even if the file
            // grows between fstat and this read.
            guard data.count <= maxFileSizeBytes else {
                throw DecisionModelError.remoteConfig("\(path) exceeds the \(maxFileSizeBytes)-byte size cap")
            }
        }
        return data
    }

    /// https only, non-empty host, optional port 1-65535, no userinfo/query/fragment, path empty or "/". Stored
    /// without a trailing slash.
    private static func parseBaseURL(_ raw: String, path: String) throws -> URL {
        guard let components = URLComponents(string: raw), let scheme = components.scheme,
              scheme.lowercased() == "https"
        else { throw DecisionModelError.remoteConfig("\(path): base_url must use https") }
        guard components.percentEncodedUser == nil, components.percentEncodedPassword == nil,
              components.percentEncodedQuery == nil, components.percentEncodedFragment == nil,
              components.percentEncodedPath.isEmpty || components.percentEncodedPath == "/"
        else {
            throw DecisionModelError.remoteConfig(
                "\(path): base_url must not carry userinfo, a query, a fragment, or a path beyond \"/\""
            )
        }
        guard let host = components.percentEncodedHost, !host.isEmpty else {
            throw DecisionModelError.remoteConfig("\(path): base_url must name a host")
        }
        if let port = components.port {
            guard (1...65_535).contains(port) else {
                throw DecisionModelError.remoteConfig("\(path): base_url port must be between 1 and 65535")
            }
        }
        let portSuffix = components.port.map { ":\($0)" } ?? ""
        guard let url = URL(string: "https://\(host)\(portSuffix)") else {
            throw DecisionModelError.remoteConfig("\(path): base_url is malformed")
        }
        return url
    }

    private static func isValidModel(_ value: String) -> Bool {
        guard (1...maxModelCharacters).contains(value.count) else { return false }
        return !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    /// Printable ASCII (0x21-0x7E), no whitespace of any kind.
    private static func isValidAPIKey(_ value: String) -> Bool {
        guard (1...maxAPIKeyCharacters).contains(value.count) else { return false }
        return value.unicodeScalars.allSatisfy { (0x21...0x7E).contains($0.value) }
    }
}
