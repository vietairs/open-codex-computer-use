import Foundation

// Client for the remote OpenAI-compatible vLLM "jev" engine: the /v1/completions request and response parsing.
// Letter resolution and prompt construction live in `DecisionJevPrompt.swift`. Conforms to
// `DecisionReadoutProviding` (`DecisionAdvisor.swift`), so `DecisionAdvisor.advise` runs unchanged whichever backend
// it is given.
//
// Wire contract source: vLLM 0.28 jev engine, `benchmark/jev/jev_client.py` on selfHostLLM (read 2026-09-28). The
// engine runs `--logprobs-mode processed_logprobs`, so `top_logprobs` in a completion response is already
// renormalised over `allowed_token_ids`; this client still renormalises over the offered labels defensively, exactly
// like `DecisionReadoutParser.distribution` does for the loopback llama-server.

/// Turns a jev `/v1/completions` response into a label-renormalised distribution, the same shape
/// `DecisionReadoutParser.distribution` produces for the loopback llama-server. Error texts never echo
/// server-supplied text, for the same reason as the llama-server parser: a squatting or hostile server controls the
/// generated token text, and that text ends up in a tool result the host LLM reads.
///
/// The engine's contract (`logprobs: n`, `allowed_token_ids` = exactly the n offered ids, `--logprobs-mode
/// processed_logprobs`) guarantees every offered label has an entry in `top_logprobs`. A missing label is therefore
/// a contract violation, not a normal case — scoring it 0 would silently manufacture false confidence (a margin up
/// to 1.0 built entirely from absent data), so this parser fails closed instead of defaulting anything to 0.
enum DecisionJevReadoutParser {
    private static let argmaxTolerance = 1e-9

    /// The two failure messages that mean the cached letter-to-token map no longer matches this server's tokenizer
    /// (for example a tokenizer redeploy under the same `(base_url, model)`), rather than a one-off malformed
    /// response — `DecisionJevClient.completeAndParse` evicts the letter cache when it sees either of these, so the
    /// next call re-resolves instead of failing the same way for the life of the process.
    static let staleLetterCacheMessages: Set<String> = [
        "offered label missing from top_logprobs", "generated text is not an offered label",
    ]

    static func parse(
        completionResponse: Data, labels: [String], letterMap: [String: DecisionJevLetterResolver.ResolvedLetter]
    ) throws -> DecisionDistribution {
        guard !labels.isEmpty else { throw DecisionModelError.readout("label set must not be empty") }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: completionResponse)
        } catch {
            throw DecisionModelError.readout("response is not JSON")
        }
        guard let root = object as? [String: Any], let choices = root["choices"] as? [[String: Any]],
              let first = choices.first
        else { throw DecisionModelError.readout("expected at least one choice") }
        guard let text = first["text"] as? String else {
            throw DecisionModelError.readout("missing generated text")
        }
        let generatedLabel = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let chosenIndex = labels.firstIndex(of: generatedLabel) else {
            throw DecisionModelError.readout("generated text is not an offered label")
        }
        guard let logprobsObject = first["logprobs"] as? [String: Any],
              let topLogprobsArray = logprobsObject["top_logprobs"] as? [[String: Any]],
              let topLogprobs = topLogprobsArray.first
        else { throw DecisionModelError.readout("missing top_logprobs") }

        var logprobByTokenStr: [String: Double] = [:]
        for (tokenStr, value) in topLogprobs {
            guard let number = (value as? NSNumber)?.doubleValue, number.isFinite else { continue }
            logprobByTokenStr[tokenStr] = number
        }

        // Fail closed the moment any offered label is missing, rather than defaulting it to probability 0.
        let logprobs: [Double] = try labels.map { label in
            guard let resolved = letterMap[label], let logprob = logprobByTokenStr[resolved.tokenStr] else {
                throw DecisionModelError.readout("offered label missing from top_logprobs")
            }
            return logprob
        }

        let maxLogprob = logprobs.max()!
        let denominator = logprobs.reduce(0) { $0 + exp($1 - maxLogprob) }
        let probabilities = logprobs.map { exp($0 - maxLogprob) / denominator }

        let ranked = probabilities.sorted(by: >)
        let top = ranked[0]
        let chosenProbability = probabilities[chosenIndex]
        guard chosenProbability >= top - argmaxTolerance else {
            throw DecisionModelError.readout("generated label is not the argmax")
        }
        let margin = top - (ranked.count > 1 ? ranked[1] : 0)
        return DecisionDistribution(
            labels: labels, probabilities: probabilities, chosenLabel: generatedLabel,
            margin: margin, missingLabels: []
        )
    }
}

/// `DecisionReadoutProviding` for the remote jev backend: two single-token `/v1/completions` calls per page (the
/// operation head, then the target head), sharing one letter resolution. Advisory only, exactly like the loopback
/// client: it only reads a distribution, it never acts.
public final class DecisionJevClient: DecisionReadoutProviding, Sendable {
    /// The engine's target-head label cap: page.labels.count must never exceed this.
    public static let pageSize = 26
    /// 2 pages of 26 = 52 candidates offered, matching the loopback backend's single 52-candidate page.
    public static let maxPages = 2
    static let requestTimeout: TimeInterval = 5
    static let maxResponseBytes = 1_048_576

    private let config: DecisionRemoteBackendConfig
    private let transport: DecisionModelTransport
    private let resolver: DecisionJevLetterResolver
    /// Absolute wall-clock deadline for every request this client (and its resolver) makes across the whole
    /// `decideNextAction` call — every page readout and the stage-2 call, not just the first one. Bounds the up to
    /// 27 `/tokenize` requests the same way it bounds the 2 `/v1/completions` requests per page.
    private let deadline: Date
    private let now: @Sendable () -> Date

    public init(
        config: DecisionRemoteBackendConfig, transport: DecisionModelTransport, deadline: Date,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.config = config
        self.transport = transport
        self.deadline = deadline
        self.now = now
        resolver = DecisionJevLetterResolver(config: config, transport: transport, deadline: deadline, now: now)
    }

    public func readout(goal: String, appName: String, page: DecisionCandidatePage) throws -> DecisionHeadReadout {
        guard !page.labels.isEmpty, page.labels.count == page.candidates.count, page.labels.count <= Self.pageSize
        else {
            throw DecisionModelError.readout(
                "candidate page must have one label per candidate, at least one and at most \(Self.pageSize)"
            )
        }
        let letterMap = try resolver.resolve()

        let operationLabels = DecisionOperation.allCases.map(\.label)
        let operationPrompt = DecisionJevPromptBuilder.operationPrompt(goal: goal, appName: appName, page: page)
        let operation = try completeAndParse(prompt: operationPrompt, labels: operationLabels, letterMap: letterMap)

        let targetPrompt = DecisionJevPromptBuilder.targetPrompt(goal: goal, appName: appName, page: page)
        let target = try completeAndParse(prompt: targetPrompt, labels: page.labels, letterMap: letterMap)

        return DecisionHeadReadout(operation: operation, target: target)
    }

    private func completeAndParse(
        prompt: String, labels: [String], letterMap: [String: DecisionJevLetterResolver.ResolvedLetter]
    ) throws -> DecisionDistribution {
        let remaining = deadline.timeIntervalSince(now())
        guard remaining > 0 else { throw DecisionAdvisorError.deadlineExceeded }
        let allowedTokenIDs = try labels.map { label -> Int in
            guard let resolved = letterMap[label] else {
                throw DecisionModelError.readout("no resolved token for an offered label")
            }
            return resolved.id
        }
        let body: [String: Any] = [
            "allowed_token_ids": allowedTokenIDs,
            "logprobs": labels.count,
            "max_tokens": 1,
            "model": config.model,
            "prompt": prompt,
            "temperature": 0,
        ]
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        let response = try transport.postJSON(
            to: config.completionsURL, body: data, timeout: min(Self.requestTimeout, remaining),
            maxResponseBytes: Self.maxResponseBytes, headers: ["Authorization": "Bearer \(config.apiKey)"]
        )
        do {
            return try DecisionJevReadoutParser.parse(completionResponse: response, labels: labels, letterMap: letterMap)
        } catch let error as DecisionModelError {
            // A response that fails to parse in one of these specific ways looks like the cached letters no longer
            // match this server's tokenizer (see `DecisionJevReadoutParser.staleLetterCacheMessages`), not a
            // one-off bad response — evict so the next call re-resolves instead of repeating the same failure for
            // the life of the process.
            if case .readout(let message) = error, DecisionJevReadoutParser.staleLetterCacheMessages.contains(message) {
                resolver.invalidateCache()
            }
            throw error
        }
    }
}
