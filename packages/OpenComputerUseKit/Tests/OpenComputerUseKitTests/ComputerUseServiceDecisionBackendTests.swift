import Foundation
import XCTest
@testable import OpenComputerUseKit

/// Covers the backend-selection and provider-construction seam of `ComputerUseService.decideNextAction`:
/// `resolveValidatedDecisionBackend` (environment -> `ValidatedDecisionBackend`, with error mapping) and
/// `buildDecisionProvider` (`ValidatedDecisionBackend` -> the `DecisionReadoutProviding` instance, page size, max
/// pages, and sidecar-port-to-verify). `decideNextAction` itself also calls `refreshSnapshot`, which needs a live
/// AX-resolved app; that is exercised by the smoke suite, not here. These two functions are the part that decides
/// which backend answers a call and how it is configured, so this is the seam worth testing without that
/// dependency.
final class ComputerUseServiceDecisionBackendTests: XCTestCase {
    private var directory: URL!
    private var configFile: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocu-decision-backend-seam-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        configFile = directory.appendingPathComponent("remote-backend.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func writeValidRemoteConfig() throws {
        let object: [String: Any] = [
            "base_url": "https://jev.example.com", "model": "qwen-jev-test", "api_key": "sk-jev-seam-test",
        ]
        try JSONSerialization.data(withJSONObject: object).write(to: configFile)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configFile.path)
    }

    // MARK: - resolveValidatedDecisionBackend

    func testResolveValidatedDecisionBackendMapsAnAbsentLlamaEndpointToStateUnavailable() {
        XCTAssertThrowsError(
            try ComputerUseService.resolveValidatedDecisionBackend(environment: [:], remoteBackendConfigURL: configFile)
        ) { error in
            guard case .stateUnavailable = error as? ComputerUseError else {
                return XCTFail("expected .stateUnavailable, got \(error)")
            }
        }
    }

    func testResolveValidatedDecisionBackendMapsAMalformedLlamaEndpointToInvalidArguments() {
        let environment = [DecisionModelEndpoint.environmentKey: "not a url"]
        XCTAssertThrowsError(
            try ComputerUseService.resolveValidatedDecisionBackend(environment: environment, remoteBackendConfigURL: configFile)
        ) { error in
            guard case .invalidArguments = error as? ComputerUseError else {
                return XCTFail("expected .invalidArguments, got \(error)")
            }
        }
    }

    func testResolveValidatedDecisionBackendReturnsLlamaWhenAWellFormedLoopbackURLIsSet() throws {
        let environment = [DecisionModelEndpoint.environmentKey: "http://127.0.0.1:39501"]
        let validated = try ComputerUseService.resolveValidatedDecisionBackend(
            environment: environment, remoteBackendConfigURL: configFile
        )
        guard case .llama(let endpoint) = validated else { return XCTFail("expected .llama, got \(validated)") }
        XCTAssertEqual(endpoint.port, 39501)
    }

    /// A missing remote config file maps to `.invalidArguments`, not `.stateUnavailable` — remote has no
    /// "absent" case distinct from "invalid", since the config file's mere absence is itself an invalid-arguments
    /// error (see the corrected history note).
    func testResolveValidatedDecisionBackendMapsAMissingRemoteConfigFileToInvalidArguments() {
        let environment = [DecisionBackendSelection.environmentKey: "remote"]
        XCTAssertThrowsError(
            try ComputerUseService.resolveValidatedDecisionBackend(environment: environment, remoteBackendConfigURL: configFile)
        ) { error in
            guard case .invalidArguments = error as? ComputerUseError else {
                return XCTFail("expected .invalidArguments, got \(error)")
            }
        }
    }

    func testResolveValidatedDecisionBackendLoadsRemoteConfigFromTheInjectedURL() throws {
        try writeValidRemoteConfig()
        let environment = [DecisionBackendSelection.environmentKey: "remote"]
        let validated = try ComputerUseService.resolveValidatedDecisionBackend(
            environment: environment, remoteBackendConfigURL: configFile
        )
        guard case .remote(let config) = validated else { return XCTFail("expected .remote, got \(validated)") }
        XCTAssertEqual(config.baseURL, URL(string: "https://jev.example.com"))
        XCTAssertEqual(config.model, "qwen-jev-test")
    }

    // MARK: - buildDecisionProvider

    func testBuildDecisionProviderForLlamaPassesThroughDefaultPageSizeMaxPagesAndTheSidecarPort() {
        let endpoint = try! DecisionModelEndpoint.fromEnvironment(
            [DecisionModelEndpoint.environmentKey: "http://127.0.0.1:39777"]
        )!
        let built = ComputerUseService.buildDecisionProvider(
            validated: .llama(endpoint), transport: FailingTransport(), deadline: Date()
        )
        XCTAssertTrue(built.provider is DecisionModelClient)
        XCTAssertEqual(built.pageSize, DecisionCandidateBuilder.pageSize)
        XCTAssertEqual(built.maxPages, DecisionCandidateBuilder.defaultMaxPages)
        XCTAssertEqual(built.sidecarPortToVerify, 39777)
    }

    /// The remote branch wires `pageSize: DecisionJevClient.pageSize` (26) and `maxPages: DecisionJevClient.maxPages`
    /// (2), not the loopback defaults; this pins that wiring directly at the seam that builds the provider, and
    /// that remote never reports a sidecar port to verify (it has no equivalent squatting risk).
    func testBuildDecisionProviderForRemotePassesThroughJevPageSizeMaxPagesAndNoSidecarPort() throws {
        try writeValidRemoteConfig()
        let config = try DecisionRemoteBackendConfigLoader.load(from: configFile)
        let built = ComputerUseService.buildDecisionProvider(
            validated: .remote(config), transport: FailingTransport(), deadline: Date()
        )
        XCTAssertTrue(built.provider is DecisionJevClient)
        XCTAssertEqual(built.pageSize, DecisionJevClient.pageSize)
        XCTAssertEqual(built.maxPages, DecisionJevClient.maxPages)
        XCTAssertNil(built.sidecarPortToVerify)
    }
}

/// A transport that fails any request it is asked to make; `buildDecisionProvider` never sends a request itself
/// (it only constructs the client), so this proves that by construction rather than by mocking a real response.
private struct FailingTransport: DecisionModelTransport {
    func postJSON(
        to url: URL, body: Data, timeout: TimeInterval, maxResponseBytes: Int, headers: [String: String]
    ) throws -> Data {
        throw DecisionModelError.transport("FailingTransport must never be called by buildDecisionProvider itself")
    }
}
