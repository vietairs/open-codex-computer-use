# PR #23 review, round 3 (final): e89601c..1070014

Scope: 1 commit (1070014), 11 files, +257/−21. Worktree `.claude/worktrees/continuous-computer-use-speed`, HEAD 1070014 (matches the PR head).

## Verification
- `swift test --scratch-path /private/tmp/claude-501/ocu-speed-build-review` (unsandboxed): **600 tests, 2 skipped, 0 failures**. Matches the PR body.
- `gh pr checks 23`: **5/5 pass** at 1070014 (audit-dependencies, check-docs, check-hygiene, repo-checks, swift).
- `git diff --shortstat main...1070014`: 53 files, +6288/−510. Matches the body.

## Claims checked

1. **Boolean rejected before the numeric casts in shared `positiveInt`.** Confirmed (`ComputerUseToolDispatcher.swift:292-296`). The other callers are `text_limit` (`optionalTextLimit`), `max_tree_nodes` and `max_tree_depth` (`optionalPositiveInt`). All three are integer-typed in the schema (`positiveIntegerProperty`/`textLimitProperty`). None of them could sensibly take a boolean. Before this change, JSON `true` became 1 through `as? Int` (1 tree node, or a 1-char text limit), which is a silent misread, not a feature. Refusing it is correct. JSON numbers never decode as a CFBoolean, so real integers are not affected. A Swift-native `Bool` passed as `Any` was already refused on the old NSNumber branch. The tests build their input with `JSONSerialization`, so the boolean case is a real test, not a false pass. They cover both the single-call and the batch path.
2. **Schema text.** Confirmed: "Number of clicks, 1 to 3. Defaults to 1."
3. **Invariant tests.** `writeCallStatements()` collects each write call until its parentheses balance (up to 12 lines). The focus allowlist is now `ClickTextEntryFocus.swift:writeClickedTextEntryFocus` plus the opt-in `raiseAppWindowViaAccessibility`, with a count==1 assert on the helper. The new scan for `AXMainWindow`/`AXFocusedWindow`/`AXFrontmost` writes is limited to the opt-in sites. I grepped the sources. Every `kAXFocusedWindowAttribute` use is a `copyElement` read, and the only AXFocused writes are `ClickTextEntryFocus.swift:71` and `InputSimulation.swift:381` (opt-in). Both allowlists match reality.
4. **Title-bar button filter.** `excludingWindowTitleBarButtons` is applied inside the private `descendantClickCandidates(for:snapshot:sideActionScope:)`. That one function feeds both the auto descendant loop (`:1616`) and the hit-test descendant loop (`:1642`), so both paths are covered. A direct element_index click on a close or minimize button goes through `performPreferredClick(on: record)` at `:1610` and is not filtered. That is correct. The direct press of `hitRecord` (`:1630`) is also not filtered. The hit points are the center and leading-at-midY of the target frame (`localClickActionPoints`), not the title bar, so this is not a real exposure for a window target.
5. **Speed cost of the subrole read.** It adds one `kAXSubroleAttribute` read per *actionable* child, and only in the descendant fallback, which runs after the preferred press has already failed. Each child already costs children + actions + position/size reads, so the extra read is a small share of that walk and does not touch the snapshot or render hot path. Acceptable for the speed goal.
6. **Background-only rule.** Nothing in the delta activates, raises or unminimizes anything. The new filter makes the rule stricter: auto clicks can no longer minimize, zoom or full-screen a window.

## Critical
None.

## Important
None.

## Suggestion
- **S1: PR body is stale on CI.** The body says "CI: 5/5 green at e89601c; re-running at 1070014". CI is now 5/5 green at 1070014. Update that line.
- **S2: PR body does not mention the wider boolean change.** "Input checks" and "click_count range" only mention `click_count`. The same `positiveInt` change also refuses JSON `true`/`false` for `text_limit`, `max_tree_nodes` and `max_tree_depth` on `get_app_state`, where `true` used to be read as 1. The change is correct, but it is a small contract tightening. Add a half-sentence to "Human actions required".
- **S3: Multi-line scan is untested.** Both allowlisted focus writes are single-line calls, so no test proves that `writeCallStatements()` catches a write whose attribute is on a later line. The main-window/frontmost scan has no positive control at all, because its expected set is empty. A small test that feeds a synthetic multi-line source string through the collector would pin this. It would need a small refactor so the collector takes lines as input. Non-blocking.
- **S4: Known blind spot in the source scan.** A wrapper that takes the attribute as a parameter (like `InputSimulation.setBoolAttribute(named:on:)`) is only caught at call sites that pass the attribute token as a literal. If a future wrapper is called with the attribute held in a variable, the scan misses it. Document this or accept it. It is not a defect today.

## Verdict
**Approve.** The delta does what it claims, stays background-only, and tests are green locally (600/2 skipped/0 failures) and in CI (5/5). The only things left are PR-body accuracy nits (S1, S2) and test-hardening suggestions.

## Unresolved questions
- None blocking.
