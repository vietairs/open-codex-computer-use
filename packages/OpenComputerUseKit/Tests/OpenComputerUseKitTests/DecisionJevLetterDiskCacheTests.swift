import CryptoKit
import Foundation
import XCTest
@testable import OpenComputerUseKit

/// Covers the on-disk jev letter table: persisted per (base_url, model) in an owner-only directory, re-validated on
/// every load, resumable after a partial resolution, and off unless a directory is passed in. Every test uses its own
/// temp directory and a fake transport; none touches the production directory or opens a socket.
final class DecisionJevLetterDiskCacheTests: XCTestCase {
    private static let apiKey = "sk-jev-test-canary"
    private static let farFutureDeadline = Date().addingTimeInterval(3600)

    private var root: URL!
    private var cacheDirectory: URL { root.appendingPathComponent("jev-letters") }

    override func setUp() {
        super.setUp()
        DecisionJevLetterResolver.resetCacheForTesting()
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        // The tests may leave a 0700 directory, a 0644 file or a symlink behind; make it removable first.
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cacheDirectory.path)
        try? FileManager.default.removeItem(at: root)
        DecisionJevLetterResolver.resetCacheForTesting()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeConfig(host: String = "jev.example.com", model: String = "qwen-jev-test") -> DecisionRemoteBackendConfig {
        DecisionRemoteBackendConfig(baseURL: URL(string: "https://\(host)")!, model: model, apiKey: Self.apiKey)
    }

    private func makeCache(now: @escaping @Sendable () -> Date = Date.init) -> DecisionJevLetterDiskCache {
        DecisionJevLetterDiskCache(directory: cacheDirectory, now: now)
    }

    private func makeResolver(
        config: DecisionRemoteBackendConfig? = nil, transport: DecisionModelTransport,
        cache: DecisionJevLetterDiskCache? = nil
    ) -> DecisionJevLetterResolver {
        DecisionJevLetterResolver(
            config: config ?? makeConfig(), transport: transport, deadline: Self.farFutureDeadline,
            diskCache: cache ?? makeCache()
        )
    }

    /// A well-behaved tokenizer: the sample prompt is the given base ids, and every letter A-Z tokenizes to exactly
    /// one new token whose id and `token_str` are derived from the letter.
    private static func tokenizer(baseIDs: [Int] = [1, 2, 3, 4, 5]) -> (String) -> [String: Any] {
        let baseStrs = baseIDs.map { "b\($0)" }
        return { prompt in
            let sample = DecisionJevPromptBuilder.samplePrompt
            guard prompt != sample else { return ["tokens": baseIDs, "token_strs": baseStrs] }
            let letter = String(prompt.dropFirst(sample.count))
            let id = 100 + Int(letter.unicodeScalars.first!.value)
            return ["tokens": baseIDs + [id], "token_strs": baseStrs + [" " + letter]]
        }
    }

    private func fileURL(config: DecisionRemoteBackendConfig? = nil) -> URL {
        let config = config ?? makeConfig()
        return makeCache().fileURL(baseURL: config.baseURL, model: config.model)
    }

    private func permissions(of url: URL) throws -> Int {
        let value = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        return try XCTUnwrap(value).intValue
    }

    private func readJSON(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func writeJSON(_ object: [String: Any], to url: URL) throws {
        try JSONSerialization.data(withJSONObject: object).write(to: url)
    }

    /// Resolves once against a healthy transport so a valid entry file exists, then clears the in-memory cache so the
    /// next resolver has to look at the disk.
    private func seedValidFile(config: DecisionRemoteBackendConfig? = nil) throws {
        let transport = FakeTokenizeTransport(tokenizer: Self.tokenizer())
        _ = try makeResolver(config: config, transport: transport).resolve()
        XCTAssertEqual(transport.tokenizeCalls, 27)
        DecisionJevLetterResolver.resetCacheForTesting()
    }

    /// Asserts the resolver recovers over the network, and leaves a fresh 0600 regular file that loads.
    private func assertRecoversOverNetworkAndRewrites(
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let transport = FakeTokenizeTransport(tokenizer: Self.tokenizer())
        let resolved = try makeResolver(transport: transport).resolve()
        XCTAssertEqual(resolved.count, 26, file: file, line: line)
        XCTAssertEqual(transport.tokenizeCalls, 27, "an unusable entry is a miss, never an error", file: file, line: line)
        let url = fileURL()
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual(attributes[.type] as? FileAttributeType, .typeRegular, file: file, line: line)
        XCTAssertEqual(try permissions(of: url), 0o600, file: file, line: line)
        XCTAssertNotNil(
            makeCache().load(
                baseURL: makeConfig().baseURL, model: makeConfig().model,
                samplePromptSHA256: DecisionJevLetterResolver.samplePromptSHA256
            ), "the file must be rewritten with a valid entry", file: file, line: line
        )
    }

    // MARK: - Miss then write

    func testMissResolvesOverTheNetworkThenWritesAnOwnerOnlyFile() throws {
        let transport = FakeTokenizeTransport(tokenizer: Self.tokenizer())
        let resolved = try makeResolver(transport: transport).resolve()

        XCTAssertEqual(resolved.count, 26)
        XCTAssertEqual(transport.tokenizeCalls, 27)
        let url = fileURL()
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try permissions(of: url), 0o600)
        XCTAssertEqual(try permissions(of: cacheDirectory), 0o700)

        let object = try readJSON(url)
        XCTAssertEqual(object["version"] as? Int, DecisionJevLetterDiskCache.formatVersion)
        XCTAssertEqual(object["base_url"] as? String, "https://jev.example.com")
        XCTAssertEqual(object["model"] as? String, "qwen-jev-test")
        XCTAssertEqual(object["sample_prompt_sha256"] as? String, DecisionJevLetterResolver.samplePromptSHA256)
        XCTAssertNotNil(object["resolved_at"], "entries carry resolved_at")
        XCTAssertEqual(object["base_ids"] as? [Int], [1, 2, 3, 4, 5])
        let letters = try XCTUnwrap(object["letters"] as? [String: [String: Any]])
        XCTAssertEqual(letters.count, 26)
        XCTAssertEqual(letters["A"]?["id"] as? Int, 165)
        XCTAssertEqual(letters["A"]?["token_str"] as? String, " A")

        let raw = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(raw.contains(Self.apiKey), "the api key must never reach the disk")
    }

    func testFileNameIsTheLowercaseHexSHA256OfTheBaseURLAndModelKey() {
        let config = makeConfig()
        let digest = SHA256.hash(data: Data("\(config.baseURL.absoluteString)|\(config.model)".utf8))
        let expected = digest.map { String(format: "%02x", $0) }.joined()

        let url = makeCache().fileURL(baseURL: config.baseURL, model: config.model)

        XCTAssertEqual(url.lastPathComponent, "\(expected).json")
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL.path, cacheDirectory.standardizedFileURL.path)
    }

    func testSamplePromptSHA256IsTheHexDigestOfTheSamplePrompt() {
        let digest = SHA256.hash(data: Data(DecisionJevPromptBuilder.samplePrompt.utf8))
        XCTAssertEqual(
            DecisionJevLetterResolver.samplePromptSHA256, digest.map { String(format: "%02x", $0) }.joined()
        )
    }

    // MARK: - Disk hit

    func testDiskHitReturnsIdenticalLettersWithZeroTokenizeRequests() throws {
        let first = FakeTokenizeTransport(tokenizer: Self.tokenizer())
        let original = try makeResolver(transport: first).resolve()
        XCTAssertEqual(first.tokenizeCalls, 27)
        DecisionJevLetterResolver.resetCacheForTesting()

        let second = FakeTokenizeTransport(tokenizer: Self.tokenizer())
        let reloaded = try makeResolver(transport: second).resolve()

        XCTAssertEqual(reloaded, original)
        XCTAssertEqual(second.tokenizeCalls, 0, "a valid disk entry must serve the whole table with no request")
    }

    // MARK: - Key change

    func testChangingOnlyTheModelIsAMiss() throws {
        try seedValidFile()

        let transport = FakeTokenizeTransport(tokenizer: Self.tokenizer())
        _ = try makeResolver(config: makeConfig(model: "another-model"), transport: transport).resolve()

        XCTAssertEqual(transport.tokenizeCalls, 27)
        XCTAssertNotEqual(fileURL(config: makeConfig(model: "another-model")), fileURL())
    }

    func testChangingOnlyTheBaseURLIsAMiss() throws {
        try seedValidFile()

        let transport = FakeTokenizeTransport(tokenizer: Self.tokenizer())
        _ = try makeResolver(config: makeConfig(host: "other.example.com"), transport: transport).resolve()

        XCTAssertEqual(transport.tokenizeCalls, 27)
        XCTAssertNotEqual(fileURL(config: makeConfig(host: "other.example.com")), fileURL())
    }

    // MARK: - Invalidation

    func testInvalidateCacheRemovesTheDiskFileAndTheMemoryEntry() throws {
        let transport = FakeTokenizeTransport(tokenizer: Self.tokenizer())
        let resolver = makeResolver(transport: transport)
        _ = try resolver.resolve()
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL().path))

        resolver.invalidateCache()

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL().path))
        _ = try resolver.resolve()
        XCTAssertEqual(transport.tokenizeCalls, 54, "memory must be evicted too, so the next resolve tokenizes again")
    }

    func testResetCacheForTestingStaysMemoryOnly() throws {
        try seedValidFile()
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL().path))
    }

    // MARK: - Corrupt or unsafe file is a miss, never an error

    func testGarbageJSONIsAMissAndIsRewritten() throws {
        try seedValidFile()
        try Data("{ this is not json".utf8).write(to: fileURL())
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL().path)

        try assertRecoversOverNetworkAndRewrites()
    }

    func testGroupOrOtherReadableFileIsAMissAndIsRewrittenOwnerOnly() throws {
        try seedValidFile()
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL().path)

        try assertRecoversOverNetworkAndRewrites()
    }

    func testSymlinkAtTheFilePathIsAMissAndIsReplacedByARegularFile() throws {
        try seedValidFile()
        let url = fileURL()
        let target = root.appendingPathComponent("elsewhere.json")
        try FileManager.default.moveItem(at: url, to: target)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)

        try assertRecoversOverNetworkAndRewrites()
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path), "the symlink target must be left alone")
    }

    func testUnknownVersionIsAMiss() throws {
        try seedValidFile()
        var object = try readJSON(fileURL())
        object["version"] = 2
        try writeJSON(object, to: fileURL())
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL().path)

        try assertRecoversOverNetworkAndRewrites()
    }

    func testMismatchedSamplePromptHashIsAMiss() throws {
        try seedValidFile()
        var object = try readJSON(fileURL())
        object["sample_prompt_sha256"] = String(repeating: "0", count: 64)
        try writeJSON(object, to: fileURL())
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL().path)

        try assertRecoversOverNetworkAndRewrites()
    }

    func testEntryOlderThanTheMaxAgeIsAMiss() throws {
        try seedValidFile()
        let later = Date().addingTimeInterval(DecisionJevLetterDiskCache.maxEntryAge + 60)
        let expiredView = makeCache(now: { later })
        XCTAssertNil(
            expiredView.load(
                baseURL: makeConfig().baseURL, model: makeConfig().model,
                samplePromptSHA256: DecisionJevLetterResolver.samplePromptSHA256
            )
        )

        let transport = FakeTokenizeTransport(tokenizer: Self.tokenizer())
        let resolved = try makeResolver(transport: transport, cache: expiredView).resolve()

        XCTAssertEqual(resolved.count, 26)
        XCTAssertEqual(transport.tokenizeCalls, 27, "an expired entry must be re-resolved")
    }

    func testEntryYoungerThanTheMaxAgeIsAHit() throws {
        try seedValidFile()
        let almost = Date().addingTimeInterval(DecisionJevLetterDiskCache.maxEntryAge - 3600)

        XCTAssertNotNil(
            makeCache(now: { almost }).load(
                baseURL: makeConfig().baseURL, model: makeConfig().model,
                samplePromptSHA256: DecisionJevLetterResolver.samplePromptSHA256
            )
        )
    }

    func testOversizeFileIsAMiss() throws {
        try seedValidFile()
        var object = try readJSON(fileURL())
        object["padding"] = String(repeating: "x", count: DecisionJevLetterDiskCache.maxFileBytes + 1024)
        try writeJSON(object, to: fileURL())
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL().path)

        try assertRecoversOverNetworkAndRewrites()
    }

    func testCompleteEntryWithCollapsedLettersIsAMiss() throws {
        try seedValidFile()
        var object = try readJSON(fileURL())
        var letters = try XCTUnwrap(object["letters"] as? [String: [String: Any]])
        letters["B"] = letters["A"]
        object["letters"] = letters
        try writeJSON(object, to: fileURL())
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL().path)

        try assertRecoversOverNetworkAndRewrites()
    }

    func testDirectoryWritableByOthersIsNeverWrittenTo() throws {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: cacheDirectory.path)

        let transport = FakeTokenizeTransport(tokenizer: Self.tokenizer())
        let resolved = try makeResolver(transport: transport).resolve()

        XCTAssertEqual(resolved.count, 26, "an unsafe directory must not fail the resolution")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL().path))
    }

    // MARK: - Progress persists

    func testProgressPersistsPerLetterAndAResumeTokenizesOnlyTheRemainingLetters() throws {
        let failing = FakeTokenizeTransport(tokenizer: Self.tokenizer(), failFromTokenizeCall: 12)
        XCTAssertThrowsError(try makeResolver(transport: failing).resolve())
        XCTAssertEqual(failing.tokenizeCalls, 12)

        let partial = try XCTUnwrap(
            makeCache().load(
                baseURL: makeConfig().baseURL, model: makeConfig().model,
                samplePromptSHA256: DecisionJevLetterResolver.samplePromptSHA256
            )
        )
        XCTAssertEqual(partial.baseTokenIDs, [1, 2, 3, 4, 5])
        XCTAssertEqual(partial.letters.count, 10, "the base prompt and 10 letters resolved before the failure")
        XCTAssertFalse(partial.isComplete)
        XCTAssertEqual(try permissions(of: fileURL()), 0o600)
        DecisionJevLetterResolver.resetCacheForTesting()

        let healthy = FakeTokenizeTransport(tokenizer: Self.tokenizer())
        let resolved = try makeResolver(transport: healthy).resolve()

        XCTAssertEqual(healthy.tokenizeCalls, 17, "1 base prompt + the 16 letters still missing")
        XCTAssertEqual(resolved.count, 26)
        let complete = try XCTUnwrap(
            makeCache().load(
                baseURL: makeConfig().baseURL, model: makeConfig().model,
                samplePromptSHA256: DecisionJevLetterResolver.samplePromptSHA256
            )
        )
        XCTAssertTrue(complete.isComplete)
        for (letter, resolvedLetter) in resolved {
            XCTAssertEqual(complete.letters[letter]?.id, resolvedLetter.id)
            XCTAssertEqual(complete.letters[letter]?.tokenStr, resolvedLetter.tokenStr)
        }
    }

    func testResumedTableEqualsAFreshlyResolvedTable() throws {
        let failing = FakeTokenizeTransport(tokenizer: Self.tokenizer(), failFromTokenizeCall: 12)
        XCTAssertThrowsError(try makeResolver(transport: failing).resolve())
        DecisionJevLetterResolver.resetCacheForTesting()
        let resumed = try makeResolver(transport: FakeTokenizeTransport(tokenizer: Self.tokenizer())).resolve()
        DecisionJevLetterResolver.resetCacheForTesting()

        let fresh = try DecisionJevLetterResolver(
            config: makeConfig(), transport: FakeTokenizeTransport(tokenizer: Self.tokenizer()),
            deadline: Self.farFutureDeadline
        ).resolve()

        XCTAssertEqual(resumed, fresh)
    }

    func testStalePartialWithDifferentBaseIDsIsDiscardedAndResolvedFresh() throws {
        let failing = FakeTokenizeTransport(tokenizer: Self.tokenizer(), failFromTokenizeCall: 12)
        XCTAssertThrowsError(try makeResolver(transport: failing).resolve())
        DecisionJevLetterResolver.resetCacheForTesting()

        let newBase = [9, 8, 7, 6, 5]
        let redeployed = FakeTokenizeTransport(tokenizer: Self.tokenizer(baseIDs: newBase))
        let resolved = try makeResolver(transport: redeployed).resolve()

        XCTAssertEqual(redeployed.tokenizeCalls, 27, "a partial for a different tokenizer must not be resumed")
        XCTAssertEqual(resolved.count, 26)
        let entry = try XCTUnwrap(
            makeCache().load(
                baseURL: makeConfig().baseURL, model: makeConfig().model,
                samplePromptSHA256: DecisionJevLetterResolver.samplePromptSHA256
            )
        )
        XCTAssertEqual(entry.baseTokenIDs, newBase)
        XCTAssertTrue(entry.isComplete)
    }

    func testAFailedLetterCheckRemovesThePartialEntryAndRethrows() throws {
        let failing = FakeTokenizeTransport(tokenizer: Self.tokenizer(), failFromTokenizeCall: 12)
        XCTAssertThrowsError(try makeResolver(transport: failing).resolve())
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL().path))
        DecisionJevLetterResolver.resetCacheForTesting()

        // Same base ids, so the partial is resumed; every remaining letter then tokenizes to two new tokens.
        let baseIDs = [1, 2, 3, 4, 5]
        let baseStrs = baseIDs.map { "b\($0)" }
        let broken = FakeTokenizeTransport { prompt in
            guard prompt != DecisionJevPromptBuilder.samplePrompt else {
                return ["tokens": baseIDs, "token_strs": baseStrs]
            }
            return ["tokens": baseIDs + [900, 901], "token_strs": baseStrs + [" x", " y"]]
        }

        XCTAssertThrowsError(try makeResolver(transport: broken).resolve()) { error in
            guard case let .readout(message) = error as? DecisionModelError else {
                return XCTFail("expected .readout, got \(error)")
            }
            XCTAssertTrue(message.contains("single token"), message)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL().path))
    }

    // MARK: - Default is off

    func testResolverDefaultsToNoDiskCache() {
        let resolver = DecisionJevLetterResolver(
            config: makeConfig(), transport: FakeTokenizeTransport(tokenizer: Self.tokenizer()),
            deadline: Self.farFutureDeadline
        )
        XCTAssertNil(resolver.diskCache)
    }

    func testPublicClientInitResolvesOverTheNetworkEveryTimeAndWritesNothing() throws {
        let transport = FakeTokenizeTransport(tokenizer: Self.tokenizer())
        let page = DecisionCandidatePage(
            labels: ["A"], candidates: [DecisionCandidate(elementIndex: 1, rowText: "button Save", isFocused: false)]
        )

        for expectedTotal in [27, 54] {
            DecisionJevLetterResolver.resetCacheForTesting()
            let client = DecisionJevClient(config: makeConfig(), transport: transport, deadline: Self.farFutureDeadline)
            // The fake serves no completions: only the resolver's /tokenize traffic is under test here.
            XCTAssertThrowsError(try client.readout(goal: "x", appName: "y", page: page))
            XCTAssertEqual(transport.tokenizeCalls, expectedTotal)
        }
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        XCTAssertEqual(leftovers, [], "the default client must not create any cache file")
    }

    func testInternalClientInitAcceptsAnExplicitDiskCache() throws {
        let transport = FakeTokenizeTransport(tokenizer: Self.tokenizer())
        let page = DecisionCandidatePage(
            labels: ["A"], candidates: [DecisionCandidate(elementIndex: 1, rowText: "button Save", isFocused: false)]
        )
        let client = DecisionJevClient(
            config: makeConfig(), transport: transport, deadline: Self.farFutureDeadline, now: Date.init,
            diskCache: makeCache()
        )
        XCTAssertThrowsError(try client.readout(goal: "x", appName: "y", page: page))

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL().path))
    }

    // MARK: - Production path shape

    func testProductionDirectoryPathShape() {
        XCTAssertTrue(
            DecisionJevLetterDiskCache.productionDirectory.path
                .hasSuffix("Library/Application Support/OpenComputerUse/decision-model/jev-letters")
        )
    }
}

/// Answers `/tokenize` in-process from a scripted function and counts the requests. Every other path throws, so a
/// test that reaches `/v1/completions` sees an error rather than a real socket. Optionally fails every tokenize
/// request from the Nth on (1-based) to model a deadline or network failure part-way through a resolution.
private final class FakeTokenizeTransport: DecisionModelTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private let tokenizer: (String) -> [String: Any]
    private let failFromTokenizeCall: Int?

    init(tokenizer: @escaping (String) -> [String: Any], failFromTokenizeCall: Int? = nil) {
        self.tokenizer = tokenizer
        self.failFromTokenizeCall = failFromTokenizeCall
    }

    var tokenizeCalls: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func postJSON(
        to url: URL, body: Data, timeout: TimeInterval, maxResponseBytes: Int, headers: [String: String]
    ) throws -> Data {
        guard url.path.hasSuffix("/tokenize") else {
            throw DecisionModelError.readout("FakeTokenizeTransport serves /tokenize only")
        }
        lock.lock()
        count += 1
        let call = count
        lock.unlock()
        if let failFromTokenizeCall, call >= failFromTokenizeCall {
            throw DecisionModelError.readout("scripted transport failure")
        }
        let object = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        return try JSONSerialization.data(withJSONObject: tokenizer(object["prompt"] as! String))
    }
}
