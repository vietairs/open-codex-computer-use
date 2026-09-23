import Foundation

// Result types for the decision-model advisory tool and their tool-result JSON.
//
// The advice is data for the host model to weigh, never an instruction the server follows: every result carries
// `advisory: true`, the full operation and target distributions, and the margin the host compares against
// `recommended_min_margin` before deciding whether to act on it.

public struct DecisionOperationProbability: Equatable, Sendable {
    public let operation: DecisionOperation
    public let probability: Double
}

public struct DecisionTargetProbability: Equatable, Sendable {
    public let elementIndex: Int
    public let probability: Double
    public let rowText: String
}

public struct DecisionAdvice: Equatable, Sendable {
    public let operation: DecisionOperation
    /// Non-nil iff operation.needsTarget. Equals targetDistribution[0].elementIndex when non-nil.
    public let elementIndex: Int?
    /// top1 − top2 of operationDistribution.
    public let operationMargin: Double
    /// top1 − top2 of targetDistribution (1.0 when one candidate).
    public let targetMargin: Double
    /// needsTarget ? min(operationMargin, targetMargin) : operationMargin
    public let margin: Double
    /// Exactly 7 entries in DecisionOperation.allCases order; sums to 1 ± 1e-9.
    public let operationDistribution: [DecisionOperationProbability]
    /// P(target | chosen operation): the target head is read after the operation letter is generated, in the same
    /// completion. Every offered candidate exactly once, sorted by probability desc then elementIndex asc; sums to
    /// 1 ± 1e-9.
    public let targetDistribution: [DecisionTargetProbability]
    /// Model calls made (1 for a single page; pages + 1 when paged).
    public let pagesQueried: Int
    public let offeredCount: Int
    public let actionableCount: Int
    public let droppedByRule: [DecisionPruneRule: Int]
    public let latencyMilliseconds: Int
}

public extension DecisionAdvice {
    /// Number of leading `target_distribution` entries that carry `row_text`, so the host can sanity-check the top
    /// choices without the result repeating the whole candidate list.
    private static let rowTextEntryCount = 3

    /// Tool result text. JSONSerialization with [.sortedKeys, .withoutEscapingSlashes]; probabilities and margins
    /// rounded to 4 decimals. Keys (exact): advisory(true), experimental(true), operation (raw value),
    /// element_index (int or null), margin, operation_margin, target_margin, recommended_min_margin,
    /// chosen_row_text (string or null — rowText of targetDistribution[0] when elementIndex != nil),
    /// operation_distribution [{operation, probability}] (7),
    /// target_distribution [{element_index, probability[, row_text]}] (row_text only on the first 3 entries),
    /// candidates {offered, actionable, pages_queried, dropped {<rule raw value>: count, only non-zero}},
    /// latency_ms, note (== DecisionAdvisor.resultNote).
    func resultJSON(recommendedMinMargin: Double) throws -> String {
        let chosenRowText: Any = elementIndex != nil
            ? (targetDistribution.first?.rowText as Any? ?? NSNull())
            : NSNull()

        let operations: [[String: Any]] = operationDistribution.map {
            ["operation": $0.operation.rawValue, "probability": Self.rounded($0.probability)]
        }
        let targets: [[String: Any]] = targetDistribution.enumerated().map { position, entry in
            var object: [String: Any] = [
                "element_index": entry.elementIndex,
                "probability": Self.rounded(entry.probability),
            ]
            if position < Self.rowTextEntryCount { object["row_text"] = entry.rowText }
            return object
        }
        var dropped: [String: Int] = [:]
        for (rule, count) in droppedByRule where count > 0 {
            dropped[rule.rawValue] = count
        }

        let object: [String: Any] = [
            "advisory": true,
            "experimental": true,
            "operation": operation.rawValue,
            "element_index": elementIndex as Any? ?? NSNull(),
            "margin": Self.rounded(margin),
            "operation_margin": Self.rounded(operationMargin),
            "target_margin": Self.rounded(targetMargin),
            "recommended_min_margin": recommendedMinMargin,
            "chosen_row_text": chosenRowText,
            "operation_distribution": operations,
            "target_distribution": targets,
            "candidates": [
                "offered": offeredCount,
                "actionable": actionableCount,
                "pages_queried": pagesQueried,
                "dropped": dropped,
            ] as [String: Any],
            "latency_ms": latencyMilliseconds,
            "note": DecisionAdvisor.resultNote,
        ]

        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        guard let text = String(data: data, encoding: .utf8) else {
            throw ComputerUseError.message("Failed to encode decide_next_action result.")
        }
        return text
    }

    private static func rounded(_ value: Double) -> Double {
        (value * 10_000).rounded() / 10_000
    }
}
