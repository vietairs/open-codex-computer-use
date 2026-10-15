import Foundation
import CoreGraphics
import Darwin

/// Shared path resolution and app-agent forwarding for the screenshot configuration.
///
/// The configuration only ever carries screenshot encoding preferences. It never carries a permission,
/// lock-screen or safety setting, and nothing read from it is executed.
///
/// The config file is read only by the process that owns the calling host: the CLI, an in-process server, or
/// the proxy that relays to the app agent. The agent never opens a config path a caller names; it receives the
/// proxy's validated `OPEN_COMPUTER_USE_IMAGE_*` values with each call and applies them to that call alone.
public enum OCUConfiguration {
    /// The per-call settings the proxy forwards to the app agent.
    public static let imageEnvironmentKeys: Set<String> = [
        "OPEN_COMPUTER_USE_IMAGE_FORMAT",
        "OPEN_COMPUTER_USE_IMAGE_JPEG_QUALITY",
        "OPEN_COMPUTER_USE_IMAGE_CAPTURE_TIMEOUT",
        "OPEN_COMPUTER_USE_IMAGE_MAX_DIMENSION",
        "OPEN_COMPUTER_USE_IMAGE_SCALE_DOWN_AFTER_MAX_SIZE",
        "OPEN_COMPUTER_USE_IMAGE_DISCARD_BELOW_PIXEL_COUNT",
    ]

    /// Every environment key the configuration reads in the caller's own process.
    public static let environmentKeys: Set<String> = imageEnvironmentKeys.union([configFileKey])

    /// Names the config file in the caller's own process. It never crosses the app-agent socket.
    public static let configFileKey = "OPEN_COMPUTER_USE_CONFIG_FILE"

    /// Largest config file that is read. A real file holds a few hundred bytes.
    static let maxFileBytes: off_t = 64 * 1024

    /// Upper bound of `captureTimeout`, in seconds. A stalled capture holds its call for at most this long.
    static let maxCaptureTimeout: Double = 30

    /// The part of a peer's per-call environment that has to be set on the agent process for the call. The
    /// screenshot settings are excluded: they travel with the call and are never written to the shared process
    /// environment, so a call that carries only those needs no process-wide lock.
    public static func processOverrides(from environment: [String: String]) -> [String: String] {
        environment.filter { !environmentKeys.contains($0.key) }
    }

    /// The per-call environment a proxy relays to the agent: the sanitized process environment, with the raw
    /// screenshot keys and the config file path removed and `imageSettings` (already validated, or nil when the
    /// call takes no screenshot) put in their place.
    public static func relayedEnvironment(
        processEnvironment: [String: String],
        imageSettings: [String: String]?
    ) -> [String: String] {
        var environment = MacSessionLockPolicy.sanitizePeerEnvironment(processEnvironment)
        for key in environmentKeys {
            environment.removeValue(forKey: key)
        }
        for (key, value) in imageSettings ?? [:] where imageEnvironmentKeys.contains(key) {
            environment[key] = value
        }
        return environment
    }

    /// The caller's resolved settings (environment over file over defaults) as validated `IMAGE_*` values, ready
    /// to travel with a relayed call. The proxy runs this in the calling host's own process.
    public static func forwardedImageEnvironment() -> [String: String] {
        ImageCaptureConfig.current.environmentValues
    }

    /// The process environment restricted to the keys that decide where the file is and what overrides it.
    public static var environment: [String: String] {
        let keys = environmentKeys.union(["HOME", "XDG_CONFIG_HOME"])
        return Dictionary(uniqueKeysWithValues: keys.compactMap { key in
            getenv(key).map { (key, String(cString: $0)) }
        })
    }

    public static func fileURL(environment: [String: String]) throws -> URL {
        if let override = environment[configFileKey], !override.isEmpty {
            guard override.hasPrefix("/") else { throw ConfigError.invalidPath }
            return URL(fileURLWithPath: override)
        }
        let base = environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 }
            ?? (environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path) + "/.config"
        guard base.hasPrefix("/") else { throw ConfigError.invalidPath }
        return URL(fileURLWithPath: base).appendingPathComponent("ocu/config.json")
    }

    enum ConfigError: Error { case invalidPath, notRegularFile, tooLarge }
}

enum ScreenshotFormat: String, Equatable {
    case png
    case jpg

    /// `jpeg` is accepted as an alias for `jpg`.
    init?(configValue: String) {
        switch configValue {
        case "png": self = .png
        case "jpg", "jpeg": self = .jpg
        default: return nil
        }
    }
}

/// Screenshot encoding preferences, resolved per capture with the precedence environment > file > defaults.
/// Every value is validated; anything out of range or of the wrong type is ignored with a warning, so a bad
/// file or environment value degrades to the previous layer instead of failing a capture.
struct ImageCaptureConfig: Equatable {
    var format: ScreenshotFormat = .png
    var jpegQuality: Double = 0.8
    var captureTimeout: TimeInterval = 5
    var scaleDownAfterMaxSize = true
    var discardBelowPixelCount = 64
    /// Longest edge, in pixels, of the returned image. `nil` disables the limit.
    var maxDimension: CGFloat? = 1280
    static let defaults = ImageCaptureConfig()

    /// The settings of this process: its environment over the config file over the defaults.
    static var current: ImageCaptureConfig {
        load(environment: OCUConfiguration.environment, warning: warn)
    }

    /// The settings a relayed call carries. Only the validated `IMAGE_*` values count; no config file is read and
    /// no path is followed, whatever else the call's environment holds. A missing or invalid value falls back to
    /// the default.
    static func forwarded(environment: [String: String]) -> ImageCaptureConfig {
        resolve(
            image: [:],
            environment: environment.filter { OCUConfiguration.imageEnvironmentKeys.contains($0.key) },
            warning: warn
        )
    }

    /// The canonical `IMAGE_*` form of these settings, accepted back by `forwarded(environment:)` unchanged.
    var environmentValues: [String: String] {
        [
            "OPEN_COMPUTER_USE_IMAGE_FORMAT": format.rawValue,
            "OPEN_COMPUTER_USE_IMAGE_JPEG_QUALITY": String(jpegQuality),
            "OPEN_COMPUTER_USE_IMAGE_CAPTURE_TIMEOUT": String(captureTimeout),
            "OPEN_COMPUTER_USE_IMAGE_MAX_DIMENSION": maxDimension.map { String(renderedInt($0)) } ?? "null",
            "OPEN_COMPUTER_USE_IMAGE_SCALE_DOWN_AFTER_MAX_SIZE": scaleDownAfterMaxSize ? "true" : "false",
            "OPEN_COMPUTER_USE_IMAGE_DISCARD_BELOW_PIXEL_COUNT": String(discardBelowPixelCount),
        ]
    }

    static func load(environment: [String: String], warning: (String) -> Void = { _ in }) -> ImageCaptureConfig {
        var document: [String: Any] = [:]
        do {
            let url = try OCUConfiguration.fileURL(environment: environment)
            if let data = try readConfigFile(at: url.path) {
                guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      root["image"] == nil || root["image"] is [String: Any] else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                document = root["image"] as? [String: Any] ?? [:]
            }
        } catch {
            warning("Cannot read config: \(error). Using environment/defaults.")
        }
        return resolve(image: document, environment: environment, warning: warning)
    }

    /// Returns nil when the file does not exist. The path is opened once without blocking and every check runs on
    /// that descriptor, so a path swapped for a fifo or a growing file after the open cannot block the reader or
    /// defeat the size limit. Only a regular file of at most `maxFileBytes` is read.
    private static func readConfigFile(at path: String) throws -> Data? {
        let descriptor = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            if errno == ENOENT { return nil }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { close(descriptor) }

        var status = stat()
        guard fstat(descriptor, &status) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard (status.st_mode & S_IFMT) == S_IFREG else { throw OCUConfiguration.ConfigError.notRegularFile }
        guard status.st_size <= OCUConfiguration.maxFileBytes else { throw OCUConfiguration.ConfigError.tooLarge }

        // Read one byte past the limit so a file that grew after the fstat is still caught.
        let limit = Int(OCUConfiguration.maxFileBytes) + 1
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while data.count < limit {
            let count = read(descriptor, &buffer, min(buffer.count, limit - data.count))
            if count < 0 {
                if errno == EINTR { continue }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        guard data.count <= Int(OCUConfiguration.maxFileBytes) else { throw OCUConfiguration.ConfigError.tooLarge }
        return data
    }

    static func resolve(
        image: [String: Any],
        environment: [String: String],
        warning: (String) -> Void = { _ in }
    ) -> ImageCaptureConfig {
        var result = defaults

        /// Parses a number from a JSON value (`text: false`) or an environment string (`text: true`).
        func number(_ raw: Any, text: Bool, min: Double, max: Double, integer: Bool) -> Double? {
            let parsed: Double?
            if text, let raw = raw as? String {
                parsed = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines))
            } else if !text, let raw = raw as? NSNumber, CFGetTypeID(raw) != CFBooleanGetTypeID() {
                parsed = raw.doubleValue
            } else {
                parsed = nil
            }
            guard let parsed, parsed.isFinite, parsed >= min, parsed <= max,
                  !integer || parsed.rounded(.down) == parsed else { return nil }
            return parsed
        }

        /// Layers file then environment over `fallback`; an invalid layer is skipped with a warning.
        func layered(_ name: String, _ envKey: String, _ fallback: Double, min: Double, max: Double, integer: Bool = false) -> Double {
            var value = fallback
            if let raw = image[name], !(raw is NSNull) {
                if let parsed = number(raw, text: false, min: min, max: max, integer: integer) { value = parsed }
                else { warning("Invalid image.\(name); using default") }
            }
            if let raw = environment[envKey] {
                if let parsed = number(raw, text: true, min: min, max: max, integer: integer) { value = parsed }
                else { warning("Invalid \(envKey); using file/default") }
            }
            return value
        }

        func boolean(_ name: String, _ envKey: String, _ fallback: Bool) -> Bool {
            var value = fallback
            if let raw = image[name] {
                if let raw = raw as? NSNumber, CFGetTypeID(raw) == CFBooleanGetTypeID() { value = raw.boolValue }
                else { warning("Invalid image.\(name); using default") }
            }
            if let raw = environment[envKey] {
                if raw == "true" || raw == "false" { value = raw == "true" }
                else { warning("Invalid \(envKey); using file/default") }
            }
            return value
        }

        if let raw = image["format"] {
            if let text = raw as? String, let format = ScreenshotFormat(configValue: text) { result.format = format }
            else { warning("Invalid image.format; using png") }
        }
        if let raw = environment["OPEN_COMPUTER_USE_IMAGE_FORMAT"] {
            if let format = ScreenshotFormat(configValue: raw) { result.format = format }
            else { warning("Invalid OPEN_COMPUTER_USE_IMAGE_FORMAT; using file/default") }
        }
        result.jpegQuality = layered("jpegQuality", "OPEN_COMPUTER_USE_IMAGE_JPEG_QUALITY", 0.8, min: 0, max: 1)
        result.captureTimeout = layered("captureTimeout", "OPEN_COMPUTER_USE_IMAGE_CAPTURE_TIMEOUT", 5, min: 0.01, max: OCUConfiguration.maxCaptureTimeout)
        result.scaleDownAfterMaxSize = boolean("scaleDownAfterMaxSize", "OPEN_COMPUTER_USE_IMAGE_SCALE_DOWN_AFTER_MAX_SIZE", true)
        result.discardBelowPixelCount = Int(layered(
            "discardBelowPixelCount", "OPEN_COMPUTER_USE_IMAGE_DISCARD_BELOW_PIXEL_COUNT", 64,
            min: 0, max: 268_435_456, integer: true
        ))

        // The long-edge limit is the one setting that may be switched off: file `null` or environment `null`.
        var maxDimension: Double? = 1280
        if let raw = image["maxLongEdgePixels"] {
            if raw is NSNull { maxDimension = nil }
            else if let parsed = number(raw, text: false, min: 1, max: 16384, integer: true) { maxDimension = parsed }
            else { warning("Invalid image.maxLongEdgePixels; using default") }
        }
        if let raw = environment["OPEN_COMPUTER_USE_IMAGE_MAX_DIMENSION"] {
            if raw == "null" { maxDimension = nil }
            else if let parsed = number(raw, text: true, min: 1, max: 16384, integer: true) { maxDimension = parsed }
            else { warning("Invalid OPEN_COMPUTER_USE_IMAGE_MAX_DIMENSION; using file/default") }
        }
        result.maxDimension = maxDimension.map { CGFloat($0) }
        return result
    }

    private static func warn(_ message: String) {
        FileHandle.standardError.write(Data("ocu config: \(message)\n".utf8))
    }
}
