import Foundation
import XCTest
@testable import OpenComputerUseKit

/// Pins the normative `DecisionAdvisor` / `DecisionAdvice` / tool-wiring contract in
/// `plans/260923-0939-notarize-translate-decision-model/decision-model/phase-05-swift-tool-wiring-and-eval-harness.md`.
/// Written before `DecisionAdvice.swift` and `DecisionAdvisor.swift` exist; every assertion here must fail (compile
/// error or runtime assertion) until those files, plus the additive wiring in `ToolDefinitions.swift`,
/// `MCPServer.swift`, `ComputerUseToolDispatcher.swift`, and `ComputerUseService.swift`, are implemented to this
/// exact contract. Candidate pruning/paging (phase 02) and the prompt/readout client (phase 04) are already shipped
/// and are read-only dependencies here: `DecisionCandidateBuilder.defaultMaxPages == 1` in the current worktree, so
/// the multi-page (stage-2) tests below pass `maxPages` explicitly rather than relying on the default.
final class DecisionAdvisorTests: XCTestCase {

    // MARK: - Fixture text

    private static let operationLabels = DecisionOperation.allCases.map(\.label)

    /// Minimal full-tree text: short enough that `DecisionCandidateBuilder.menuBarStartIndex` fails open to `nil`
    /// (fewer than 3 lines), so the menu-bar prune rule never fires in these fixtures.
    private static let minimalRenderedFull = "App=com.example.decisiontest (pid 1)\nWindow: \"Test Window\", App: DecisionTestApp.\n"

    private static let fiveButtonRows: [(index: Int, text: String)] = [
        (1, "button New"),
        (2, "button Open"),
        (3, "button Save"),
        (4, "button Cancel"),
        (5, "button Help"),
    ]

    /// Shares no token with any of `fiveButtonRows`' text, so every row scores 0 and ranking ties break purely on
    /// ascending `elementIndex` (`DecisionCandidates.swift`'s documented tie-break) — labels land A, B, C, D, E in
    /// index order, so "button Save" (index 3) is always label "C".
    private static let fiveButtonGoal = "increment the counter"

    private static func compactActionableText(rows: [(index: Int, text: String)]) -> String {
        var lines = [
            "App=com.example.decisiontest (pid 1)",
            "Window: \"Test Window\", App: DecisionTestApp.",
            "Compact actionable view: \(rows.count) of \(rows.count) elements, screenshot omitted. "
                + "element_index values match the full tree; re-run without compact for full context.",
        ]
        lines.append(contentsOf: rows.map { "\($0.index) \($0.text)" })
        return lines.joined(separator: "\n")
    }

    private static let noActionableCompactText =
        "App=com.example.decisiontest (pid 1)\nWindow: \"Test Window\", App: DecisionTestApp.\n"
        + "(no actionable elements found; re-run without compact for the full tree)"

    private static func loopbackEndpoint(port: Int = 39501) -> DecisionModelEndpoint {
        // A literal loopback URL always parses; forcing here keeps every call site a one-liner.
        try! DecisionModelEndpoint.fromEnvironment([DecisionModelEndpoint.environmentKey: "http://127.0.0.1:\(port)"])!
    }

    private static func topTwoMargin(_ probabilities: [Double]) -> Double {
        let sorted = probabilities.sorted(by: >)
        return sorted[0] - (sorted.count > 1 ? sorted[1] : 0)
    }

    // MARK: - DecisionAdvisor.advise — single page

    func testAdviseSinglePageChoosesClickOnSaveAndReportsCompleteDistributions() throws {
        let transport = ScriptedTransport(scripts: [
            (op: ["A": -0.05, "B": -3], target: ["C": -0.1, "A": -2, "B": -2.5, "D": -3, "E": -3.5]),
        ])
        let client = DecisionModelClient(endpoint: Self.loopbackEndpoint(), transport: transport)

        let advice = try DecisionAdvisor.advise(
            goal: Self.fiveButtonGoal, appName: "DecisionTestApp",
            renderedFull: Self.minimalRenderedFull,
            renderedCompact: Self.compactActionableText(rows: Self.fiveButtonRows),
            client: client
        )

        XCTAssertEqual(advice.operation, .click)
        XCTAssertEqual(advice.elementIndex, 3, "the 'button Save' row is element_index 3")
        XCTAssertEqual(advice.pagesQueried, 1)
        XCTAssertEqual(transport.requests.count, 1)

        XCTAssertEqual(advice.operationDistribution.map(\.operation), DecisionOperation.allCases)
        XCTAssertEqual(advice.operationDistribution.reduce(0) { $0 + $1.probability }, 1, accuracy: 1e-9)

        XCTAssertEqual(advice.targetDistribution.count, 5)
        XCTAssertEqual(advice.targetDistribution.reduce(0) { $0 + $1.probability }, 1, accuracy: 1e-9)
        let targetProbabilities = advice.targetDistribution.map(\.probability)
        XCTAssertEqual(targetProbabilities, targetProbabilities.sorted(by: >), "must be sorted probability desc")
        XCTAssertEqual(advice.targetDistribution.first?.elementIndex, 3)

        XCTAssertEqual(advice.operationMargin, Self.topTwoMargin(advice.operationDistribution.map(\.probability)), accuracy: 1e-9)
        XCTAssertEqual(advice.targetMargin, Self.topTwoMargin(targetProbabilities), accuracy: 1e-9)
        XCTAssertEqual(advice.margin, min(advice.operationMargin, advice.targetMargin), accuracy: 1e-9)
    }

    func testAdviseNonTargetedOperationHasNilElementIndexAndMarginEqualsOperationMargin() throws {
        // " E" is DecisionOperation.pressKey.label (5th of allCases: click, setValue, typeText, scroll, pressKey).
        let transport = ScriptedTransport(scripts: [
            (op: ["E": -0.02, "A": -4], target: ["C": -0.2, "A": -1, "B": -1.5, "D": -2, "E": -2.5]),
        ])
        let client = DecisionModelClient(endpoint: Self.loopbackEndpoint(), transport: transport)

        let advice = try DecisionAdvisor.advise(
            goal: Self.fiveButtonGoal, appName: "DecisionTestApp",
            renderedFull: Self.minimalRenderedFull,
            renderedCompact: Self.compactActionableText(rows: Self.fiveButtonRows),
            client: client
        )

        XCTAssertEqual(advice.operation, .pressKey)
        XCTAssertNil(advice.elementIndex)
        XCTAssertEqual(advice.margin, advice.operationMargin, accuracy: 1e-9)
        XCTAssertEqual(advice.targetDistribution.count, 5, "target distribution is still complete even though unused")
        XCTAssertEqual(advice.targetDistribution.reduce(0) { $0 + $1.probability }, 1, accuracy: 1e-9)
    }

    // MARK: - DecisionAdvisor.advise — empty goal / no candidates

    func testAdviseThrowsEmptyGoalWithoutAnyModelRequest() {
        let transport = ScriptedTransport(scripts: [])
        let client = DecisionModelClient(endpoint: Self.loopbackEndpoint(), transport: transport)

        XCTAssertThrowsError(
            try DecisionAdvisor.advise(
                goal: "   ", appName: "DecisionTestApp",
                renderedFull: Self.minimalRenderedFull,
                renderedCompact: Self.compactActionableText(rows: Self.fiveButtonRows),
                client: client
            )
        ) { error in
            XCTAssertEqual(error as? DecisionAdvisorError, .emptyGoal)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testAdviseThrowsNoCandidatesWhenCompactViewHasNoActionableRows() {
        let transport = ScriptedTransport(scripts: [])
        let client = DecisionModelClient(endpoint: Self.loopbackEndpoint(), transport: transport)

        XCTAssertThrowsError(
            try DecisionAdvisor.advise(
                goal: Self.fiveButtonGoal, appName: "DecisionTestApp",
                renderedFull: Self.minimalRenderedFull,
                renderedCompact: Self.noActionableCompactText,
                client: client
            )
        ) { error in
            XCTAssertEqual(error as? DecisionAdvisorError, .noCandidates)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    // MARK: - DecisionAdvisor.advise — deadline

    /// A clock whose successive calls each advance 12 s past the prior one. `advise` calls `now()` once to capture
    /// `start`, then again before every model call to check the deadline: the second call already reads
    /// `start + 13s`, so `13 > overallDeadline (12)` trips before the first request is ever made — the earliest
    /// point at which "before the second request" (never mind the first) can be true.
    private final class TickingClock {
        private let start = Date()
        private var callCount = 0
        func now() -> Date {
            defer { callCount += 1 }
            return start.addingTimeInterval(Double(callCount) * 13)
        }
    }

    func testAdviseThrowsDeadlineExceededBeforeAnyRequestWhenClockAdvancesPastBudget() {
        let clock = TickingClock()
        let transport = ScriptedTransport(scripts: [
            (op: ["A": -0.1], target: ["C": -0.1, "A": -1]),
        ])
        let client = DecisionModelClient(endpoint: Self.loopbackEndpoint(), transport: transport)

        XCTAssertThrowsError(
            try DecisionAdvisor.advise(
                goal: Self.fiveButtonGoal, appName: "DecisionTestApp",
                renderedFull: Self.minimalRenderedFull,
                renderedCompact: Self.compactActionableText(rows: Self.fiveButtonRows),
                client: client, now: clock.now
            )
        ) { error in
            XCTAssertEqual(error as? DecisionAdvisorError, .deadlineExceeded)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    /// A clock that reads `start` until `advanceAfter` requests have been answered, then 13 s later. The deadline
    /// check between pages must stop the second request after the first one has already gone out.
    func testAdviseThrowsDeadlineExceededBetweenPagesAfterTheFirstRequestIsInFlight() {
        let rows = (1...60).map { (index: $0, text: "button Item \($0)") }
        let transport = ScriptedTransport(rawPayloads: [
            makeCompletion(op: ["A": -0.1], target: ["A": -0.1, "B": -2]),
            makeCompletion(op: ["A": -0.1], target: ["A": -0.1, "B": -2]),
            makeCompletion(op: ["A": -0.1], target: ["A": -0.1, "B": -2]),
        ])
        let client = DecisionModelClient(endpoint: Self.loopbackEndpoint(), transport: transport)
        let start = Date()
        let now = { transport.requests.isEmpty ? start : start.addingTimeInterval(13) }

        XCTAssertThrowsError(
            try DecisionAdvisor.advise(
                goal: "reorganize the layout", appName: "DecisionTestApp",
                renderedFull: Self.minimalRenderedFull,
                renderedCompact: Self.compactActionableText(rows: rows),
                client: client, maxPages: 2, now: now
            )
        ) { error in
            XCTAssertEqual(error as? DecisionAdvisorError, .deadlineExceeded)
        }
        XCTAssertEqual(transport.requests.count, 1, "the first page was sent; the second must not be")
    }

    // MARK: - DecisionAdvisor.runOffMainThread

    func testRunOffMainThreadFromTheMainThreadRunsAdviseOnABackgroundThreadWithASlowTransport() throws {
        XCTAssertTrue(Thread.isMainThread, "XCTest runs test methods on the main thread")
        let transport = SlowTransport(
            delay: 0.3,
            payload: makeCompletion(op: ["A": -0.05, "B": -3], target: ["C": -0.1, "A": -2])
        )
        let client = DecisionModelClient(endpoint: Self.loopbackEndpoint(), transport: transport)
        let goal = Self.fiveButtonGoal
        let full = Self.minimalRenderedFull
        let compact = Self.compactActionableText(rows: Self.fiveButtonRows)

        let advice = try DecisionAdvisor.runOffMainThread {
            try DecisionAdvisor.advise(
                goal: goal, appName: "DecisionTestApp", renderedFull: full, renderedCompact: compact, client: client
            )
        }

        XCTAssertEqual(advice.elementIndex, 3)
        XCTAssertEqual(transport.calledOnMainThread, [false], "the transport must never run on the main thread")
    }

    func testRunOffMainThreadGivesUpWithDeadlineExceededWhenWorkOutlivesTheTimeout() {
        let started = Date()
        XCTAssertThrowsError(
            try DecisionAdvisor.runOffMainThread(timeout: 0.2) { () -> Int in
                Thread.sleep(forTimeInterval: 2)
                return 1
            }
        ) { error in
            XCTAssertEqual(error as? DecisionAdvisorError, .deadlineExceeded)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.5, "the main thread must not wait for the work")
    }

    func testRunOffMainThreadWaitLimitIsTheOverallDeadlinePlusOneRequestTimeout() {
        XCTAssertEqual(
            DecisionAdvisor.mainThreadWaitLimit,
            DecisionAdvisor.overallDeadline + DecisionModelClient.defaultRequestTimeout
        )
    }

    // MARK: - DecisionAdvisor.advise — paging (K11 stage-2, exercised via explicit maxPages)

    func testAdvisePagesAndCombinesStage2WithPerPageDistributionsForTheReportedArgmax() throws {
        // 120 rows across 3 pages of the default pageSize (52), reusing phase 02's "120 rows, none matching the
        // goal" shape so ranking ties break purely on ascending elementIndex: page 0 = indices 1...52 (labels
        // A...z), page 1 = indices 53...104 (labels A...z), page 2 = indices 105...120 (labels A...P).
        let rows = (1...120).map { (index: $0, text: "button Item \($0)") }
        let goal = "reorganize the layout"

        let page0Winner = ("J", 1 + 9)     // position 9 (0-based) in page 0 -> elementIndex 10
        let page1Winner = ("M", 53 + 12)   // position 12 in page 1 -> elementIndex 65
        let page2Winner = ("D", 105 + 3)   // position 3 in page 2 -> elementIndex 108

        let page0Payload = makeCompletion(op: ["A": -0.1], target: [page0Winner.0: -0.05, "A": -4])
        let page1Payload = makeCompletion(op: ["A": -0.1], target: [page1Winner.0: -0.05, "B": -4])
        let page2Payload = makeCompletion(op: ["A": -0.1], target: [page2Winner.0: -0.05, "A": -4])
        // Winners sorted ascending elementIndex (10, 65, 108) always match page order (0, 1, 2) here, because each
        // page's index range is strictly greater than the previous page's — so stage-2 label "A" is page 0's
        // winner, "B" is page 1's, "C" is page 2's.
        let stage2Payload = makeCompletion(op: ["B": -0.05, "A": -3], target: ["B": -0.02, "A": -1, "C": -1.5])

        let transport = ScriptedTransport(rawPayloads: [page0Payload, page1Payload, page2Payload, stage2Payload])
        let client = DecisionModelClient(endpoint: Self.loopbackEndpoint(), transport: transport)

        let advice = try DecisionAdvisor.advise(
            goal: goal, appName: "DecisionTestApp",
            renderedFull: Self.minimalRenderedFull,
            renderedCompact: Self.compactActionableText(rows: rows),
            client: client, maxPages: 3
        )

        XCTAssertEqual(advice.pagesQueried, 4, "3 page calls + 1 stage-2 call")
        XCTAssertEqual(transport.requests.count, 4)

        let stage2Body = try XCTUnwrap(JSONSerialization.jsonObject(with: transport.requests[3].body) as? [String: Any])
        let stage2Grammar = try XCTUnwrap(stage2Body["grammar"] as? String)
        XCTAssertEqual(stage2Grammar, DecisionPromptBuilder.grammar(targetLabels: ["A", "B", "C"]))

        // Independently re-derive the combined distribution from the exact same synthetic payloads, using the
        // already-pinned (phase 04) `DecisionReadoutParser`, per K11: combined P(c on page p) = P2(winner_p) x P1_p(c).
        let page0Labels = Array(DecisionCandidateBuilder.labelAlphabet.prefix(52))
        let page2Labels = Array(DecisionCandidateBuilder.labelAlphabet.prefix(16))
        let p1Page0 = try DecisionReadoutParser.parse(
            completionResponse: page0Payload, operationLabels: Self.operationLabels, targetLabels: page0Labels
        ).target
        let p1Page1 = try DecisionReadoutParser.parse(
            completionResponse: page1Payload, operationLabels: Self.operationLabels, targetLabels: page0Labels
        ).target
        let p1Page2 = try DecisionReadoutParser.parse(
            completionResponse: page2Payload, operationLabels: Self.operationLabels, targetLabels: page2Labels
        ).target
        let p2 = try DecisionReadoutParser.parse(
            completionResponse: stage2Payload, operationLabels: Self.operationLabels, targetLabels: ["A", "B", "C"]
        ).target

        var expected: [Int: Double] = [:]
        for (offset, probability) in p1Page0.probabilities.enumerated() { expected[1 + offset] = p2.probabilities[0] * probability }
        for (offset, probability) in p1Page1.probabilities.enumerated() { expected[53 + offset] = p2.probabilities[1] * probability }
        for (offset, probability) in p1Page2.probabilities.enumerated() { expected[105 + offset] = p2.probabilities[2] * probability }
        let expectedArgmaxIndex = try XCTUnwrap(expected.max(by: { $0.value < $1.value })?.key)

        XCTAssertEqual(advice.targetDistribution.count, 120)
        XCTAssertEqual(advice.targetDistribution.reduce(0) { $0 + $1.probability }, 1, accuracy: 1e-6)
        XCTAssertEqual(advice.targetDistribution.first?.elementIndex, expectedArgmaxIndex)
        for entry in advice.targetDistribution {
            XCTAssertEqual(entry.probability, expected[entry.elementIndex] ?? 0, accuracy: 1e-9, "index \(entry.elementIndex)")
        }
    }

    // MARK: - DecisionAdvice.resultJSON

    func testResultJSONHasExactlyTheFourteenSignatureKeysAndOmitsZeroDroppedCounts() throws {
        let advice = DecisionAdvice(
            operation: .click,
            elementIndex: 3,
            operationMargin: 0.1235,
            targetMargin: 0.6543,
            margin: 0.1235,
            operationDistribution: DecisionOperation.allCases.map {
                DecisionOperationProbability(operation: $0, probability: $0 == .click ? 0.7 : 0.05)
            },
            targetDistribution: [
                DecisionTargetProbability(elementIndex: 3, probability: 0.5, rowText: "button Save"),
                DecisionTargetProbability(elementIndex: 1, probability: 0.3, rowText: "button New"),
                DecisionTargetProbability(elementIndex: 2, probability: 0.1, rowText: "button Open"),
                DecisionTargetProbability(elementIndex: 4, probability: 0.06, rowText: "button Cancel"),
                DecisionTargetProbability(elementIndex: 5, probability: 0.04, rowText: "button Help"),
            ],
            pagesQueried: 1,
            offeredCount: 5,
            actionableCount: 5,
            droppedByRule: [.disabled: 2, .overflow: 0],
            latencyMilliseconds: 42
        )

        let json = try advice.resultJSON(recommendedMinMargin: 0.35)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])

        XCTAssertEqual(Set(object.keys), [
            "advisory", "experimental", "operation", "element_index", "margin", "operation_margin", "target_margin",
            "recommended_min_margin", "chosen_row_text", "operation_distribution", "target_distribution",
            "candidates", "latency_ms", "note",
        ])
        XCTAssertEqual(object["advisory"] as? Bool, true)
        XCTAssertEqual(object["experimental"] as? Bool, true)
        XCTAssertEqual(object["operation"] as? String, "click")
        XCTAssertEqual(object["element_index"] as? Int, 3)
        XCTAssertEqual(object["recommended_min_margin"] as? Double, 0.35)
        XCTAssertEqual(object["chosen_row_text"] as? String, "button Save")
        XCTAssertEqual(object["note"] as? String, DecisionAdvisor.resultNote)
        XCTAssertEqual(object["latency_ms"] as? Int, 42)

        let operationDistribution = try XCTUnwrap(object["operation_distribution"] as? [[String: Any]])
        XCTAssertEqual(operationDistribution.count, 7)
        XCTAssertEqual(operationDistribution.first?["operation"] as? String, "click")

        let targetDistribution = try XCTUnwrap(object["target_distribution"] as? [[String: Any]])
        XCTAssertEqual(targetDistribution.count, 5)
        for (index, entry) in targetDistribution.enumerated() {
            if index < 3 {
                XCTAssertNotNil(entry["row_text"], "entry \(index) should carry row_text")
            } else {
                XCTAssertNil(entry["row_text"], "entry \(index) should omit row_text")
            }
        }

        let candidates = try XCTUnwrap(object["candidates"] as? [String: Any])
        XCTAssertEqual(candidates["offered"] as? Int, 5)
        XCTAssertEqual(candidates["actionable"] as? Int, 5)
        XCTAssertEqual(candidates["pages_queried"] as? Int, 1)
        let dropped = try XCTUnwrap(candidates["dropped"] as? [String: Any])
        XCTAssertEqual(dropped as? [String: Int], ["disabled": 2], "zero-count rules must be omitted")

        // Every probability/margin is rounded to <= 4 decimals: multiplying by 10_000 lands on (approximately) an
        // integer.
        for value in [object["margin"], object["operation_margin"], object["target_margin"]] {
            let number = try XCTUnwrap(value as? Double)
            XCTAssertEqual((number * 10_000).rounded(), number * 10_000, accuracy: 1e-6)
        }
        for entry in targetDistribution {
            let probability = try XCTUnwrap(entry["probability"] as? Double)
            XCTAssertEqual((probability * 10_000).rounded(), probability * 10_000, accuracy: 1e-6)
        }
    }

    // MARK: - ToolDefinitions.listed

    func testToolDefinitionsAllStaysNineAndExcludesDecideNextAction() {
        XCTAssertEqual(ToolDefinitions.all.count, 9)
        XCTAssertFalse(ToolDefinitions.all.contains { $0.name == "decide_next_action" })
    }

    func testToolDefinitionsListedWithEmptyEnvironmentMatchesAllByName() {
        let names = ToolDefinitions.listed(environment: [:]).map(\.name)
        XCTAssertEqual(names, ToolDefinitions.all.map(\.name))
    }

    func testToolDefinitionsListedWithValidLoopbackURLAppendsDecideNextActionLast() throws {
        let listed = ToolDefinitions.listed(environment: [DecisionModelEndpoint.environmentKey: "http://127.0.0.1:39501"])
        XCTAssertEqual(listed.count, 10)
        let last = try XCTUnwrap(listed.last)
        XCTAssertEqual(last.name, "decide_next_action")
        XCTAssertEqual(last.annotations["readOnlyHint"] as? Bool, true)
        XCTAssertEqual(last.inputSchema["required"] as? [String], ["app", "goal"])
    }

    func testToolDefinitionsListedWithNonLoopbackURLStaysAtNine() {
        let listed = ToolDefinitions.listed(environment: [DecisionModelEndpoint.environmentKey: "http://10.0.0.1:1"])
        XCTAssertEqual(listed.count, 9)
    }

    // MARK: - StdioMCPServer wiring

    private static let initializeLine =
        #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","clientInfo":{"name":"t","version":"0"},"capabilities":{}}}"#
    private static let toolsListLine = #"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"#

    private func jsonRPCResult(_ response: String?, file: StaticString = #filePath, line: UInt = #line) throws -> [String: Any] {
        let data = try XCTUnwrap(response, file: file, line: line).data(using: .utf8)!
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any], file: file, line: line)
        return try XCTUnwrap(object["result"] as? [String: Any], file: file, line: line)
    }

    func testStdioMCPServerHidesToolAndKeepsBaseInstructionsWhenEnvironmentIsEmpty() throws {
        let server = StdioMCPServer(service: ComputerUseService(), environment: { [:] })

        let initResult = try jsonRPCResult(server.handle(line: Self.initializeLine))
        XCTAssertEqual(initResult["instructions"] as? String, baseComputerUseServerInstructions)

        let listResult = try jsonRPCResult(server.handle(line: Self.toolsListLine))
        let names = (listResult["tools"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        XCTAssertFalse(names.contains("decide_next_action"))
    }

    func testStdioMCPServerListsToolAndAppendsCascadeGuideWhenURLIsValidLoopback() throws {
        let server = StdioMCPServer(
            service: ComputerUseService(),
            environment: { [DecisionModelEndpoint.environmentKey: "http://127.0.0.1:39501"] }
        )

        let initResult = try jsonRPCResult(server.handle(line: Self.initializeLine))
        let instructions = try XCTUnwrap(initResult["instructions"] as? String)
        XCTAssertTrue(instructions.hasSuffix(DecisionAdvisor.cascadeGuide))

        let listResult = try jsonRPCResult(server.handle(line: Self.toolsListLine))
        let names = (listResult["tools"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        XCTAssertTrue(names.contains("decide_next_action"))
    }

    /// In the app agent the process environment is shared by every host, and another host's overrides may be set on
    /// it at any moment. The per-call dictionary must decide listing, instructions and the call path on its own.
    func testStdioMCPServerPerCallEnvironmentWinsOverAPollutedProcessEnvironment() throws {
        let polluted = StdioMCPServer(
            service: ComputerUseService(),
            environment: { [DecisionModelEndpoint.environmentKey: "http://127.0.0.1:39501"] }
        )

        let initResult = try jsonRPCResult(polluted.handle(line: Self.initializeLine, environment: [:]))
        XCTAssertEqual(initResult["instructions"] as? String, baseComputerUseServerInstructions)

        let listResult = try jsonRPCResult(polluted.handle(line: Self.toolsListLine, environment: [:]))
        let names = (listResult["tools"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        XCTAssertFalse(names.contains("decide_next_action"))

        let callResult = try jsonRPCResult(polluted.handle(line: Self.decideCallLine, environment: [:]))
        XCTAssertEqual(callResult["isError"] as? Bool, true)
        let text = ((callResult["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        XCTAssertTrue(text.contains("decide_next_action is disabled"), text)
    }

    func testStdioMCPServerPerCallEnvironmentEnablesTheToolWhenTheProcessEnvironmentHasNoURL() throws {
        let server = StdioMCPServer(service: ComputerUseService(), environment: { [:] })
        let callEnvironment = [DecisionModelEndpoint.environmentKey: "http://127.0.0.1:39501"]

        let listResult = try jsonRPCResult(server.handle(line: Self.toolsListLine, environment: callEnvironment))
        let names = (listResult["tools"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        XCTAssertTrue(names.contains("decide_next_action"))
    }

    private static let decideCallLine =
        #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"decide_next_action","arguments":{"app":"NoSuchApp-decision-test","goal":"click something"}}}"#

    func testReadsOnlyCallEnvironmentIsTrueOnlyForDecideNextActionCalls() {
        XCTAssertTrue(StdioMCPServer.readsOnlyCallEnvironment(line: Self.decideCallLine))
        XCTAssertFalse(StdioMCPServer.readsOnlyCallEnvironment(line: Self.initializeLine))
        XCTAssertFalse(StdioMCPServer.readsOnlyCallEnvironment(line: Self.toolsListLine))
        XCTAssertFalse(StdioMCPServer.readsOnlyCallEnvironment(
            line: #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"click","arguments":{"app":"x"}}}"#
        ))
        XCTAssertFalse(StdioMCPServer.readsOnlyCallEnvironment(line: "not json"))
        XCTAssertFalse(StdioMCPServer.readsOnlyCallEnvironment(
            line: #"{"jsonrpc":"2.0","id":5,"method":"tools/list","params":{"name":"decide_next_action"}}"#
        ))
    }

    func testCLIReadsOnlyCallEnvironmentIsTrueOnlyForASingleDecideNextActionCall() {
        XCTAssertTrue(openComputerUseCLIReadsOnlyCallEnvironment(
            arguments: ["call", "decide_next_action", "--args", #"{"app":"x","goal":"y"}"#]
        ))
        XCTAssertTrue(openComputerUseCLIReadsOnlyCallEnvironment(
            arguments: ["call", "decide_next_action", "--args-file", "/nonexistent/args.json"]
        ))
        XCTAssertFalse(openComputerUseCLIReadsOnlyCallEnvironment(arguments: ["call", "click", "--args", #"{"app":"x"}"#]))
        // A sequence may mix in tools that read the process environment, so it keeps the override lock.
        XCTAssertFalse(openComputerUseCLIReadsOnlyCallEnvironment(
            arguments: ["call", "--calls", #"[{"tool":"decide_next_action","args":{"app":"x","goal":"y"}}]"#]
        ))
        XCTAssertFalse(openComputerUseCLIReadsOnlyCallEnvironment(arguments: ["list-apps"]))
        XCTAssertFalse(openComputerUseCLIReadsOnlyCallEnvironment(arguments: ["snapshot", "decide_next_action"]))
        XCTAssertFalse(openComputerUseCLIReadsOnlyCallEnvironment(arguments: ["call", "decide_next_action", "--bogus"]))
        XCTAssertFalse(openComputerUseCLIReadsOnlyCallEnvironment(arguments: []))
    }

    // MARK: - ComputerUseToolDispatcher wiring (no AX, no network — resolution never reaches a real app)

    private func makeDispatcher(environment: @escaping @Sendable () -> [String: String]) -> ComputerUseToolDispatcher {
        ComputerUseToolDispatcher(guard: MacSessionGuard(provider: UnlockedProvider()), environment: environment)
    }

    private func decideNextActionErrorDescription(
        app: String = "NoSuchApp-decision-test", goal: String, environment: [String: String],
        file: StaticString = #filePath, line: UInt = #line
    ) -> String {
        let dispatcher = makeDispatcher(environment: { environment })
        do {
            _ = try dispatcher.callTool(name: "decide_next_action", arguments: ["app": app, "goal": goal])
            XCTFail("expected decide_next_action to throw", file: file, line: line)
            return ""
        } catch let error as ComputerUseError {
            return error.errorDescription ?? ""
        } catch {
            XCTFail("expected a ComputerUseError, got \(error)", file: file, line: line)
            return ""
        }
    }

    func testDecideNextActionNamesTheEnvKeyBeforeAppResolutionWhenURLIsAbsent() {
        let description = decideNextActionErrorDescription(goal: "click something", environment: [:])
        XCTAssertTrue(description.contains(DecisionModelEndpoint.environmentKey), description)
        XCTAssertFalse(description.contains("appNotFound"), description)
    }

    func testDecideNextActionNamesTheEnvKeyBeforeAppResolutionWhenURLIsNonLoopback() {
        let description = decideNextActionErrorDescription(
            goal: "click something", environment: [DecisionModelEndpoint.environmentKey: "http://10.0.0.1:1"]
        )
        XCTAssertTrue(description.contains(DecisionModelEndpoint.environmentKey), description)
        XCTAssertFalse(description.contains("appNotFound"), description)
    }

    func testDecideNextActionRejectsBlankGoalAfterURLValidationAndBeforeAppResolution() {
        let description = decideNextActionErrorDescription(
            goal: "   ", environment: [DecisionModelEndpoint.environmentKey: "http://127.0.0.1:39501"]
        )
        XCTAssertTrue(description.contains("goal must not be empty"), description)
    }

    func testDecideNextActionUsesTheExplicitCallEnvironmentInsteadOfTheInjectedOne() {
        let dispatcher = makeDispatcher(environment: { [DecisionModelEndpoint.environmentKey: "http://127.0.0.1:39501"] })
        XCTAssertThrowsError(
            try dispatcher.callTool(
                name: "decide_next_action", arguments: ["app": "NoSuchApp-decision-test", "goal": "click something"],
                environment: [:]
            )
        ) { error in
            let description = (error as? ComputerUseError)?.errorDescription ?? ""
            XCTAssertTrue(description.contains("decide_next_action is disabled"), description)
            XCTAssertFalse(description.contains("appNotFound"), description)
        }
    }

    func testDecideNextActionReachesAppResolutionWithAValidLoopbackURLAndNonEmptyGoal() {
        let description = decideNextActionErrorDescription(
            goal: "click something", environment: [DecisionModelEndpoint.environmentKey: "http://127.0.0.1:39501"]
        )
        XCTAssertTrue(description.contains("appNotFound"), description)
    }
}

// MARK: - Test doubles

private struct UnlockedProvider: MacSessionStateProvider {
    func currentSnapshot() -> MacSessionSnapshot {
        MacSessionSnapshot(isLocked: false, isUnknown: false, rawKeysSeen: [])
    }
}

/// Builds a synthetic `/completion` response with the same `completion_probabilities` shape as
/// `scripts/decision-model/fixtures/readout-pin.json`: one entry for the operation head, one for the target head.
/// `scores` maps a bare label letter (no leading space) to its logprob; the generated token is whichever label has
/// the highest logprob, exactly like a real grammar-constrained greedy decode.
private func makeCompletion(op: [String: Double], target: [String: Double]) -> Data {
    func entry(_ scores: [String: Double]) -> [String: Any] {
        let chosen = scores.max(by: { $0.value < $1.value })!.key
        return [
            "token": " \(chosen)",
            "logprob": scores[chosen]!,
            "top_logprobs": scores.map { ["token": " \($0.key)", "logprob": $0.value] },
        ]
    }
    let object: [String: Any] = ["completion_probabilities": [entry(op), entry(target)]]
    return try! JSONSerialization.data(withJSONObject: object)
}

/// Records every `(url, body)` pair `postJSON` is called with, and answers each call in order from a queue of
/// scripted `(op, target)` logprob maps (via `makeCompletion`), or from pre-built raw payloads.
private final class ScriptedTransport: DecisionModelTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [(url: URL, body: Data)] = []
    private var payloads: [Data]

    init(scripts: [(op: [String: Double], target: [String: Double])]) {
        payloads = scripts.map { makeCompletion(op: $0.op, target: $0.target) }
    }

    init(rawPayloads: [Data]) {
        payloads = rawPayloads
    }

    func postJSON(to url: URL, body: Data, timeout: TimeInterval, maxResponseBytes: Int) throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        recorded.append((url, body))
        guard !payloads.isEmpty else {
            throw DecisionModelError.readout("ScriptedTransport ran out of scripted responses")
        }
        return payloads.removeFirst()
    }

    var requests: [(url: URL, body: Data)] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }
}

/// Answers every call with the same payload after `delay`, and records whether each call ran on the main thread.
private final class SlowTransport: DecisionModelTransport, @unchecked Sendable {
    private let delay: TimeInterval
    private let payload: Data
    private let lock = NSLock()
    private var mainThreadFlags: [Bool] = []

    init(delay: TimeInterval, payload: Data) {
        self.delay = delay
        self.payload = payload
    }

    func postJSON(to url: URL, body: Data, timeout: TimeInterval, maxResponseBytes: Int) throws -> Data {
        lock.lock()
        mainThreadFlags.append(Thread.isMainThread)
        lock.unlock()
        Thread.sleep(forTimeInterval: delay)
        return payload
    }

    var calledOnMainThread: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return mainThreadFlags
    }
}
