# Code Review — PR #10 `feat/compact-actionable-snapshot`

Date: 2026-09-22 · Reviewer: code-reviewer (read-only) · Base: `origin/main` (5 commits ahead, 0 behind)

## Scope

- Files: `AccessibilitySnapshot.swift`, `ComputerUseService.swift`, `ComputerUseToolDispatcher.swift`, `ToolDefinitions.swift`, `OpenComputerUseKitTests.swift`, `docs/ARCHITECTURE.md`, `.gitignore`, 3 added docs/plan/report md.
- LOC: +812 / −10.
- Verification run: `swift test` in `packages/OpenComputerUseKit` — **239 tests, 0 failures, 2 skipped** (build clean, no warnings surfaced).
- Paths read at branch tip via worktree `.claude/worktrees/compact-actionable-snapshot`.

## Overall Assessment

The critical invariant holds. Indices are **not** renumbered: `treeLineOffsets[index] = lines.count - 1` is written on the same statement pair as the `lines.append` in both renderers, and the compact path reads rows back by that offset and never re-derives a number. Every row a compact line starts with is the full-tree `element_index`.

The real risks are elsewhere: (a) the actionability filter removes elements that `click`/`scroll` can genuinely actuate via the coordinate fallback, and (b) the critical invariant itself has **zero** test coverage because every new test hand-writes `treeLineOffsets` instead of driving a renderer.

Note on the brief: `optionalBool` **throws** on unparseable input (`ComputerUseToolDispatcher.swift:216`), it does not return nil. The premise in the task description is stale — commit `851bcf0` changed it. Throwing is the right call and is tested.

## Critical Issues

None. No index off-by-one, no auth/data-exposure change, no breaking change to existing callers (`compact` defaults to `false`; `required` stays `["app"]`, asserted by `testGetAppStateExposesCompactFlagAsBoolean`; adding a `SnapshotTextStyle` case breaks nothing — no exhaustive switch on it exists outside the kit).

## High Priority

### H1 — Compact drops elements that `click` and `scroll` can actuate

`AccessibilitySnapshot.swift:255` — `guard !actuating.isEmpty else { return false }` removes every element with no AX action. But both action tools fall back to synthetic events:

- `ComputerUseService.swift:717` — `scroll` uses the element's `AXScroll*ByPage` *if present*, else `performScrollEvent(at: point)` on the element's frame. An `AXScrollArea` that advertises no actions (common in AppKit) is dropped from compact, so the agent sees no scroll target at all.
- `ComputerUseService.swift:543` — `click` falls back to `performNonAXClickFallback(at: targetPoint,…)` for any element with a frame. A no-action `AXGroup`/`AXCell` sidebar row is clickable in practice, but invisible in compact.

The inline comment at `AccessibilitySnapshot.swift:270-274` claims scroll areas are deliberately not dropped, but that exemption is scoped only to the static-text branch below it; the top-level zero-action guard still removes them. Comment and behavior disagree.

Suggested: keep an element when `record.localFrame != nil` and its role is in a scrollable/container set (`AXScrollArea`, `AXWebArea`, `AXTable`, `AXOutline`), independent of advertised actions. At minimum, correct the comment so it does not assert a protection the code does not provide.

### H2 — The `treeLineOffsets` invariant is untested

Every compact test constructs `AppSnapshot` through the local `makeSnapshot` helper with literal offsets (e.g. `treeLineOffsets: [0: 0, 1: 1, 2: 2]`). No test drives `TreeRenderer` or the fixture renderer at `AccessibilitySnapshot.swift:551`. Consequence: an off-by-one introduced in `lineOffsets[index] = lines.count - 1`, or a future edit that appends a line between the two statements, passes the whole suite — the exact defect class the feature is built to avoid.

The fixture renderer path is testable without AX permissions (it builds from `FixtureElementState`, no live `AXUIElement`). Add one test that builds a fixture snapshot through the real builder and asserts, for each index `i`, that `treeLines[treeLineOffsets[i]!]` starts (after indent strip) with `"\(i) "`.

### H3 — Indexless-row absorption swallows *indexed* synthetic-text rows

`renderSyntheticText` (`AccessibilitySnapshot.swift:1062-1069`) appends a row that **does** carry its own element index and its own `records[index]` entry, but deliberately never registers a `lineOffsets` entry. The span logic (`AccessibilitySnapshot.swift:184-199`) ends a span at the next *registered* offset, so a synthetic child row is absorbed into its parent's compact line:

```
12 group Frame: (…) — 13 text Draft saved
```

The leading index (12) is still correct, so this is not an actuation bug, but the embedded `13` reads exactly like an `element_index` and is a plausible misfire target for a model scanning the line. The comment at `:183` ("Rows that carry no index of their own belong to the element above them") is factually wrong for this case. Either register synthetic offsets and filter them at selection time, or strip the leading `N text ` prefix when folding a synthetic row into a parent's line.

## Medium Priority

### M1 — Static-text filter can hide a real control

`AccessibilitySnapshot.swift:276-278` keeps `AXStaticText` only when `meaningfulRawActions` is non-empty, and that helper ignores `AXPress`, `AXConfirm`, `AXShowMenu` (`AccessibilitySnapshot.swift:1846-1853`). A genuine control that reports role `AXStaticText` and advertises **only** `AXPress` is dropped. The rationale ("whatever handles the click carries its own press, and that ancestor is kept") is sound for web content but is an assumption about non-web AppKit/Electron UIs, not a guarantee. `testCompactViewKeepsStaticTextThatAdvertisesANonUbiquitousAction` only proves the `AXIncrement` case. Measured benefit was 280→210 rows on one page; worth re-checking whether that 25% is worth the tail risk.

### M2 — `compact` still pays for a full window screen capture

`AccessibilitySnapshot.swift:393` captures the window PNG unconditionally; `ComputerUseService.swift:1948` only suppresses it at serialization. The tool description sells compact as "much cheaper per call", which is true for tokens but not for latency or ScreenCapture TCC traffic. Caveat: the capture is not purely decorative (`ComputerUseService.swift:1674` consumes `snapshot.screenshotPNGData` for another path), so skipping it needs the flag threaded into `SnapshotBuilder` rather than a one-line change. Worth a follow-up, not a blocker.

### M3 — Unrelated file committed on this branch

`docs/exec-plans/active/20260922-local-decision-model-mcp-tool.md` (+64) is a plan for a different feature (local decision model MCP tool) and has nothing to do with compact snapshots. Scope creep; should be split out. `.gitignore` gaining `.impeccable/` is also unrelated tooling, though harmless.

### M4 — Header count can overstate printed rows

`AccessibilitySnapshot.swift:176` prints `ordered.count`, but the loop below can `continue` on `guard var line = span.first` when every line in a span is empty after stripping. Currently unreachable (a rendered element line always begins with its index), but it makes the header a claim the loop does not guarantee. Same area: `.filter { !$0.isEmpty }` runs *before* `span.first` is taken (`:190-193`) — if the element's own row ever rendered blank, the first continuation row would be promoted and the line would start with the **wrong** index. That is the off-by-one class this PR exists to prevent; take `span.first` before filtering to make it structurally impossible rather than incidentally safe.

## Low Priority

- `rowStarts.first { $0 > offset }` (`:188`) is a linear scan inside the per-element loop → O(n²), n ≤ `maxNodeCount` (1200). ~1.4M int comparisons worst case, negligible, but a `sorted` binary search or a precomputed next-offset map is a two-line change.
- `docs/ARCHITECTURE.md` lists `AXTextField` / `AXTextArea` / `AXComboBox` as always kept, omitting `AXTextView` and `AXSecureTextField` which the code also keeps (`AccessibilitySnapshot.swift:288-294`).
- Comment density in `compactActionableLines` and `isActionableForCompactView` is very high (roughly 1:1 with code) and two comments are now inaccurate (H1, H3). Long rationale comments that drift are worse than none.

## Edge Cases Checked

| Case | Result |
|---|---|
| Index renumbering in compact | Not renumbered — offsets recorded at append site in both renderers |
| Focused-first reordering shifting indices | No — `[focusedIndex] + rest.sorted()` reorders rows only |
| Focused element matching its synthetic twin | Handled; `isSyntheticText` skipped, `.min()` breaks dictionary-order nondeterminism (`:296-299`) |
| AXRow continuation rows (`:1040`) | Absorbed into the row's span as intended |
| Empty actionable set | Explicit fallback line, no crash |
| Non-strict-weak-ordering sort trap | Avoided by partitioning rather than a custom comparator |
| Existing callers / schema compat | `compact` optional, `required` unchanged, no external exhaustive switch |
| Bool encodings from MCP clients | `true` / `"true"` / `1` accepted; anything else throws, tested |
| Linux/Windows parity | Go runtime (`apps/OpenComputerUseLinux/main.go:1168`) does not declare `compact`; documented as a known gap in ARCHITECTURE.md — acceptable |
| Debug CLI `snapshot` subcommand | Does not expose compact (`MacOSAppAgentProxy.swift:470`, `OpenComputerUseMain.swift:62`); MCP path uses `.call` → dispatcher, so the feature works in production |

## Recommended Actions

1. **H2** — add one renderer-driven test asserting `treeLines[treeLineOffsets[i]]` starts with `i` (fixture builder path, no AX needed). Blocking: the invariant is currently unguarded.
2. **H1** — keep frame-bearing scrollable/container roles regardless of advertised actions, or correct the comment that claims they are already protected.
3. **H3** — strip or suppress the synthetic row's leading `N text ` when folding it into a parent line.
4. **M4** — take `span.first` before the empty filter.
5. **M3** — move `docs/exec-plans/active/20260922-local-decision-model-mcp-tool.md` off this branch.
6. **M2** — follow-up ticket: thread `compact` into `SnapshotBuilder` to skip the window capture.

## Metrics

- Tests: 239 executed, 0 failures, 2 skipped (1 requires `OPEN_COMPUTER_USE_RUN_SKY_CLICK_LIVE_TEST=1`).
- New tests: 15 (13 compact rendering + 2 flag parsing) — all behavioral, no phantom tests; but all render-layer tests use hand-authored offsets (H2).
- Type safety: no `Any` widening introduced beyond the pre-existing `[String: Any]` argument dict; no lint suppressions; no force unwraps added.
- Build: clean.

## Unresolved Questions

1. Was the 280→210 row reduction from the static-text filter (M1) measured against a *task success* baseline, or only token count? If only tokens, the tail risk of hiding a mislabelled control is unquantified.
2. Is the coordinate-click fallback (H1) considered in scope for "actionable"? The tool description says "elements that expose an accessibility action", which is honest — but an agent reading the compact header ("N of M elements") will reasonably assume the omitted M−N are not targets.
3. Should the debug CLI `snapshot` subcommand gain `--compact` for parity with the MCP tool, or is CLI/MCP divergence intentional?
