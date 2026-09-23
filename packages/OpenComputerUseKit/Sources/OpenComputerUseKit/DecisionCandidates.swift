import Foundation

// Candidate extraction for the decision-model advisory tool.
//
// Turns the two strings `get_app_state` already renders (the full tree and the compact actionable view) into
// labelled pages of candidates. Pure string processing: no AX, no network, no state.
//
// Fail-open invariant: every heuristic here keeps a candidate whenever its evidence is incomplete or ambiguous
// (unknown locale, unusual tree shape, goal wording that touches the rule's subject). A focused candidate is never
// dropped. Every drop is attributed to exactly one named `DecisionPruneRule`, so the pruned-target rate can be
// measured per rule.

/// One actionable row from the compact view, addressable by the full tree's `element_index`.
public struct DecisionCandidate: Equatable, Sendable {
    public let elementIndex: Int
    /// Compact row with the leading "<index> " and any trailing " (focused)" removed. Never contains "\n".
    public let rowText: String
    public let isFocused: Bool

    public init(elementIndex: Int, rowText: String, isFocused: Bool) {
        self.elementIndex = elementIndex
        self.rowText = rowText
        self.isFocused = isFocused
    }
}

/// The deterministic rule that removed a candidate. Raw values are the stable names used in eval reports.
public enum DecisionPruneRule: String, CaseIterable, Sendable, Codable {
    case disabled
    case menuBar = "menu_bar"
    case scrollBarPart = "scroll_bar_part"
    case windowChrome = "window_chrome"
    case duplicateClose = "duplicate_close"
    case overflow
}

public struct DecisionCandidatePage: Equatable, Sendable {
    /// labels[i] names candidates[i]; labels are a prefix of DecisionCandidateBuilder.labelAlphabet.
    public let labels: [String]
    /// Ascending elementIndex.
    public let candidates: [DecisionCandidate]
}

public struct DecisionCandidateSet: Equatable, Sendable {
    public let pages: [DecisionCandidatePage]
    /// elementIndex -> the first rule that removed it.
    public let dropped: [Int: DecisionPruneRule]
    /// Number of rows parsed from the compact view before pruning.
    public let actionableCount: Int

    /// Every elementIndex offered to the model, across all pages, ascending.
    public var offeredIndices: [Int] {
        pages.flatMap { $0.candidates.map(\.elementIndex) }.sorted()
    }
}

public enum DecisionCandidateBuilder {
    /// "A"..."Z" then "a"..."z": exactly 52 unique single-token labels.
    public static let labelAlphabet: [String] =
        (UInt8(ascii: "A")...UInt8(ascii: "Z")).map { String(UnicodeScalar($0)) }
        + (UInt8(ascii: "a")...UInt8(ascii: "z")).map { String(UnicodeScalar($0)) }
    public static let pageSize: Int = 52
    /// One page per decision in v1; anything ranked beyond it is reported as `.overflow`.
    public static let defaultMaxPages: Int = 1

    private static let compactHeaderPrefix = "Compact actionable view:"
    private static let trailerPrefixes = ["Selected text:", "The focused UI element is"]
    private static let focusedSuffix = " (focused)"
    private static let stopwords: Set<String> = [
        "a", "an", "the", "to", "of", "in", "on", "at", "for", "and", "or", "into", "from", "with", "by", "is",
        "it", "this", "that", "my", "me", "please", "then",
    ]
    private static let traitVocabulary: Set<String> = [
        "selected", "expanded", "disabled", "settable", "string", "boolean", "float",
    ]
    private static let menuWords: Set<String> = ["menu", "menus", "menubar"]
    private static let scrollBarPartPhrases = [
        "scroll bar", "value indicator", "increment arrow", "decrement arrow", "increment page", "decrement page",
    ]
    private static let windowChromePhrases = ["close button", "minimize button", "zoom button", "full screen button"]
    /// Goal words that keep window chrome: the control names themselves, plus the window or display it acts on
    /// ("get rid of this window", "fill the entire display").
    private static let windowChromeWords: Set<String> = [
        "close", "minimize", "minimise", "zoom", "fullscreen", "full", "screen", "window", "windows", "display",
    ]

    // MARK: - Parsing

    /// Rows after the `Compact actionable view:` header, up to the first empty line. Returns `[]` when the header is
    /// missing (for example the no-actionable-elements message). Lines that do not start with an index are ignored.
    public static func parseCompactRows(_ renderedCompact: String) -> [DecisionCandidate] {
        let lines = renderedCompact.components(separatedBy: "\n")
        guard let headerIndex = lines.firstIndex(where: { $0.hasPrefix(compactHeaderPrefix) }) else { return [] }

        var candidates: [DecisionCandidate] = []
        for line in lines[(headerIndex + 1)...] {
            if line.isEmpty { break }
            guard let (index, rest) = splitIndexedRow(line) else { continue }
            let trailingFocus = rest.hasSuffix(focusedSuffix)
            let isFocused = trailingFocus || rest.contains(focusedSuffix + " ")
            let rowText = trailingFocus ? String(rest.dropLast(focusedSuffix.count)) : rest
            candidates.append(DecisionCandidate(elementIndex: index, rowText: rowText, isFocused: isFocused))
        }
        return candidates
    }

    /// Matches `^(\d+)(?: (.*))?$`, returning the index and the (possibly empty) remainder.
    private static func splitIndexedRow(_ line: String) -> (Int, String)? {
        let digits = line.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, let index = Int(digits) else { return nil }
        let rest = line.dropFirst(digits.count)
        if rest.isEmpty { return (index, "") }
        guard rest.first == " " else { return nil }
        return (index, String(rest.dropFirst()))
    }

    /// Lower-cased tokens split on anything that is not a Unicode letter or digit, minus 1-character tokens and
    /// stopwords. Used for both the goal and candidate rows.
    public static func goalTokens(_ goal: String) -> Set<String> {
        var tokens: Set<String> = []
        var current = String.UnicodeScalarView()
        func flush() {
            let token = String(current)
            current.removeAll()
            if token.count > 1, !stopwords.contains(token) { tokens.insert(token) }
        }
        for scalar in goal.lowercased().unicodeScalars {
            if CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) {
                current.append(scalar)
            } else {
                flush()
            }
        }
        flush()
        return tokens
    }

    // MARK: - Menu-bar region

    /// Index of the first element of the trailing depth-0/1 menu-bar region of the full tree, or `nil` when the tree
    /// shape does not clearly show one (fail-open: `nil` disables the `menu_bar` rule).
    public static func menuBarStartIndex(renderedFull: String) -> Int? {
        let tree = treeSection(renderedFull)
        let rows: [(depth: Int, index: Int?)] = tree.map { line in
            (depth(of: line), splitIndexedRow(line.trimmingCharacters(in: .whitespaces))?.0)
        }
        guard let maxIndex = rows.last(where: { $0.index != nil })?.index else { return nil }

        // Walk backward over sequentially indexed, shallow lines.
        var expected = maxIndex
        var runStart = rows.count
        while runStart > 0 {
            let row = rows[runStart - 1]
            guard row.index == expected, row.depth <= 1 else { break }
            runStart -= 1
            expected -= 1
        }

        for position in runStart..<rows.count {
            let row = rows[position]
            guard row.depth == 0, let index = row.index, index > 0 else { continue }
            let hasDeeperLineBefore = rows[..<position].contains { $0.depth >= 1 }
            let regionLineCount = rows.count - position
            if hasDeeperLineBefore, (2...40).contains(regionLineCount) { return index }
        }
        return nil
    }

    /// Lines after the 2 header lines, excluding the trailing "Selected text:" / "The focused UI element is" block.
    private static func treeSection(_ renderedFull: String) -> ArraySlice<String> {
        let lines = renderedFull.components(separatedBy: "\n")
        guard lines.count > 2 else { return [] }
        var body = lines[2...]
        if let lastEmpty = body.lastIndex(of: ""), lastEmpty + 1 < body.endIndex,
           trailerPrefixes.contains(where: { body[lastEmpty + 1].hasPrefix($0) })
        {
            body = body[..<lastEmpty]
        }
        return body
    }

    /// Leading tabs plus leading spaces / 4.
    private static func depth(of line: String) -> Int {
        let indent = line.prefix { $0 == "\t" || $0 == " " }
        let tabs = indent.filter { $0 == "\t" }.count
        return tabs + (indent.count - tabs) / 4
    }

    // MARK: - Build

    /// Parses, prunes, ranks, and pages the candidates. Deterministic for identical inputs.
    public static func build(
        goal: String,
        renderedFull: String,
        renderedCompact: String,
        maxPages: Int = defaultMaxPages
    ) -> DecisionCandidateSet {
        precondition(maxPages >= 1, "maxPages must be at least 1")
        let candidates = parseCompactRows(renderedCompact)
        let goalSet = goalTokens(goal)
        let rowTokens = candidates.map { goalTokens($0.rowText) }

        let menuStart = menuBarStartIndex(renderedFull: renderedFull)
        let menuRuleActive: Bool = {
            guard let menuStart, goalSet.isDisjoint(with: menuWords) else { return false }
            let regionTokens = zip(candidates, rowTokens)
                .filter { $0.0.elementIndex >= menuStart }
                .reduce(into: Set<String>()) { $0.formUnion($1.1) }
            return goalSet.isDisjoint(with: regionTokens)
        }()

        var normalizedCounts: [String: Int] = [:]
        for candidate in candidates { normalizedCounts[normalized(candidate.rowText), default: 0] += 1 }

        var dropped: [Int: DecisionPruneRule] = [:]
        var survivors: [(candidate: DecisionCandidate, score: Double)] = []
        for (candidate, tokens) in zip(candidates, rowTokens) {
            let rule: DecisionPruneRule? = {
                if candidate.isFocused { return nil }
                let text = candidate.rowText
                if firstTraitGroup(in: text)?.contains("disabled") == true { return .disabled }
                if menuRuleActive, let menuStart, candidate.elementIndex >= menuStart { return .menuBar }
                if scrollBarPartPhrases.contains(where: { startsWithRolePhrase(text, $0) }) { return .scrollBarPart }
                if windowChromePhrases.contains(where: { startsWithRolePhrase(text, $0) }),
                   goalSet.isDisjoint(with: windowChromeWords)
                {
                    return .windowChrome
                }
                if tokens.contains("close"), normalizedCounts[normalized(text), default: 0] >= 2,
                   !goalSet.contains("close")
                {
                    return .duplicateClose
                }
                return nil
            }()
            if let rule {
                dropped[candidate.elementIndex] = dropped[candidate.elementIndex] ?? rule
            } else {
                survivors.append((candidate, score(goal: goalSet, row: tokens)))
            }
        }

        let ranked = survivors.sorted { lhs, rhs in
            if lhs.candidate.isFocused != rhs.candidate.isFocused { return lhs.candidate.isFocused }
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.candidate.elementIndex < rhs.candidate.elementIndex
        }.map(\.candidate)

        var pages: [DecisionCandidatePage] = []
        for (pageNumber, start) in stride(from: 0, to: ranked.count, by: pageSize).enumerated() {
            let chunk = ranked[start..<min(start + pageSize, ranked.count)]
            if pageNumber >= maxPages {
                for candidate in chunk { dropped[candidate.elementIndex] = .overflow }
                continue
            }
            let sorted = chunk.sorted { $0.elementIndex < $1.elementIndex }
            pages.append(DecisionCandidatePage(labels: Array(labelAlphabet.prefix(sorted.count)), candidates: sorted))
        }

        return DecisionCandidateSet(pages: pages, dropped: dropped, actionableCount: candidates.count)
    }

    // MARK: - Rule helpers

    /// Tokens of the first `(…)` group whose comma-separated, trimmed tokens are all trait words, if any.
    private static func firstTraitGroup(in text: String) -> [String]? {
        var remainder = text[...]
        while let open = remainder.firstIndex(of: "(") {
            let afterOpen = remainder[remainder.index(after: open)...]
            guard let close = afterOpen.firstIndex(of: ")") else { return nil }
            let tokens = afterOpen[..<close].split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if tokens.allSatisfy({ traitVocabulary.contains($0) }) { return tokens }
            remainder = afterOpen[afterOpen.index(after: close)...]
        }
        return nil
    }

    /// `text` starts with `phrase` followed by a space, "(", or the end.
    private static func startsWithRolePhrase(_ text: String, _ phrase: String) -> Bool {
        guard text.hasPrefix(phrase) else { return false }
        let next = text.dropFirst(phrase.count).first
        return next == nil || next == " " || next == "("
    }

    /// Lower-cased with whitespace runs collapsed to one space.
    private static func normalized(_ text: String) -> String {
        text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// |G ∩ R| + 0.5 × |{g ∈ G, |g| ≥ 4 : ∃ r ∈ R, |r| ≥ 4, r ≠ g, one is a prefix of the other}|.
    private static func score(goal: Set<String>, row: Set<String>) -> Double {
        let exact = goal.intersection(row).count
        let partial = goal.filter { g in
            g.count >= 4 && row.contains { r in r.count >= 4 && r != g && (r.hasPrefix(g) || g.hasPrefix(r)) }
        }.count
        return Double(exact) + 0.5 * Double(partial)
    }
}
