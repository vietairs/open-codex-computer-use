import Foundation

// Composes candidate pruning/paging and the two-head readout client into one advisory decision.
//
// Pure with respect to the machine: it reads two already-rendered strings and talks only to the injected client.
// It never touches AX, never actuates UI, and never spawns a process. The same `advise` entry point serves the
// `decide_next_action` MCP tool and the offline eval harness, so the eval measures shipped code.
//
// Time bound: `overallDeadline` is checked before every model call, and each call is bounded by the client's request
// timeout (5 s by default), so one decision holds its caller for at most ~17 s.

public enum DecisionAdvisorError: Error, Equatable, LocalizedError {
    /// The endpoint environment key is absent.
    case disabled
    case emptyGoal
    /// No candidate survived pruning, so there is nothing to offer the model.
    case noCandidates
    case deadlineExceeded

    public var errorDescription: String? {
        switch self {
        case .disabled:
            return "decide_next_action is disabled: set \(DecisionModelEndpoint.environmentKey) to a loopback "
                + "llama-server URL such as http://127.0.0.1:<port> (start one with scripts/decision-model/start-sidecar.sh)."
        case .emptyGoal:
            return "goal must not be empty"
        case .noCandidates:
            return "no actionable candidates in the current app state; call get_app_state and decide yourself"
        case .deadlineExceeded:
            return "the decision model did not answer within \(Int(DecisionAdvisor.overallDeadline)) seconds"
        }
    }
}

public enum DecisionAdvisor {
    /// Smallest margin at which the offline eval measured >= 90% precision; 1.0 means "never auto-follow".
    /// Set from scripts/decision-model/eval-data/summary.json. Start value here: 1.0.
    public static let recommendedMinMargin: Double = 0.72
    public static let overallDeadline: TimeInterval = 12
    /// One-line reminder embedded in every result.
    public static let resultNote: String =
        "Advisory only; the server never acts. Follow only when margin >= recommended_min_margin and the operation "
        + "is non-destructive; otherwise call get_app_state and decide yourself."
    /// Host-side cascade guide. Appended to the MCP `initialize` instructions only when the tool is enabled.
    /// skills/open-computer-use/references/decision-model.md carries the same text verbatim.
    public static let cascadeGuide: String = [
        "decide_next_action (experimental, advisory): a local model proposes the next operation and target from the current app state. It never acts.",
        "- Follow the advice only when margin >= recommended_min_margin AND the operation is non-destructive (not send, delete, purchase, submit, sign in/out, or anything externally visible) AND chosen_row_text matches your intent.",
        "- Otherwise call get_app_state and decide yourself. Low margin means the model is unsure.",
        "- Pass your own sub-goal in plain words. Never paste screen text into goal.",
        "- element_index values are valid for the next click, set_value, or scroll on the same app, exactly like get_app_state.",
    ].joined(separator: "\n")

    /// Blocking; performs one model call per candidate page, plus one stage-2 call when there is more than one page.
    /// Must be called off the main thread when the client's transport requires it.
    public static func advise(
        goal: String,
        appName: String,
        renderedFull: String,
        renderedCompact: String,
        client: DecisionModelClient,
        maxPages: Int = DecisionCandidateBuilder.defaultMaxPages,
        now: () -> Date = Date.init
    ) throws -> DecisionAdvice {
        let trimmedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedGoal.isEmpty else { throw DecisionAdvisorError.emptyGoal }
        let start = now()

        let set = DecisionCandidateBuilder.build(
            goal: trimmedGoal, renderedFull: renderedFull, renderedCompact: renderedCompact, maxPages: maxPages
        )
        guard !set.offeredIndices.isEmpty else { throw DecisionAdvisorError.noCandidates }

        var modelCalls = 0
        func readout(_ page: DecisionCandidatePage) throws -> DecisionHeadReadout {
            guard now().timeIntervalSince(start) <= overallDeadline else { throw DecisionAdvisorError.deadlineExceeded }
            modelCalls += 1
            return try client.readout(goal: trimmedGoal, appName: appName, page: page)
        }

        let operationProbabilities: [Double]
        var targets: [DecisionTargetProbability] = []
        if set.pages.count == 1 {
            let page = set.pages[0]
            let result = try readout(page)
            operationProbabilities = result.operation.probabilities
            targets = zip(page.candidates, result.target.probabilities).map { candidate, probability in
                DecisionTargetProbability(elementIndex: candidate.elementIndex, probability: probability, rowText: candidate.rowText)
            }
        } else {
            // Stage 1: each page's own distribution and winner. Stage 2: the model picks among the winners, and a
            // candidate's combined probability is P2(its page's winner) × P1(candidate within its page).
            var stageOne: [(page: DecisionCandidatePage, target: DecisionDistribution, winner: DecisionCandidate)] = []
            for page in set.pages {
                let result = try readout(page)
                guard let winnerPosition = page.labels.firstIndex(of: result.target.chosenLabel) else {
                    throw DecisionModelError.readout("chosen target label is not on the page")
                }
                stageOne.append((page, result.target, page.candidates[winnerPosition]))
            }
            let winners = stageOne.map(\.winner).sorted { $0.elementIndex < $1.elementIndex }
            let stageTwoPage = DecisionCandidatePage(
                labels: Array(DecisionCandidateBuilder.labelAlphabet.prefix(winners.count)), candidates: winners
            )
            let stageTwo = try readout(stageTwoPage)
            operationProbabilities = stageTwo.operation.probabilities

            var winnerProbability: [Int: Double] = [:]
            for (winner, probability) in zip(winners, stageTwo.target.probabilities) {
                winnerProbability[winner.elementIndex] = probability
            }
            for entry in stageOne {
                let pageWeight = winnerProbability[entry.winner.elementIndex] ?? 0
                for (candidate, probability) in zip(entry.page.candidates, entry.target.probabilities) {
                    targets.append(DecisionTargetProbability(
                        elementIndex: candidate.elementIndex, probability: pageWeight * probability, rowText: candidate.rowText
                    ))
                }
            }
        }

        let operations = zip(DecisionOperation.allCases, operationProbabilities).map {
            DecisionOperationProbability(operation: $0, probability: $1)
        }
        guard operations.count == DecisionOperation.allCases.count else {
            throw DecisionModelError.readout("operation distribution does not cover every operation")
        }
        // Ties break toward the earlier operation (allCases order) and the lower elementIndex.
        let chosenOperation = operations.reduce(operations[0]) { $1.probability > $0.probability ? $1 : $0 }.operation
        targets.sort { lhs, rhs in
            lhs.probability != rhs.probability ? lhs.probability > rhs.probability : lhs.elementIndex < rhs.elementIndex
        }

        let operationMargin = topTwoMargin(operations.map(\.probability))
        let targetMargin = topTwoMargin(targets.map(\.probability))
        let needsTarget = chosenOperation.needsTarget

        var droppedByRule: [DecisionPruneRule: Int] = [:]
        for rule in set.dropped.values { droppedByRule[rule, default: 0] += 1 }

        return DecisionAdvice(
            operation: chosenOperation,
            elementIndex: needsTarget ? targets.first?.elementIndex : nil,
            operationMargin: operationMargin,
            targetMargin: targetMargin,
            margin: needsTarget ? min(operationMargin, targetMargin) : operationMargin,
            operationDistribution: operations,
            targetDistribution: targets,
            pagesQueried: modelCalls,
            offeredCount: set.offeredIndices.count,
            actionableCount: set.actionableCount,
            droppedByRule: droppedByRule,
            latencyMilliseconds: Int(now().timeIntervalSince(start) * 1000)
        )
    }

    /// top1 − top2; top2 is 0 when there is a single entry.
    private static func topTwoMargin(_ probabilities: [Double]) -> Double {
        let ranked = probabilities.sorted(by: >)
        guard let top = ranked.first else { return 0 }
        return top - (ranked.count > 1 ? ranked[1] : 0)
    }

    /// Runs `work` off the main thread. On the main thread it hops to a global queue with `async` and waits on a
    /// semaphore; `sync` is avoided because it may execute the block on the calling (main) thread.
    static func runOffMainThread<T: Sendable>(_ work: @escaping @Sendable () throws -> T) throws -> T {
        guard Thread.isMainThread else { return try work() }
        let box = ResultBox<T>()
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            box.store(Result { try work() })
            finished.signal()
        }
        finished.wait()
        return try box.load().get()
    }
}

/// Hands one result from a background queue to the waiting thread.
private final class ResultBox<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<T, Error>?

    func store(_ value: Result<T, Error>) {
        lock.lock()
        defer { lock.unlock() }
        result = value
    }

    func load() -> Result<T, Error> {
        lock.lock()
        defer { lock.unlock() }
        return result ?? .failure(DecisionModelError.transport("background decision task produced no result"))
    }
}
