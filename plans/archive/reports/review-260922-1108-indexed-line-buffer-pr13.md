# Adversarial review — PR #13 `fix/indexed-line-buffer` (`f76ddff`)

Reviewer: code-reviewer subagent. Date: 2026-09-22.
Worktree: `/Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/indexed-line-buffer`.
Read-only review. Worktree source unmodified (`git status --porcelain -- packages/ docs/` empty at finish).

Method legend: **[RAN]** = verified by executing something. **[READ]** = concluded by reading code.

Mutation harness: full copy of the package under
`/private/tmp/.../scratchpad/mut/` with a minimal `Package.swift` (kit + kit tests only).
That scratch package has **one pre-existing, path-dependent failure**
(`testSoftwareCursorGlyphLoadsCursorMotionReferenceImage`, missing repo-relative reference image);
it appears in every mutation run below and is unrelated to this change.

---

## Verdicts

### Claim 1 — "No behavior change." → **CONFIRMED**

**[READ]** `main` has exactly four mutation sites for `lines`/`lineOffsets` in the two renderers;
all four convert 1:1, in place, with no statement reordered:

| `main` site | HEAD site | conversion |
|---|---|---|
| `AccessibilitySnapshot.swift:551-552` (fixture, append + register) | `:550` | `appendIndexedLine` |
| `:1016-1017` (TreeRenderer.render, append + register) | `:1037` | `appendIndexedLine` |
| `:1040` (table-row continuation, append only) | `:1060` | `appendSpanLine` |
| `:1069` (renderSyntheticText, append only) | `:1094` | `appendSpanLine` |

Ordering around the table-row branch is byte-identical apart from the call: `appendIndexedLine`
still precedes `records[index] = record`, `identifierIndex[...]`, the `focusedSummary` assignment,
and the `kAXRowRole` early `return`; the `dropFirst()` loop and its `return` are untouched.
`records` is a dictionary, so append/record interleaving carries no ordering semantics anyway.
Consumption sites moved from `renderer.lines`/`renderer.lineOffsets` to
`renderer.buffer.lines`/`renderer.buffer.offsets` (`:419-420`, `:576-577`) with no other change.

No `public`/`open` symbols added; `IndexedLineBuffer` is module-internal, reached from the test via
the existing `@testable import`. No force-unwraps, `try!`, or `as!` introduced (grepped the added
lines).

**[RAN]** Worktree suite green: `241 executed, 2 skipped, 0 failures` (`swift test`, 18.5 s).

### Claim 2 — "The new test is not vacuous." → **CONFIRMED** (with a defect, see H-1)

Four mutations applied to a scratch copy. All four are caught **only** by
`testSpanRowsDoNotShiftTheOffsetsOfTheIndexedRowsAroundThem`:

| Mutation | Caught? | Evidence |
|---|---|---|
| A. `offsets[index] = lines.count` (off-by-one) | **yes** | `XCTAssertEqual failed: ("[0: 1, 1: 4, 2: 5]") is not equal to ("[0: 0, 2: 4, 1: 3]")` |
| B. swap the two statements inside `appendIndexedLine` | **yes** | `("[1: 2, 2: 3, 0: -1]") is not equal to ("[1: 3, 2: 4, 0: 0]")` |
| C. `appendSpanLine` re-registers the last indexed element onto the span row | **yes** | `("[0: 2, 2: 4, 1: 3]") is not equal to ("[0: 0, 2: 4, 1: 3]")` + `row for index 0 mis-registered: Invoice #42` |
| E. fixture call site → `appendSpanLine` (no registration) | **yes**, but by PR #12's test, not the new one | `testTreeLineOffsetsMatchEveryElementRowFromARealRenderer: no treeLineOffsets entry for element index 0..3` |

**[RAN]** all four. The test is genuinely load-bearing for the buffer's internals.

### Claim 3 — "Sharing the implementation puts the live-AX `TreeRenderer` recording site under test." → **REFUTED**

Only the buffer is under test. `TreeRenderer`'s *choice of method* is completely uncovered.
**[RAN]** two mutations inside `TreeRenderer`, full suite green (only the pre-existing scratch
failure) in both:

- **D1** — table-row continuation loop changed from `buffer.appendSpanLine(text)` to
  `buffer.appendIndexedLine(index: index, text)` (`AccessibilitySnapshot.swift:1060`). Every table
  row's own offset would be silently reassigned to its last continuation row, which is precisely
  the compact-view corruption this PR exists to prevent. **Suite stays green.**
- **D3** — the primary indexed row changed from `appendIndexedLine` to `appendSpanLine`
  (`AccessibilitySnapshot.swift:1037`), i.e. the live-AX path stops registering offsets *entirely*.
  **Suite stays green.**
- **D2** — `renderSyntheticText` changed to `appendIndexedLine` (the "fix" the history note
  deliberately declines). **Suite stays green.** So nothing pins the decision the note argues for
  at length.

The refactor removes the *intra-call* gap between append and register. It does **not** put the live
recording site under test. What remains uncovered, plainly:

1. every `TreeRenderer` call-site method choice (indexed vs span);
2. `TreeRenderer`'s offsets vs its `lines` as actually produced from a tree;
3. the synthetic-text span decision;
4. `TreeRenderer`'s output end to end (unchanged from before — needs a real `AXUIElement`).

Only the **fixture** call-site choice is covered, by PR #12's test (mutation E).

### Claim 4 — "`renderSyntheticText` calling `appendSpanLine` preserves prior behavior exactly." → **CONFIRMED**

**[READ]** `git show main:...AccessibilitySnapshot.swift:1069` is a bare
`lines.append("\(String(repeating: "\t", count: depth))\(index) text \(text)")` with no
`lineOffsets` write anywhere in that function; `records[index] = ElementRecord(... isSyntheticText: true)`
follows in both versions. Same string, same position, no registration before or after. The change
is a rename of the operation plus a comment.

---

## Other checks

- **`private(set)` encapsulation is real.** **[READ]** grep across `Sources/` + `Tests/`: the only
  writes to `lines`/`offsets` are the two bodies inside `IndexedLineBuffer` (`:858`, `:865`); all
  external touches are reads (`:419-420`, `:576-577`, test `:1387-1398`). The unrelated
  `lines.append` hits at `:132-200` and in `OpenComputerUseCLI.swift` are local `[String]` vars in
  other functions. Compiler enforces this anyway.
- **History note vs code.** One claim is contradicted, one is loose:
  - **Contradicted:** *"this is the first coverage the live-AX recording site has ever had."*
    Refuted by D1/D3 above — the live site can be broken in the two most likely ways with the suite
    green. Correct wording is that the live site now shares a *tested implementation*, while its
    call sites remain uncovered.
  - **Loose:** *"The pair `lines.append(...)` / `lineOffsets[index] = lines.count - 1` no longer
    exists anywhere"* — it exists exactly once, inside `appendIndexedLine`. That is the intent, but
    "anywhere" is wrong as written.
  - Verified-true claims: the mutation result quoted in the note (`[2: 5, 0: 1, 1: 4]` vs
    `[0: 0, 1: 3, 2: 4]`) reproduces **[RAN]** (dictionary print order differs run to run; contents
    match); `241 executed / 0 failures / 2 skipped` reproduces **[RAN]**; the
    `testCompactViewHoistsFocusedElementAndIgnoresItsSyntheticTwin` observation is accurate
    **[READ]** — that test hand-authors `treeLineOffsets: [0: 0, 1: 1, 2: 2]` while index 2 is
    `isSyntheticText: true` (test file `:1235`, `:1245-1249`), an arrangement the renderer does not
    produce.
  - Minor: the "Files Modified" list omits the history note itself.

---

## Defects, ranked

**H-1 (High, test hygiene) — the new test aborts the whole xctest process on failure.**
`OpenComputerUseKitTests.swift:1395-1399` does `buffer.lines[offset]` with an unvalidated `offset`.
**[RAN]** under mutation A this traps (`Swift/ContiguousArrayBuffer.swift:695: Fatal error: Index out
of range`, `xctest ... exited with unexpected signal code 5`) and the run produces **no**
`Executed N tests` summary — every alphabetically later test is skipped silently, including PR #12's
`testTreeLineOffsetsMatchEveryElementRowFromARealRenderer`, which does catch that same mutation when
run in isolation. A guard failure this test is designed to detect therefore *hides* other failures.
Fix: guard the subscript, e.g.
`guard buffer.lines.indices.contains(offset) else { XCTFail("offset \(offset) out of range for index \(index)"); continue }`.
(Note: PR #12's test at `:1341` has the same shape and the same exposure.)

**M-1 (Medium) — Claim 3 as written will mislead the next reader.** The history note's "first
coverage the live-AX recording site has ever had" and the test's own comment ("this covers the
live-AX path that no test can drive directly") both overstate. D1 is a realistic edit — someone
adding an index to continuation rows — and lands green. Either soften both wordings, or add a
`TreeRenderer` seam (a rendering protocol / injectable element provider) so the call sites are
reachable. Recommend at minimum fixing the wording before merge; the seam is a separate piece of work.

**L-1 (Low) — `appendSpanLine` is a one-line wrapper that cannot fail.** Its value is documentation,
not enforcement: nothing stops a caller choosing the wrong method (D1/D2/D3). Acceptable as intent
signalling, but it should not be described as a safety mechanism.

**L-2 (Low) — mutation D2 is unguarded.** The history note spends a paragraph arguing that
synthetic text must not register an offset ("its text would vanish from the compact view"). No test
holds that line. If the reasoning is right, it is worth one assertion; if nobody writes it, expect a
future "fix" to flip it.

---

## Recommended actions

1. Fix H-1 (guard the subscript in the new test; consider the same at `:1341`).
2. Reword the "first coverage the live-AX recording site has ever had" claim in the history note and
   the matching test comment to say what is actually true: shared *implementation*, uncovered *call
   sites*. Fix the "no longer exists anywhere" phrasing.
3. Optional, separate change: a seam for `TreeRenderer` so D1/D3 become catchable, and a test
   pinning the synthetic-text span decision (L-2).

Nothing here blocks correctness of the shipped behavior — claims 1, 2 and 4 hold. The blocking-grade
problem is H-1 (a failing assertion silently truncating the suite); claim 3 is a documentation
defect, not a code defect.

## Unresolved questions

- Is `testCompactViewHoistsFocusedElementAndIgnoresItsSyntheticTwin` modelling an arrangement the
  renderer never produces acceptable long-term, or should the compact-view behavior for synthetic
  text be decided (D2) rather than deferred again?
- `python3` is killed (exit 137 / SIGKILL) in this agent session; perl was used instead. Same class
  of environment breakage as the recorded debug-CLI exit-141 issue — may affect other tooling.

Status: DONE_WITH_CONCERNS
Summary: Claims 1, 2 and 4 CONFIRMED with mutation and diff evidence; claim 3 REFUTED — the live-AX
`TreeRenderer` call sites remain fully uncovered (two realistic mutations there leave the suite green).
Concerns/Blockers: H-1 — the new test's unguarded `buffer.lines[offset]` traps and aborts the whole
xctest process on failure, masking every later test; and the history note's "first coverage the
live-AX recording site has ever had" is contradicted by mutations D1/D3.
