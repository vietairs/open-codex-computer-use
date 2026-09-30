# Phase 02 — Swift candidate extraction, deterministic pruning, paging, labels

Parallel group G1 (with 01, 03). No dependencies. **Tests-first:** a tester agent writes `DecisionCandidatesTests.swift`
from the Acceptance list and confirms it fails to compile or fails. A different implementer agent (opus) then writes
`DecisionCandidates.swift`.
Worktree: `/Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/decision-model`.

## Goal

Turn the two strings `get_app_state` already produces (full tree text and compact actionable text) into ≤ 4 pages of
≤ 52 labelled candidates. The pruning must be deterministic and fail-open, so the correct target is rarely dropped.
Every drop is attributed to a named rule, so phase 06 can measure the pruned-target rate per rule. This code is pure
string processing, with no AX, no network, and no state.

## Context (verified)

- Compact text shape (`AccessibilitySnapshot.swift:127-202`): line 1 `App=<ref> (pid N)`; line 2 `Window: "<title>", App: <name>.`;
  line 3 `Compact actionable view: N of M elements, screenshot omitted. element_index values match the full tree; …`
  (or the single line `(no actionable elements found; re-run without compact for the full tree)`). Then one row per element:
  `<index> <roleText>[ (<traits>)][ title …][ — span | span][ (focused)]`. Then optionally `""` followed by
  `Selected text: [...]` or `The focused UI element is …`.
- Full text shape: the same two header lines, then the tree rows, indented with tabs per depth
  (`AccessibilitySnapshot.swift:1034`). The fixture tree uses 4 spaces for depth 1 (`:547`). Then the same optional trailer.
  AXRow span texts are appended **without indentation** (`appendSpanLine(text)`, `:1082-1085`), so a depth-0 line is not
  necessarily a real element row.
- The menu bar is rendered by a second top-level `render(menuBar)` call at depth 0, after the window (`:403-409`).
  Menu-bar items render with an empty role word (`:1959-1961`) and suppress their children (`:1808-1809`). The
  `AXMenuBar` row itself may be elided, in which case its items appear at depth 0.
- Trait vocabulary, rendered in English as `(a, b)` right after the role text: `selected, expanded, disabled, settable, string, boolean, float`
  (`:1240-1285`).
- Role text is `AXRoleDescription` lower-cased (`:2008-2010`), so it is localized. Rules keyed on English role phrases
  fail open (keep) on other locales.
- Indices are assigned sequentially in render order, so indexed rows carry strictly increasing integers in line order
  (`nextIndex += 1`, `:970`, `:1101`).

## Signature

New file `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/DecisionCandidates.swift`:

```swift
public struct DecisionCandidate: Equatable, Sendable {
    public let elementIndex: Int
    /// Compact row with the leading "<index> " and any trailing " (focused)" removed. Never contains "\n".
    public let rowText: String
    public let isFocused: Bool
    public init(elementIndex: Int, rowText: String, isFocused: Bool)
}

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
    public var offeredIndices: [Int] { get }
}

public enum DecisionCandidateBuilder {
    public static let labelAlphabet: [String]      // "A"..."Z" then "a"..."z" — exactly 52, unique
    public static let pageSize: Int                // 52
    public static let defaultMaxPages: Int         // 4
    public static func parseCompactRows(_ renderedCompact: String) -> [DecisionCandidate]
    public static func menuBarStartIndex(renderedFull: String) -> Int?
    public static func goalTokens(_ goal: String) -> Set<String>
    public static func build(
        goal: String,
        renderedFull: String,
        renderedCompact: String,
        maxPages: Int = defaultMaxPages          // precondition(maxPages >= 1)
    ) -> DecisionCandidateSet
}
```

### Normative algorithm (implement exactly; tests pin it)

1. **Parse compact** (`parseCompactRows`): take the lines after the `Compact actionable view:` header up to (excluding) the
   first empty line. Each row matches `^(\d+)(?: (.*))?$`; non-matching lines are ignored. `isFocused` = the row ends with
   ` (focused)` (compact marker) **or** contains ` (focused) ` (fixture inline marker). `rowText` strips the index prefix
   and the trailing ` (focused)` only. If the header line is missing (for example, the no-actionable message), return `[]`.
2. **Tokens** (`goalTokens`, reused for rows): lower-case; split on any character that is not a Unicode letter or digit;
   drop tokens of length 1 and the stopwords
   `a an the to of in on at for and or into from with by is it this that my me please then`.
3. **Menu-bar start** (`menuBarStartIndex`): take the tree section, meaning the lines after the 2 header lines up to
   the last empty line if the text after it starts with `Selected text:` or `The focused UI element is`, else to the end.
   Depth = leading tabs + (leading spaces / 4). A line is *indexed* if its stripped text starts with an integer followed
   by a space or the end of the line. Let `maxIndex` = the integer on the last indexed line. Walk lines **backward** from
   the end while each line (a) is indexed, (b) has depth ≤ 1, and (c) carries exactly `expected` (starting at `maxIndex`,
   decrementing by 1 per line). Stop at the first violation. The *run* is the lines walked. Return the index of the first
   (earliest) depth-0 line in the run whose index > 0, **provided that** (i) at least one line before that line has depth ≥ 1,
   and (ii) the region (that line through the end) has 2…40 lines. Otherwise return `nil` (fail-open).
4. **Rules**, applied in this order to every parsed candidate; the first matching rule records the drop. A focused
   candidate is **never** dropped by any rule. "Role phrase" = `rowText` starts with the phrase followed by a space, `(`,
   or the end.
   - `disabled`: the first `(…)` group in `rowText` whose comma-separated, trimmed tokens are **all** in the trait
     vocabulary contains `disabled`.
   - `menu_bar`: `menuBarStartIndex` is non-nil, `elementIndex >= start`, **and** the goal tokens intersect neither
     `{"menu","menus","menubar"}` nor the union of row tokens of all candidates in the region.
   - `scroll_bar_part`: role phrase ∈ `scroll bar, value indicator, increment arrow, decrement arrow, increment page, decrement page`.
   - `window_chrome`: role phrase ∈ `close button, minimize button, zoom button, full screen button`, and the goal tokens
     do not intersect `{"close","minimize","minimise","zoom","fullscreen","full","screen"}`.
   - `duplicate_close`: the row tokens contain `close`, at least 2 candidates share the identical normalized `rowText`
     (lower-cased, whitespace collapsed), and the goal tokens do not contain `close`.
5. **Rank** the survivors by (isFocused desc, score desc, elementIndex asc). Here score = |G ∩ R| + 0.5 × |{g ∈ G, |g| ≥ 4 :
   ∃ r ∈ R, |r| ≥ 4, r.hasPrefix(g) || g.hasPrefix(r), r ≠ g}|, with G = goal tokens and R = row tokens.
6. **Page**: chunk the ranked list into pages of `pageSize`. Pages beyond `maxPages` are dropped with `overflow`. Within
   each page, sort the candidates by ascending `elementIndex` and assign `labelAlphabet[0..<count]`.

## Boundaries

```
TARGET:    packages/OpenComputerUseKit/Sources/OpenComputerUseKit/DecisionCandidates.swift        (new)
           packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/DecisionCandidatesTests.swift (new)
READ-ONLY: packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift,
           packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift
FORBIDDEN: AccessibilitySnapshot.swift (upstream-synced; compact output is a public contract);
           Package.swift, ToolDefinitions.swift, ComputerUseToolDispatcher.swift, ComputerUseService.swift, MCPServer.swift (phase 05);
           DecisionPrompt.swift, DecisionModelClient.swift (phase 04); scripts/** (phases 01/03/06);
           any new dependency; any AX / AppKit / network call in DecisionCandidates.swift (Foundation only);
           reading real-app snapshots from artifacts/ into tests (tests use synthetic text only)
```

## Acceptance

Command: `swift test --filter DecisionCandidatesTests`, then `swift test` (the whole suite stays green; baseline ≥ 233 tests).
Assertions (write these first; they must fail before `DecisionCandidates.swift` exists):

- `labelAlphabet.count == 52`, `Set(labelAlphabet).count == 52`, `labelAlphabet.first == "A"`, `[25] == "Z"`, `[26] == "a"`, `.last == "z"`.
- Parse: for
  `"App=com.example (pid 1)\nWindow: \"Sample\", App: Sample.\nCompact actionable view: 2 of 4 elements, screenshot omitted. element_index values match the full tree; re-run without compact for full context.\n1 button Send Secondary Actions: Press\n3 text field (settable, string) Message (focused)\n\nThe focused UI element is 3 text field."`
  → indices `[1, 3]`; `[1].isFocused == true`; `[1].rowText == "text field (settable, string) Message"`; `[0].rowText == "button Send Secondary Actions: Press"`.
- Parse: the `(no actionable elements found; …)` variant → `[]`.
- Parse: a row with a ` — ` span keeps the span in `rowText`.
- Parse fixture-style `2 button Increment (focused) ID: fixture-increment Frame: …` → `isFocused == true`.
- Disabled: `5 button (disabled) Save` → dropped `.disabled`; `6 button Save (disabled draft)` → kept (the paren group
  holds a non-trait token); focused + `(disabled)` → kept.
- `menuBarStartIndex`:
  - window at depth 0, children at depth 1–2, then `3 menu bar` (depth 0), `\t4 File`, `\t5 Edit` → `3`;
  - the same with the menu bar elided (`3 File`, `4 Edit` at depth 0) → `3`;
  - no menu bar (tree truncated; last lines at depth 2) → `nil`;
  - flat tree, every line at depth 0 (root elided) → `nil`;
  - fixture tree (4-space indent, single root) → `nil`;
  - a depth-0 span line `7 KB` in the middle of window content (not sequential) does not create a region → still `3` for
    the first case with that line inserted.
- Menu-bar rule: region `File`, `Edit`, goal `"click Save"` → both dropped `.menuBar`; goal `"rename the file"` → kept;
  goal `"open the Edit menu"` → kept.
- Scroll-bar parts: `increment page`, `value indicator`, `scroll bar` → dropped `.scrollBarPart`; `scroll area` → kept.
- Window chrome: `close button` dropped for goal `"save the report"`, kept for goal `"close this window"`.
- Duplicate close: three `button Close tab` rows → all dropped `.duplicateClose` for goal `"open settings"`; kept for
  `"close the docs tab"`; a single `button Close` is kept.
- Ranking/paging: 120 rows at indices 1…120, each `button Item N` except index 90 = `button Export PDF`, goal
  `"export as pdf"`: with `maxPages: 4` → 3 pages (52, 52, 16) and `90` is in page 0; with `maxPages: 1` → 1 page,
  68 rows dropped `.overflow`, `90` still offered; page 0's candidates are ascending by index and `labels == Array(labelAlphabet.prefix(52))`.
- Determinism: `build` called twice on the same inputs → `==`.
- `offeredIndices` == sorted union of all page candidates; `offeredIndices ∩ dropped.keys == ∅`;
  `offeredIndices.count + dropped.count == actionableCount`.

## Success criteria

All assertions pass. `DecisionCandidates.swift` imports only Foundation, is ≤ 300 lines (split a
`DecisionCandidateRules` helper only if it would exceed that), and has doc comments stating the fail-open invariant.

## Risks and rollback

- Heuristic 3 misfires on unusual trees → fail-open guards plus phase 06 per-rule attribution. Tuning happens only in
  phase 06, sequentially.
- Rollback: delete the two new files (nothing else references them until phase 04).

## Contract Rules

1. Implements to the SIGNATURE exactly. A signature that cannot work is a STOP, not a redesign — report it through the Failure Protocol.
2. Edits only within TARGET. Discovering that the change genuinely requires a FORBIDDEN file is a STOP with that finding, never a quiet widening.
3. Writes the acceptance assertions first where the plan says tests-first, confirms they FAIL, then implements until they pass.
4. Never weakens an assertion, never marks a test skipped, and never stubs an implementation to make one pass. A passing suite obtained this way is the specific failure this whole contract is built to prevent — cheap tiers reward-hack checkable specs more than strong ones do, so the escalation path exists precisely for the moment the spec looks unsatisfiable.
5. On any failed Verify, follows the `## Failure Protocol` already in the phase file. That is the backchannel; using it is correct behaviour, not an admission of failure.

## Failure Protocol

On any failed Verify or Acceptance step (non-zero exit, failed assertion, or output that differs from what is specified
here), the executor stops reasoning about the fix on its own. It spawns the `kongming` agent with: this phase file's path,
the exact failing command and its full output, `git diff -- <TARGET files>`, and the approaches already tried. It waits
for the advice, applies it within TARGET only, and re-runs the failed step. If `kongming` is unavailable, or its advice
needs a FORBIDDEN file or a changed Signature, the executor STOPS and reports `Status: BLOCKED` with the evidence. It never
silently retries the same approach and never weakens an assertion to get green.
