import Foundation

// Loopback-only endpoint, two-head readout parser, and the client that ties prompt, transport, and parser together
// for the decision-model advisory tool. The HTTP transport lives in `DecisionModelTransport.swift`.

public enum DecisionModelError: Error, Equatable, LocalizedError {
    case malformedURL(String)
    case unsupportedScheme(String)
    case nonLoopbackHost(String)
    case transport(String)
    case timeout
    case redirectRefused
    case responseTooLarge(limit: Int)
    case httpStatus(Int)
    case readout(String)
    /// The loopback listener is not the llama-server that start-sidecar.sh recorded; nothing was sent to it.
    case unverifiedSidecar(String)

    public var errorDescription: String? {
        switch self {
        case .malformedURL(let value): return "Decision model URL is malformed: \(value)"
        case .unsupportedScheme(let scheme): return "Decision model URL must use http, not \(scheme)"
        case .nonLoopbackHost(let host): return "Decision model host must be 127.0.0.1, not \(host)"
        case .transport(let message): return "Decision model request failed: \(message)"
        case .timeout: return "Decision model request timed out"
        case .redirectRefused: return "Decision model server attempted a redirect, which is refused"
        case .responseTooLarge(let limit): return "Decision model response exceeded \(limit) bytes"
        case .httpStatus(let status): return "Decision model server returned HTTP \(status)"
        case .readout(let message): return "Decision model readout is unusable: \(message)"
        case .unverifiedSidecar(let reason):
            return "Decision model listener is not the sidecar recorded by scripts/decision-model/start-sidecar.sh "
                + "(\(reason)); no goal or screen text was sent. Start the sidecar with start-sidecar.sh, or unset "
                + "\(DecisionModelEndpoint.environmentKey)."
        }
    }
}

public struct DecisionModelEndpoint: Equatable, Sendable {
    public static let environmentKey: String = "OPEN_COMPUTER_USE_DECISION_MODEL_URL"

    /// "http://<host>:<port>" — no path, no trailing slash.
    public let baseURL: URL

    /// baseURL + "/completion"
    public var completionURL: URL { URL(string: baseURL.absoluteString + "/completion")! }

    /// The literal IPv4 loopback address only, because that is the only address start-sidecar.sh binds. `localhost`
    /// is refused because the resolver may map it to `::1`. `[::1]` is refused because the IPv4 bind does not reserve
    /// the IPv6 port, so any same-uid process could listen there and receive the goal and screen rows instead of the
    /// sidecar.
    static func canonicalLoopbackHost(_ host: String) -> String? {
        host == "127.0.0.1" ? host : nil
    }

    /// The port the sidecar must be listening on, for the ownership check before any request is sent.
    public var port: Int { baseURL.port ?? 0 }

    /// nil when the key is absent or whitespace-only. Throws for anything that is not
    /// http://127.0.0.1:<1-65535>[/] with no userinfo, query, fragment or other path.
    public static func fromEnvironment(_ environment: [String: String]) throws -> DecisionModelEndpoint? {
        guard let raw = environment[environmentKey] else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return nil }

        guard let components = URLComponents(string: value), let scheme = components.scheme else {
            throw DecisionModelError.malformedURL(value)
        }
        guard scheme.lowercased() == "http" else { throw DecisionModelError.unsupportedScheme(scheme) }
        guard components.percentEncodedUser == nil, components.percentEncodedPassword == nil,
              components.percentEncodedQuery == nil, components.percentEncodedFragment == nil,
              components.percentEncodedPath.isEmpty || components.percentEncodedPath == "/"
        else { throw DecisionModelError.malformedURL(value) }
        guard let rawHost = components.percentEncodedHost, !rawHost.isEmpty else {
            throw DecisionModelError.malformedURL(value)
        }
        guard let host = canonicalLoopbackHost(rawHost) else { throw DecisionModelError.nonLoopbackHost(rawHost) }
        guard let port = components.port, (1...65_535).contains(port) else {
            throw DecisionModelError.malformedURL(value)
        }
        guard let baseURL = URL(string: "http://\(host):\(port)") else { throw DecisionModelError.malformedURL(value) }
        return DecisionModelEndpoint(baseURL: baseURL)
    }
}

public struct DecisionDistribution: Equatable, Sendable {
    /// Requested order.
    public let labels: [String]
    /// Renormalised over labels; absent labels = 0; sums to 1.
    public let probabilities: [Double]
    /// The generated label.
    public let chosenLabel: String
    /// top1 − top2 (top2 = 0 when one label).
    public let margin: Double
    /// Labels absent from top_logprobs.
    public let missingLabels: [String]
}

public struct DecisionHeadReadout: Equatable, Sendable {
    public let operation: DecisionDistribution
    public let target: DecisionDistribution
}

/// Turns llama-server `completion_probabilities` (pre-sampling logprobs) into label-renormalised distributions.
///
/// The operation head is entry 0. The target head is the last entry whose token is one of the target labels: after
/// the grammar's root production completes, the server may append a forced-stop entry with an empty token, so the
/// raw last element is not reliable (see the pin file's `responseShapeNote`).
public enum DecisionReadoutParser {
    private static let argmaxTolerance = 1e-9

    public static func parse(
        completionResponse: Data, operationLabels: [String], targetLabels: [String]
    ) throws -> DecisionHeadReadout {
        guard !operationLabels.isEmpty, !targetLabels.isEmpty else {
            throw DecisionModelError.readout("label sets must not be empty")
        }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: completionResponse)
        } catch {
            throw DecisionModelError.readout("response is not JSON")
        }
        guard let root = object as? [String: Any],
              let entries = root["completion_probabilities"] as? [[String: Any]], entries.count >= 2
        else { throw DecisionModelError.readout("expected at least 2 generated positions") }
        if entries.contains(where: { $0["top_probs"] != nil }) {
            throw DecisionModelError.readout("post-sampling probabilities are not supported")
        }

        let operation = try distribution(entry: entries[0], labels: operationLabels, head: "operation")
        let targetPieces = Set(targetLabels.map { " " + $0 })
        let targetEntry = entries.dropFirst().last { entry in
            (entry["token"] as? String).map(targetPieces.contains) ?? false
        }
        // Error texts never echo server-supplied tokens: they end up in the tool result the host LLM reads, and a
        // squatting server could otherwise inject up to the response cap of arbitrary text there.
        guard let targetEntry else {
            throw DecisionModelError.readout("unexpected token at target head")
        }
        let target = try distribution(entry: targetEntry, labels: targetLabels, head: "target")
        return DecisionHeadReadout(operation: operation, target: target)
    }

    private static func distribution(entry: [String: Any], labels: [String], head: String) throws -> DecisionDistribution {
        let token = entry["token"] as? String ?? ""
        guard token.hasPrefix(" "), labels.contains(String(token.dropFirst())) else {
            throw DecisionModelError.readout("unexpected token at \(head) head")
        }
        let chosenLabel = String(token.dropFirst())
        guard let topLogprobs = entry["top_logprobs"] as? [[String: Any]] else {
            throw DecisionModelError.readout("missing top_logprobs at \(head) head")
        }

        // First occurrence wins if the server ever repeats a token.
        var logprobByToken: [String: Double] = [:]
        for candidate in topLogprobs {
            guard let candidateToken = candidate["token"] as? String,
                  let logprob = (candidate["logprob"] as? NSNumber)?.doubleValue, logprob.isFinite,
                  logprobByToken[candidateToken] == nil
            else { continue }
            logprobByToken[candidateToken] = logprob
        }

        var logprobs: [Double?] = labels.map { logprobByToken[" " + $0] }
        if let chosenIndex = labels.firstIndex(of: chosenLabel), logprobs[chosenIndex] == nil {
            guard let own = (entry["logprob"] as? NSNumber)?.doubleValue, own.isFinite else {
                throw DecisionModelError.readout("generated label has no logprob at \(head) head")
            }
            logprobs[chosenIndex] = own
        }

        // Max-subtraction keeps exp() in range for very negative logprobs.
        let present = logprobs.compactMap { $0 }
        let maxLogprob = present.max()!
        let denominator = present.reduce(0) { $0 + exp($1 - maxLogprob) }
        let probabilities = logprobs.map { $0.map { exp($0 - maxLogprob) / denominator } ?? 0 }

        let ranked = probabilities.sorted(by: >)
        let top = ranked[0]
        let chosenProbability = probabilities[labels.firstIndex(of: chosenLabel)!]
        guard chosenProbability >= top - argmaxTolerance else {
            throw DecisionModelError.readout("generated label is not the argmax")
        }
        let margin = top - (ranked.count > 1 ? ranked[1] : 0)
        let missingLabels = zip(labels, logprobs).filter { $0.1 == nil }.map(\.0)
        return DecisionDistribution(
            labels: labels, probabilities: probabilities, chosenLabel: chosenLabel,
            margin: margin, missingLabels: missingLabels
        )
    }
}

public struct DecisionModelClient: Sendable {
    public static let defaultRequestTimeout: TimeInterval = 5
    public static let defaultMaxResponseBytes: Int = 1_048_576
    public static let defaultNProbs: Int = 128

    private let endpoint: DecisionModelEndpoint
    private let transport: DecisionModelTransport
    private let requestTimeout: TimeInterval
    private let maxResponseBytes: Int
    private let nProbs: Int

    public init(
        endpoint: DecisionModelEndpoint, transport: DecisionModelTransport,
        requestTimeout: TimeInterval = defaultRequestTimeout,
        maxResponseBytes: Int = defaultMaxResponseBytes,
        nProbs: Int = defaultNProbs
    ) {
        self.endpoint = endpoint
        self.transport = transport
        self.requestTimeout = requestTimeout
        self.maxResponseBytes = maxResponseBytes
        self.nProbs = nProbs
    }

    /// One blocking `/completion` round trip for one candidate page. Must be called off the main thread.
    public func readout(goal: String, appName: String, page: DecisionCandidatePage) throws -> DecisionHeadReadout {
        guard !page.labels.isEmpty, page.labels.count == page.candidates.count else {
            throw DecisionModelError.readout("candidate page must have one label per candidate and at least one")
        }
        let prompt = DecisionPromptBuilder.prompt(goal: goal, appName: appName, page: page)
        let grammar = DecisionPromptBuilder.grammar(targetLabels: page.labels)
        let body = try DecisionPromptBuilder.completionRequestBody(prompt: prompt, grammar: grammar, nProbs: nProbs)
        let response = try transport.postJSON(
            to: endpoint.completionURL, body: body, timeout: requestTimeout, maxResponseBytes: maxResponseBytes
        )
        return try DecisionReadoutParser.parse(
            completionResponse: response,
            operationLabels: DecisionOperation.allCases.map(\.label),
            targetLabels: page.labels
        )
    }
}
