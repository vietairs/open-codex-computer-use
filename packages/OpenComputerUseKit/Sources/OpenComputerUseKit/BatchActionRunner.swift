import Foundation

/// One step of a `perform_actions` batch. Every step carries exactly the arguments of the matching single tool,
/// minus `app`: the batch acts on one app.
enum ActionStep: Equatable {
    case click(elementIndex: String?, x: Double?, y: Double?, clickCount: Int, mouseButton: String, clickMethod: ClickMethod)
    case typeText(text: String)
    case pressKey(key: String)
    case setValue(elementIndex: String, value: String)
    case scroll(direction: String, elementIndex: String, pages: Double)
    case performSecondaryAction(elementIndex: String, action: String)

    static let allowedToolNames: [String] = [
        "click", "type_text", "press_key", "set_value", "scroll", "perform_secondary_action",
    ]

    var toolName: String {
        switch self {
        case .click: return "click"
        case .typeText: return "type_text"
        case .pressKey: return "press_key"
        case .setValue: return "set_value"
        case .scroll: return "scroll"
        case .performSecondaryAction: return "perform_secondary_action"
        }
    }

    var elementIndex: String? {
        switch self {
        case let .click(elementIndex, _, _, _, _, _): return elementIndex
        case .typeText, .pressKey: return nil
        case let .setValue(elementIndex, _): return elementIndex
        case let .scroll(_, elementIndex, _): return elementIndex
        case let .performSecondaryAction(elementIndex, _): return elementIndex
        }
    }

    /// One short line naming the step. It never echoes typed text or set values, which may be private.
    var summary: String {
        switch self {
        case let .click(elementIndex, x, y, _, _, _):
            if let elementIndex {
                return "click element_index=\(elementIndex)"
            }
            if let x, let y {
                return "click x=\(Int(x)) y=\(Int(y))"
            }
            return "click"
        case .typeText:
            return "type_text"
        case let .pressKey(key):
            return "press_key key=\(key)"
        case let .setValue(elementIndex, _):
            return "set_value element_index=\(elementIndex)"
        case let .scroll(direction, elementIndex, _):
            return "scroll element_index=\(elementIndex) direction=\(direction)"
        case let .performSecondaryAction(elementIndex, action):
            return "perform_secondary_action element_index=\(elementIndex) action=\(action)"
        }
    }
}

enum BatchStepOutcome: Equatable {
    case ok
    case failed(String)
    case notRun
}

struct BatchActionReport: Equatable {
    let steps: [ActionStep]
    let outcomes: [BatchStepOutcome]

    var hasFailure: Bool {
        outcomes.contains { outcome in
            if case .failed = outcome {
                return true
            }
            return false
        }
    }

    /// "Step 1 click element_index=12: ok" / "Step 3 press_key key=Return: failed: <message>" /
    /// "Step 4 click element_index=40: not run"
    var stepLines: [String] {
        zip(steps, outcomes).enumerated().map { offset, pair in
            let (step, outcome) = pair
            let status: String
            switch outcome {
            case .ok: status = "ok"
            case let .failed(message): status = "failed: \(message)"
            case .notRun: status = "not run"
            }
            return "Step \(offset + 1) \(step.summary): \(status)"
        }
    }
}

/// Pure sequencing for `perform_actions`: no accessibility, no snapshots. The service supplies what happens before
/// and during each step; this type decides order, stopping, and how the result reads.
enum BatchActionRunner {
    static let maxSteps = 10

    /// `element_index` values, as given, that are absent from `knownIndices`, in step order.
    static func unknownElementIndices(in steps: [ActionStep], knownIndices: Set<Int>) -> [String] {
        steps.compactMap { step in
            guard let elementIndex = step.elementIndex else {
                return nil
            }
            if let parsed = Int(elementIndex), knownIndices.contains(parsed) {
                return nil
            }
            return elementIndex
        }
    }

    /// Read-only when any click uses `sky_click`, so the final refresh never activates an app that click avoided.
    static func mostRestrictiveRecoveryPolicy(for steps: [ActionStep]) -> SnapshotRecoveryPolicy {
        let usesSkyClick = steps.contains { step in
            if case let .click(_, _, _, _, _, clickMethod) = step {
                return clickActionSnapshotRecoveryPolicy(for: clickMethod) == .readOnly
            }
            return false
        }
        return usesSkyClick ? .readOnly : .allowActivation
    }

    /// Runs steps in order. For each one `beforeEachStep(i)` runs, then `perform(i, step)`; the first throw from
    /// either marks step i failed with `errorText(error)` and every later step not run. Never observes state.
    static func run(
        steps: [ActionStep],
        beforeEachStep: (_ index: Int) throws -> Void,
        perform: (_ index: Int, _ step: ActionStep) throws -> Void
    ) -> BatchActionReport {
        var outcomes = [BatchStepOutcome](repeating: .notRun, count: steps.count)
        for (index, step) in steps.enumerated() {
            do {
                try beforeEachStep(index)
                try perform(index, step)
                outcomes[index] = .ok
            } catch {
                outcomes[index] = .failed(errorText(error))
                break
            }
        }
        return BatchActionReport(steps: steps, outcomes: outcomes)
    }

    /// The step lines, a blank line, then the final state text (and its image, when one is attached).
    /// A failed or skipped final read keeps the step lines and says why the state is missing.
    static func result(
        report: BatchActionReport,
        finalState: Result<ToolCallResult, Error>?,
        notReadReason: String?
    ) -> ToolCallResult {
        let header = report.stepLines.joined(separator: "\n")

        switch finalState {
        case let .success(state):
            let stateText = state.primaryText ?? ""
            let images = state.content.filter { $0.dictionary["type"] as? String != "text" }
            return ToolCallResult(
                content: [.text(header + "\n\n" + stateText)] + images,
                isError: report.hasFailure || state.isError
            )
        case let .failure(error):
            return .text(header + "\n\nFinal state unavailable: " + errorText(error), isError: true)
        case nil:
            return .text(header + "\n\nFinal state not read: " + (notReadReason ?? "unknown reason"), isError: true)
        }
    }

    /// The same text the tool dispatcher shows for this error.
    static func errorText(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
}
