import Foundation
import XCTest
@testable import OpenComputerUseKit

/// Pins the normative endpoint/transport/parser/client contract in
/// `plans/260923-0939-notarize-translate-decision-model/decision-model/phase-04-swift-prompt-readout-client.md`,
/// with the loopback amendment from that plan's "Amendments from plan validation" (2026-09-23 10:30, binding):
/// only literal `127.0.0.1` and `[::1]` hosts are accepted; `localhost` is rejected because llama-server binds
/// IPv4 only. Written before `DecisionModelClient.swift` exists; every assertion here must fail (compile error or
/// runtime assertion) until that file is implemented to this exact contract.
final class DecisionModelClientTests: XCTestCase {

    // MARK: - Fixture loading

    /// Loads `scripts/decision-model/fixtures/readout-pin.json` (phase 01) relative to the repo root, found by
    /// walking up from this test file's own path: filename, `OpenComputerUseKitTests`, `Tests`, `OpenComputerUseKit`,
    /// `packages` — 5 `deleteLastPathComponent()` calls land on the repo root.
    private static func loadPin() -> [String: Any] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        url.appendPathComponent("scripts/decision-model/fixtures/readout-pin.json")
        let data = try! Data(contentsOf: url)
        return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    private static func trimmedLabel(_ token: String) -> String {
        token.hasPrefix(" ") ? String(token.dropFirst()) : token
    }

    // MARK: - DecisionModelEndpoint.fromEnvironment

    func testEndpointAcceptsLiteralLoopbackHostsAndNormalizesToCompletionURL() throws {
        for input in ["http://127.0.0.1:39501", "http://127.0.0.1:39501/", "http://[::1]:39501"] {
            let endpoint = try XCTUnwrap(
                try DecisionModelEndpoint.fromEnvironment([DecisionModelEndpoint.environmentKey: input]), input
            )
            XCTAssertTrue(endpoint.completionURL.absoluteString.hasSuffix(":39501/completion"), input)
        }
    }

    func testEndpointIsNilWhenKeyAbsentOrBlank() throws {
        XCTAssertNil(try DecisionModelEndpoint.fromEnvironment([:]))
        XCTAssertNil(try DecisionModelEndpoint.fromEnvironment([DecisionModelEndpoint.environmentKey: ""]))
        XCTAssertNil(try DecisionModelEndpoint.fromEnvironment([DecisionModelEndpoint.environmentKey: "   "]))
    }

    func testEndpointThrowsUnsupportedSchemeForHTTPS() {
        XCTAssertThrowsError(
            try DecisionModelEndpoint.fromEnvironment([DecisionModelEndpoint.environmentKey: "https://127.0.0.1:1"])
        ) { error in
            guard case .unsupportedScheme = error as? DecisionModelError else {
                return XCTFail("expected .unsupportedScheme, got \(error)")
            }
        }
    }

    /// Amendment (plan validation, 2026-09-23, binding): llama-server binds IPv4 only, so a hostname that commonly
    /// resolves to loopback is still rejected — only the literal IP forms are trusted.
    func testEndpointRejectsLocalhostHostnameAsNonLoopback() {
        for input in ["http://localhost:39501", "http://LOCALHOST:39501"] {
            XCTAssertThrowsError(
                try DecisionModelEndpoint.fromEnvironment([DecisionModelEndpoint.environmentKey: input])
            ) { error in
                guard case .nonLoopbackHost = error as? DecisionModelError else {
                    return XCTFail("expected .nonLoopbackHost for \(input), got \(error)")
                }
            }
        }
    }

    func testEndpointThrowsForNonLoopbackOrMalformedInputs() {
        let inputs = [
            "ftp://127.0.0.1:1",
            "127.0.0.1:39501",
            "http://10.0.0.1:1",
            "http://127.0.0.2:1",
            "http://0.0.0.0:1",
            "http://127.1:1",
            "http://2130706433:1",
            "http://[::ffff:127.0.0.1]:1",
            "http://127.0.0.1.evil.com:1",
            "http://localhost.evil.com:1",
            "http://user:pw@127.0.0.1:1",
            "http://127.0.0.1:39501/v1",
            "http://127.0.0.1:39501?x=1",
            "http://127.0.0.1",
            "http://127.0.0.1:0",
        ]
        for input in inputs {
            XCTAssertThrowsError(
                try DecisionModelEndpoint.fromEnvironment([DecisionModelEndpoint.environmentKey: input]), input
            )
        }
    }

    // MARK: - DecisionReadoutParser.parse — pinned fixture

    func testParsePinnedResponseSucceedsAndMatchesFixtureGeneratedLabels() throws {
        let pin = Self.loadPin()
        let response = pin["response"] as! [String: Any]
        let responseData = try JSONSerialization.data(withJSONObject: response)
        let operationLabels = pin["operationLabels"] as! [String]
        let targetLabels = pin["targetLabels"] as! [String]

        let readout = try DecisionReadoutParser.parse(
            completionResponse: responseData, operationLabels: operationLabels, targetLabels: targetLabels
        )

        XCTAssertEqual(readout.operation.probabilities.reduce(0, +), 1, accuracy: 1e-9)
        XCTAssertEqual(readout.target.probabilities.reduce(0, +), 1, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(readout.operation.margin, 0)
        XCTAssertLessThanOrEqual(readout.operation.margin, 1)
        XCTAssertGreaterThanOrEqual(readout.target.margin, 0)
        XCTAssertLessThanOrEqual(readout.target.margin, 1)

        let entries = response["completion_probabilities"] as! [[String: Any]]
        let expectedOperationLabel = Self.trimmedLabel(entries[0]["token"] as! String)
        XCTAssertEqual(readout.operation.chosenLabel, expectedOperationLabel)

        // responseShapeNote (phase 01 fixture): completion_probabilities can include a trailing forced-stop entry
        // with an empty token after the grammar's root production is fully matched. The target head is the LAST
        // entry whose token is one of the target labels — not the raw last array element (which may be that
        // trailing stop marker).
        let expectedTargetLabel = entries.reversed().compactMap { entry -> String? in
            guard let token = entry["token"] as? String else { return nil }
            let trimmed = Self.trimmedLabel(token)
            return targetLabels.contains(trimmed) ? trimmed : nil
        }.first
        XCTAssertEqual(readout.target.chosenLabel, expectedTargetLabel)
    }

    // MARK: - DecisionReadoutParser.parse — synthetic renormalization

    func testParseSyntheticTargetDistributionRenormalizesOverPresentLabelsOnly() throws {
        let entries: [[String: Any]] = [
            ["token": " Z", "logprob": -0.01, "top_logprobs": [["token": " Z", "logprob": -0.01]]],
            ["token": " A", "logprob": -0.1, "top_logprobs": [
                ["token": " A", "logprob": -0.1],
                ["token": " B", "logprob": -2.4],
                ["token": "Save", "logprob": -1.0],
            ]],
        ]
        let data = try JSONSerialization.data(withJSONObject: ["completion_probabilities": entries])

        let readout = try DecisionReadoutParser.parse(
            completionResponse: data, operationLabels: ["Z"], targetLabels: ["A", "B", "C"]
        )

        XCTAssertEqual(readout.target.labels, ["A", "B", "C"])
        XCTAssertEqual(readout.target.chosenLabel, "A")
        XCTAssertEqual(readout.target.missingLabels, ["C"])
        XCTAssertEqual(readout.target.probabilities[0], 0.9089, accuracy: 1e-3)
        XCTAssertEqual(readout.target.probabilities[1], 0.0911, accuracy: 1e-3)
        XCTAssertEqual(readout.target.probabilities[2], 0, accuracy: 1e-9)
        XCTAssertEqual(readout.target.margin, 0.8178, accuracy: 1e-3)
    }

    // MARK: - DecisionReadoutParser.parse — error cases

    func testParseThrowsReadoutForFewerThanTwoEntries() {
        let data = try! JSONSerialization.data(withJSONObject: [
            "completion_probabilities": [
                ["token": " A", "logprob": -0.1, "top_logprobs": [["token": " A", "logprob": -0.1]]],
            ],
        ])
        assertParseThrowsReadout(data, operationLabels: ["A"], targetLabels: ["A"])
    }

    func testParseThrowsReadoutWhenAnEntryCarriesPostSamplingTopProbs() {
        let entries: [[String: Any]] = [
            ["token": " A", "logprob": -0.1, "top_logprobs": [["token": " A", "logprob": -0.1]]],
            ["token": " A", "prob": 0.9, "top_probs": [["token": " A", "prob": 0.9]]],
        ]
        let data = try! JSONSerialization.data(withJSONObject: ["completion_probabilities": entries])
        assertParseThrowsReadout(data, operationLabels: ["A"], targetLabels: ["A"])
    }

    func testParseThrowsReadoutWhenTargetTokenHasNoLeadingSpace() {
        let entries: [[String: Any]] = [
            ["token": " A", "logprob": -0.1, "top_logprobs": [["token": " A", "logprob": -0.1]]],
            ["token": "A", "logprob": -0.1, "top_logprobs": [["token": "A", "logprob": -0.1]]],
        ]
        let data = try! JSONSerialization.data(withJSONObject: ["completion_probabilities": entries])
        assertParseThrowsReadout(data, operationLabels: ["A"], targetLabels: ["A"])
    }

    func testParseThrowsReadoutWhenGeneratedLabelIsNotTheArgmax() {
        let entries: [[String: Any]] = [
            ["token": " A", "logprob": -0.1, "top_logprobs": [["token": " A", "logprob": -0.1]]],
            ["token": " B", "logprob": -2.0, "top_logprobs": [
                ["token": " A", "logprob": -0.1],
                ["token": " B", "logprob": -2.0],
            ]],
        ]
        let data = try! JSONSerialization.data(withJSONObject: ["completion_probabilities": entries])
        assertParseThrowsReadout(data, operationLabels: ["A"], targetLabels: ["A", "B"])
    }

    private func assertParseThrowsReadout(
        _ data: Data, operationLabels: [String], targetLabels: [String], file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try DecisionReadoutParser.parse(
                completionResponse: data, operationLabels: operationLabels, targetLabels: targetLabels
            ), file: file, line: line
        ) { error in
            guard case .readout = error as? DecisionModelError else {
                return XCTFail("expected .readout, got \(error)", file: file, line: line)
            }
        }
    }

    // MARK: - URLSessionDecisionModelTransport — off-main helper

    /// Runs `body` on a background queue and blocks the caller until it finishes, so tests can exercise the
    /// transport's main-thread guard by calling `postJSON` directly on the XCTest main thread elsewhere.
    /// **Deliberately uses `DispatchQueue.global().async` + a semaphore, not `.sync`:** GCD runs a `sync` block on
    /// the calling thread whenever it can, so from the XCTest main thread the block would still see
    /// `Thread.isMainThread == true` and hit the transport's own main-thread guard.
    private func offMain<T>(_ body: @escaping () throws -> T) throws -> T {
        let box = OffMainResultBox<T>()
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            box.result = Result { try body() }
            semaphore.signal()
        }
        semaphore.wait()
        return try box.result!.get()
    }

    // MARK: - URLSessionDecisionModelTransport — URLProtocol stub

    private static let stubCompletionURL = URL(string: "http://127.0.0.1:39501/completion")!

    func testPostJSONRefusesRedirectAndRecordsNoRequestToTheRedirectTarget() throws {
        let redirectTarget = URL(string: "http://127.0.0.1:39999/redirected")!
        StubURLProtocol.configure(.init(redirectTo: redirectTarget))
        let transport = URLSessionDecisionModelTransport(protocolClasses: [StubURLProtocol.self])

        XCTAssertThrowsError(
            try offMain {
                try transport.postJSON(
                    to: Self.stubCompletionURL, body: Data("{}".utf8), timeout: 2, maxResponseBytes: 1024
                )
            }
        ) { error in
            XCTAssertEqual(error as? DecisionModelError, .redirectRefused)
        }
        XCTAssertTrue(StubURLProtocol.recordedRequests().allSatisfy { $0.url != redirectTarget })
    }

    func testPostJSONRejectsResponseLargerThanMaxResponseBytes() throws {
        let oversized = Data(repeating: 0x41, count: 2 * 1024 * 1024)
        StubURLProtocol.configure(.init(body: oversized))
        let transport = URLSessionDecisionModelTransport(protocolClasses: [StubURLProtocol.self])

        XCTAssertThrowsError(
            try offMain {
                try transport.postJSON(
                    to: Self.stubCompletionURL, body: Data("{}".utf8), timeout: 2, maxResponseBytes: 1_048_576
                )
            }
        ) { error in
            XCTAssertEqual(error as? DecisionModelError, .responseTooLarge(limit: 1_048_576))
        }
    }

    func testPostJSONThrowsHTTPStatusOnServerError() throws {
        StubURLProtocol.configure(.init(statusCode: 500))
        let transport = URLSessionDecisionModelTransport(protocolClasses: [StubURLProtocol.self])

        XCTAssertThrowsError(
            try offMain {
                try transport.postJSON(
                    to: Self.stubCompletionURL, body: Data("{}".utf8), timeout: 2, maxResponseBytes: 1024
                )
            }
        ) { error in
            XCTAssertEqual(error as? DecisionModelError, .httpStatus(500))
        }
    }

    func testPostJSONTimesOutWhenServerNeverRespondsAndReturnsWellUnderTwoSeconds() throws {
        StubURLProtocol.configure(.init(neverRespond: true))
        let transport = URLSessionDecisionModelTransport(protocolClasses: [StubURLProtocol.self])
        let start = Date()

        XCTAssertThrowsError(
            try offMain {
                try transport.postJSON(
                    to: Self.stubCompletionURL, body: Data("{}".utf8), timeout: 0.5, maxResponseBytes: 1024
                )
            }
        ) { error in
            XCTAssertEqual(error as? DecisionModelError, .timeout)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }

    func testPostJSONOnMainThreadThrowsTransportError() {
        XCTAssertTrue(Thread.isMainThread)
        StubURLProtocol.configure(.init())
        let transport = URLSessionDecisionModelTransport(protocolClasses: [StubURLProtocol.self])

        XCTAssertThrowsError(
            try transport.postJSON(to: Self.stubCompletionURL, body: Data("{}".utf8), timeout: 2, maxResponseBytes: 1024)
        ) { error in
            guard case .transport = error as? DecisionModelError else {
                return XCTFail("expected .transport, got \(error)")
            }
        }
    }

    func testPostJSONSendsPostWithJSONContentTypeAndTheExactRequestBody() throws {
        StubURLProtocol.configure(.init(body: Data(#"{"ok":true}"#.utf8)))
        let transport = URLSessionDecisionModelTransport(protocolClasses: [StubURLProtocol.self])
        let requestBody = Data(#"{"a":1}"#.utf8)

        _ = try offMain {
            try transport.postJSON(to: Self.stubCompletionURL, body: requestBody, timeout: 2, maxResponseBytes: 1024)
        }

        let recorded = try XCTUnwrap(StubURLProtocol.recordedRequests().last)
        XCTAssertEqual(recorded.httpMethod, "POST")
        XCTAssertEqual(recorded.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(recorded.resolvedHTTPBody, requestBody)
    }

    // MARK: - DecisionModelClient — StubTransport

    func testClientReadoutPostsOnceWithPageLabelGrammarAndMatchesParserResult() throws {
        let pin = Self.loadPin()
        let responseData = try JSONSerialization.data(withJSONObject: pin["response"] as Any)
        let page = DecisionCandidatePage(
            labels: ["A", "B", "C"],
            candidates: [
                DecisionCandidate(elementIndex: 1, rowText: "menu item File", isFocused: false),
                DecisionCandidate(elementIndex: 2, rowText: "text field Untitled", isFocused: false),
                DecisionCandidate(elementIndex: 3, rowText: "button Save", isFocused: false),
            ]
        )
        let stub = StubTransport(responseData: responseData)
        let endpoint = try XCTUnwrap(
            try DecisionModelEndpoint.fromEnvironment([DecisionModelEndpoint.environmentKey: "http://127.0.0.1:39501"])
        )
        let client = DecisionModelClient(endpoint: endpoint, transport: stub)

        let readout = try client.readout(goal: "Save the document", appName: "Sample", page: page)

        XCTAssertEqual(stub.requests.count, 1)
        let recorded = try XCTUnwrap(stub.requests.first)
        XCTAssertTrue(recorded.url.absoluteString.hasSuffix("/completion"))

        let bodyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: recorded.body) as? [String: Any])
        let grammar = try XCTUnwrap(bodyObject["grammar"] as? String)
        XCTAssertEqual(grammar, DecisionPromptBuilder.grammar(targetLabels: page.labels))

        let expectedReadout = try DecisionReadoutParser.parse(
            completionResponse: responseData,
            operationLabels: DecisionOperation.allCases.map(\.label),
            targetLabels: page.labels
        )
        XCTAssertEqual(readout, expectedReadout)
    }
}

// MARK: - Test doubles

/// Storage for `offMain`'s background result, at file scope because Swift does not allow a type to be nested
/// inside a generic function.
private final class OffMainResultBox<T>: @unchecked Sendable {
    var result: Result<T, Error>?
}

/// Records every `(url, body)` pair `postJSON` is called with and always returns `responseData`.
private final class StubTransport: DecisionModelTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [(url: URL, body: Data)] = []
    private let responseData: Data

    init(responseData: Data) { self.responseData = responseData }

    func postJSON(to url: URL, body: Data, timeout: TimeInterval, maxResponseBytes: Int) throws -> Data {
        lock.lock()
        recorded.append((url, body))
        lock.unlock()
        return responseData
    }

    var requests: [(url: URL, body: Data)] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }
}

/// A minimal, lock-protected `URLProtocol` stub for exercising `URLSessionDecisionModelTransport` without any real
/// socket or DNS lookup (forbidden by the phase file). Configure with `configure(_:)` before each call, then read
/// `recordedRequests()` afterward.
private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Configuration {
        var statusCode: Int = 200
        var headers: [String: String] = ["Content-Type": "application/json"]
        var body: Data = Data("{}".utf8)
        var redirectTo: URL?
        var neverRespond: Bool = false
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var configuration = Configuration()
    nonisolated(unsafe) private static var requests: [URLRequest] = []

    static func configure(_ configuration: Configuration) {
        lock.lock()
        Self.configuration = configuration
        Self.requests = []
        lock.unlock()
    }

    static func recordedRequests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let configuration = Self.configuration
        Self.requests.append(request)
        Self.lock.unlock()

        if configuration.neverRespond { return }

        if let redirectTo = configuration.redirectTo {
            let redirectResponse = HTTPURLResponse(
                url: request.url!, statusCode: 302, httpVersion: "HTTP/1.1",
                headerFields: ["Location": redirectTo.absoluteString]
            )!
            client?.urlProtocol(
                self, wasRedirectedTo: URLRequest(url: redirectTo), redirectResponse: redirectResponse
            )
            return
        }

        let response = HTTPURLResponse(
            url: request.url!, statusCode: configuration.statusCode, httpVersion: "HTTP/1.1",
            headerFields: configuration.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: configuration.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

extension URLRequest {
    /// `httpBody` is sometimes moved into `httpBodyStream` by `URLSession` before reaching `URLProtocol`; this
    /// reads either form so body assertions do not depend on which one URLSession chose.
    fileprivate var resolvedHTTPBody: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
