import Foundation
import OpenComputerUseKit

// Dev-only eval harness: replays captured app-state snapshots through the shipped `DecisionAdvisor.advise` entry
// point, so offline measurements describe the exact code the MCP tool runs.
//
//   swift run DecisionModelEval (--prune-only | --url http://127.0.0.1:<port>)
//
// stdin : JSONL, one object per line: {"id", "goal", "app", "renderedFull", "renderedCompact"} (all strings).
// stdout: JSONL, one object per input line, same order:
//         {"id", "offered_indices", "dropped": {"<index>": "<rule>"}, "actionable_count",
//          "advice": <parsed resultJSON object> | null, "error": str | null, "wall_ms"}
// Exit codes: 0 success; 2 stdin is not JSONL of that shape; 3 the URL is rejected; 64 bad command-line usage.
// Per-item model errors go in "error" and never abort the run. No AX, no AppKit, no file writes.

private let usage = "usage: DecisionModelEval (--prune-only | --url http://127.0.0.1:<port>)"

private struct EvalItem {
    let id: String
    let goal: String
    let app: String
    let renderedFull: String
    let renderedCompact: String
}

private enum Mode {
    case pruneOnly
    case advise(DecisionModelClient)
}

private struct ExitFailure: Error {
    let code: Int32
    let message: String
}

private func parseMode(_ arguments: [String]) throws -> Mode {
    switch arguments {
    case ["--prune-only"]:
        return .pruneOnly
    case let args where args.count == 2 && args[0] == "--url":
        let endpoint: DecisionModelEndpoint?
        do {
            endpoint = try DecisionModelEndpoint.fromEnvironment([DecisionModelEndpoint.environmentKey: args[1]])
        } catch {
            throw ExitFailure(code: 3, message: "rejected URL: \(error.localizedDescription)")
        }
        guard let endpoint else { throw ExitFailure(code: 3, message: "rejected URL: empty") }
        return .advise(DecisionModelClient(endpoint: endpoint, transport: URLSessionDecisionModelTransport()))
    default:
        throw ExitFailure(code: 64, message: usage)
    }
}

/// Parses every non-empty stdin line before any work starts, so malformed input never yields partial output.
private func parseItems(_ data: Data) throws -> [EvalItem] {
    guard let text = String(data: data, encoding: .utf8) else {
        throw ExitFailure(code: 2, message: "stdin is not UTF-8")
    }
    var items: [EvalItem] = []
    for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { continue }
        guard let object = (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) as? [String: Any],
              let id = object["id"] as? String, let goal = object["goal"] as? String,
              let app = object["app"] as? String, let renderedFull = object["renderedFull"] as? String,
              let renderedCompact = object["renderedCompact"] as? String
        else {
            throw ExitFailure(
                code: 2,
                message: "stdin line \(number + 1) is not a JSON object with string id, goal, app, renderedFull, renderedCompact"
            )
        }
        items.append(EvalItem(id: id, goal: goal, app: app, renderedFull: renderedFull, renderedCompact: renderedCompact))
    }
    return items
}

private func evaluate(_ item: EvalItem, mode: Mode) -> [String: Any] {
    let started = Date()
    let set = DecisionCandidateBuilder.build(
        goal: item.goal, renderedFull: item.renderedFull, renderedCompact: item.renderedCompact
    )
    var dropped: [String: String] = [:]
    for (index, rule) in set.dropped { dropped[String(index)] = rule.rawValue }

    var advice: Any = NSNull()
    var failure: Any = NSNull()
    if case .advise(let client) = mode {
        do {
            let result = try DecisionAdvisor.advise(
                goal: item.goal, appName: item.app, renderedFull: item.renderedFull,
                renderedCompact: item.renderedCompact, client: client
            )
            let json = try result.resultJSON(recommendedMinMargin: DecisionAdvisor.recommendedMinMargin)
            advice = try JSONSerialization.jsonObject(with: Data(json.utf8))
        } catch {
            failure = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    return [
        "id": item.id,
        "offered_indices": set.offeredIndices,
        "dropped": dropped,
        "actionable_count": set.actionableCount,
        "advice": advice,
        "error": failure,
        "wall_ms": Int(Date().timeIntervalSince(started) * 1000),
    ]
}

private func writeLine(_ text: String, to handle: FileHandle) {
    handle.write(Data((text + "\n").utf8))
}

private func run(arguments: [String]) -> Int32 {
    do {
        let mode = try parseMode(arguments)
        let items = try parseItems(FileHandle.standardInput.readDataToEndOfFile())
        for item in items {
            let data = try JSONSerialization.data(
                withJSONObject: evaluate(item, mode: mode), options: [.sortedKeys, .withoutEscapingSlashes]
            )
            writeLine(String(decoding: data, as: UTF8.self), to: .standardOutput)
        }
        return 0
    } catch let failure as ExitFailure {
        writeLine("DecisionModelEval: \(failure.message)", to: .standardError)
        return failure.code
    } catch {
        writeLine("DecisionModelEval: \(error.localizedDescription)", to: .standardError)
        return 1
    }
}

/// Holds the background thread's exit code for the waiting main thread.
private final class ExitCodeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var code: Int32 = 1

    func set(_ value: Int32) {
        lock.lock()
        defer { lock.unlock() }
        code = value
    }

    var value: Int32 {
        lock.lock()
        defer { lock.unlock() }
        return code
    }
}

/// The blocking HTTP transport refuses the main thread, so all work runs on a background thread while main waits.
private func runOnBackgroundThread() -> Never {
    let arguments = Array(CommandLine.arguments.dropFirst())
    let exitCode = ExitCodeBox()
    let finished = DispatchSemaphore(value: 0)
    let worker = Thread {
        exitCode.set(run(arguments: arguments))
        finished.signal()
    }
    worker.start()
    finished.wait()
    exit(exitCode.value)
}

runOnBackgroundThread()
