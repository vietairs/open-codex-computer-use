import Foundation
import XCTest
@testable import OpenComputerUseKit

/// Covers the remote-backend trust boundary: `DecisionBackendSelection.resolve(environment:)` (per-call backend
/// choice) and `DecisionRemoteBackendConfigLoader.load(from:)` (the trusted config file: perms, ownership, JSON
/// shape). No test ever opens a socket; loader tests use a real temp file so `lstat`/`stat` behavior is exercised
/// exactly as in production, mirroring `DecisionSidecarVerifierTests`'s style.
final class DecisionRemoteBackendTests: XCTestCase {
    private var directory: URL!
    private var configFile: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocu-remote-backend-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        configFile = directory.appendingPathComponent("remote-backend.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A key with a distinctive value, so assertions can prove no error text ever echoes it.
    private static let distinctiveKey = "sk-jev-REDACTION-CANARY-9f31acb2"

    private func writeConfig(_ object: [String: Any], mode: Int = 0o600) throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        try data.write(to: configFile)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: configFile.path)
    }

    private func assertLoadThrowsRemoteConfig(
        _ fragment: String, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        XCTAssertThrowsError(
            try DecisionRemoteBackendConfigLoader.load(from: configFile), file: file, line: line
        ) { error in
            guard case let .remoteConfig(message) = error as? DecisionModelError else {
                return XCTFail("expected .remoteConfig, got \(error)", file: file, line: line)
            }
            XCTAssertTrue(message.contains(fragment), "\(message) should mention \(fragment)", file: file, line: line)
            XCTAssertFalse(message.contains(Self.distinctiveKey), message, file: file, line: line)
        }
    }

    // MARK: - Loader — happy path

    func testLoadAcceptsAWellFormedPrivateConfigFile() throws {
        try writeConfig([
            "base_url": "https://jev.example.com:8443", "model": "Qwen3.8-27B-NVFP4-jev",
            "api_key": Self.distinctiveKey,
        ])
        let config = try DecisionRemoteBackendConfigLoader.load(from: configFile)
        XCTAssertEqual(config.baseURL.absoluteString, "https://jev.example.com:8443")
        XCTAssertEqual(config.completionsURL.absoluteString, "https://jev.example.com:8443/v1/completions")
        XCTAssertEqual(config.tokenizeURL.absoluteString, "https://jev.example.com:8443/tokenize")
        XCTAssertEqual(config.model, "Qwen3.8-27B-NVFP4-jev")
        XCTAssertEqual(config.apiKey, Self.distinctiveKey)
    }

    func testLoadAcceptsNoPortAndIgnoresUnknownKeys() throws {
        try writeConfig([
            "base_url": "https://jev.example.com", "model": "qwen", "api_key": "key123", "extra_field": "ignored",
        ])
        let config = try DecisionRemoteBackendConfigLoader.load(from: configFile)
        XCTAssertEqual(config.baseURL.absoluteString, "https://jev.example.com")
    }

    func testLoadStripsATrailingSlashFromBaseURL() throws {
        try writeConfig(["base_url": "https://jev.example.com/", "model": "qwen", "api_key": "key123"])
        let config = try DecisionRemoteBackendConfigLoader.load(from: configFile)
        XCTAssertEqual(config.baseURL.absoluteString, "https://jev.example.com")
    }

    // MARK: - Loader — base_url validation

    func testLoadRejectsHTTPScheme() throws {
        try writeConfig(["base_url": "http://jev.example.com", "model": "qwen", "api_key": Self.distinctiveKey])
        try assertLoadThrowsRemoteConfig("https")
    }

    func testLoadRejectsUserinfoInBaseURL() throws {
        try writeConfig([
            "base_url": "https://user:pw@jev.example.com", "model": "qwen", "api_key": Self.distinctiveKey,
        ])
        try assertLoadThrowsRemoteConfig("userinfo")
    }

    func testLoadRejectsQueryInBaseURL() throws {
        try writeConfig([
            "base_url": "https://jev.example.com?x=1", "model": "qwen", "api_key": Self.distinctiveKey,
        ])
        try assertLoadThrowsRemoteConfig("userinfo")
    }

    func testLoadRejectsAPathBeyondRootInBaseURL() throws {
        try writeConfig([
            "base_url": "https://jev.example.com/v1", "model": "qwen", "api_key": Self.distinctiveKey,
        ])
        try assertLoadThrowsRemoteConfig("userinfo")
    }

    func testLoadRejectsAnOutOfRangePort() throws {
        try writeConfig([
            "base_url": "https://jev.example.com:0", "model": "qwen", "api_key": Self.distinctiveKey,
        ])
        try assertLoadThrowsRemoteConfig("port")
    }

    func testLoadRejectsAnEmptyOrMissingBaseURL() throws {
        try writeConfig(["base_url": "", "model": "qwen", "api_key": Self.distinctiveKey])
        try assertLoadThrowsRemoteConfig("base_url")
        try writeConfig(["model": "qwen", "api_key": Self.distinctiveKey])
        try assertLoadThrowsRemoteConfig("base_url")
    }

    // MARK: - Loader — model / api_key validation

    func testLoadRejectsMissingOrEmptyModel() throws {
        try writeConfig(["base_url": "https://jev.example.com", "model": "", "api_key": Self.distinctiveKey])
        try assertLoadThrowsRemoteConfig("model")
        try writeConfig(["base_url": "https://jev.example.com", "api_key": Self.distinctiveKey])
        try assertLoadThrowsRemoteConfig("model")
    }

    func testLoadRejectsAModelWithControlCharacters() throws {
        try writeConfig([
            "base_url": "https://jev.example.com", "model": "qwen\nrow", "api_key": Self.distinctiveKey,
        ])
        try assertLoadThrowsRemoteConfig("model")
    }

    func testLoadRejectsMissingOrEmptyAPIKey() throws {
        try writeConfig(["base_url": "https://jev.example.com", "model": "qwen", "api_key": ""])
        try assertLoadThrowsRemoteConfig("api_key")
        try writeConfig(["base_url": "https://jev.example.com", "model": "qwen"])
        try assertLoadThrowsRemoteConfig("api_key")
    }

    func testLoadRejectsAnAPIKeyContainingWhitespace() throws {
        try writeConfig([
            "base_url": "https://jev.example.com", "model": "qwen", "api_key": "sk-with a space",
        ])
        try assertLoadThrowsRemoteConfig("api_key")
    }

    func testLoadRejectsAnOversizeAPIKey() throws {
        try writeConfig([
            "base_url": "https://jev.example.com", "model": "qwen",
            "api_key": String(repeating: "k", count: 513),
        ])
        try assertLoadThrowsRemoteConfig("api_key")
    }

    // MARK: - Loader — file trust boundary

    func testLoadRejectsAGroupOrOtherReadableFile() throws {
        try writeConfig(
            ["base_url": "https://jev.example.com", "model": "qwen", "api_key": Self.distinctiveKey], mode: 0o640
        )
        try assertLoadThrowsRemoteConfig("group or other")
    }

    func testLoadRejectsASymlink() throws {
        try writeConfig(["base_url": "https://jev.example.com", "model": "qwen", "api_key": Self.distinctiveKey])
        let target = directory.appendingPathComponent("real-remote-backend.json")
        try FileManager.default.moveItem(at: configFile, to: target)
        try FileManager.default.createSymbolicLink(at: configFile, withDestinationURL: target)
        try assertLoadThrowsRemoteConfig("symlink")
    }

    /// A directory at the config path opens successfully (unlike a missing path or a symlink) but must still be
    /// refused once `fstat` shows it is not a regular file — with a message that does not misname it a symlink.
    func testLoadRejectsADirectoryAtTheConfigPath() throws {
        try FileManager.default.createDirectory(at: configFile, withIntermediateDirectories: true)
        try assertLoadThrowsRemoteConfig("must be a regular file")
        XCTAssertThrowsError(try DecisionRemoteBackendConfigLoader.load(from: configFile)) { error in
            guard case let .remoteConfig(message) = error as? DecisionModelError else {
                return XCTFail("expected .remoteConfig, got \(error)")
            }
            XCTAssertFalse(message.contains("symlink"), message)
        }
    }

    /// An `open` failure other than "no such file" (here, a non-directory path component) must not be reported as
    /// though the config file were simply absent.
    func testLoadRejectsAConfigPathWithANonDirectoryPathComponent() throws {
        let blocker = directory.appendingPathComponent("not-a-directory")
        try Data().write(to: blocker)
        let path = blocker.appendingPathComponent("remote-backend.json")

        XCTAssertThrowsError(try DecisionRemoteBackendConfigLoader.load(from: path)) { error in
            guard case let .remoteConfig(message) = error as? DecisionModelError else {
                return XCTFail("expected .remoteConfig, got \(error)")
            }
            XCTAssertTrue(message.contains("could not be opened"), message)
            XCTAssertFalse(message.contains("no remote-backend config file"), message)
        }
    }

    func testLoadRejectsAnOversizeFile() throws {
        let oversized = String(repeating: "x", count: 17 * 1024)
        try oversized.write(to: configFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configFile.path)
        try assertLoadThrowsRemoteConfig("size cap")
    }

    func testLoadRejectsWhenNoFileExists() throws {
        try assertLoadThrowsRemoteConfig("no remote-backend config file")
    }

    func testLoadRejectsAFileThatIsNotAJSONObject() throws {
        try "[]".write(to: configFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configFile.path)
        try assertLoadThrowsRemoteConfig("JSON object")
    }

    // MARK: - DecisionBackendSelection.resolve

    func testResolveDefaultsToLlamaWhenBackendKeyIsAbsentOrBlank() throws {
        for environment: [String: String] in [[:], [DecisionBackendSelection.environmentKey: ""], [DecisionBackendSelection.environmentKey: "  "]] {
            XCTAssertEqual(try DecisionBackendSelection.resolve(environment: environment), .llama)
        }
    }

    func testResolveAcceptsLlamaCaseInsensitively() throws {
        XCTAssertEqual(
            try DecisionBackendSelection.resolve(environment: [DecisionBackendSelection.environmentKey: "LLAMA"]),
            .llama
        )
    }

    func testResolveAcceptsRemoteWhenNoLlamaURLIsSet() throws {
        XCTAssertEqual(
            try DecisionBackendSelection.resolve(environment: [DecisionBackendSelection.environmentKey: "remote"]),
            .remote
        )
    }

    func testResolveThrowsWhenRemoteIsCombinedWithANonEmptyLlamaURL() {
        XCTAssertThrowsError(
            try DecisionBackendSelection.resolve(environment: [
                DecisionBackendSelection.environmentKey: "remote",
                DecisionModelEndpoint.environmentKey: "http://127.0.0.1:39501",
            ])
        ) { error in
            guard case let .remoteConfig(message) = error as? DecisionModelError else {
                return XCTFail("expected .remoteConfig, got \(error)")
            }
            XCTAssertTrue(message.contains(DecisionBackendSelection.environmentKey), message)
            XCTAssertTrue(message.contains(DecisionModelEndpoint.environmentKey), message)
        }
    }

    func testResolveThrowsForAnUnknownBackendValue() {
        XCTAssertThrowsError(
            try DecisionBackendSelection.resolve(environment: [DecisionBackendSelection.environmentKey: "bogus"])
        ) { error in
            guard case .remoteConfig = error as? DecisionModelError else {
                return XCTFail("expected .remoteConfig, got \(error)")
            }
        }
    }

    // MARK: - ToolDefinitions.listed — remote gate

    func testToolDefinitionsListedIncludesDecideNextActionWhenBackendIsRemote() {
        let listed = ToolDefinitions.listed(environment: [DecisionBackendSelection.environmentKey: "remote"])
        XCTAssertTrue(listed.contains { $0.name == "decide_next_action" })
    }

    func testToolDefinitionsListedExcludesDecideNextActionForAnUnknownBackend() {
        let listed = ToolDefinitions.listed(environment: [DecisionBackendSelection.environmentKey: "bogus"])
        XCTAssertFalse(listed.contains { $0.name == "decide_next_action" })
    }
}
