# Counsel: Track A plan, plan-validation direction-confirm gate

Mode: one-shot counsel, with no interview. Source was read at afb60fa in the Track A worktree, read-only. Claims with a `file:line` are verified; everything else is my judgement.

## Verdict

Approve the direction, with four plan edits before phase 01 starts. The plan implements Proposal A, the five corrections and decision 13 faithfully. It fixes the metric before any code, gives every lever its own commit and measurement, and chooses good pure-function test seams. The weak spots are specific: phase 01 introduces a new failure mode into single `element_index` clicks, two checks do not test what they claim, and the turns gate can pass without proving anything.

## Verified findings that need a plan edit

1. **Phase 01 can make an element_index click fail after a window change. Fix this before phase 01 runs.**
   - `hitTestElement` sends *window* points through `screenshotToGlobalPoint` (ComputerUseService.swift:1298-1300). Single element_index clicks call it during nearby hit-testing (:1161, with `includeNearbyHitTesting: true` at :669 and :686). That branch runs whenever the direct AX press fails.
   - Phase 01 makes `screenshotPixelSize` throw on a frame mismatch. The existing `try` compiles without complaint, so the throw is silent at build time.
   - Result: after a text-only action (no PNG in the cache), a resize or a new target window (for example, compose) makes a click that has no x/y fail with the "x/y coordinates refer to a screenshot…" error.
   - Fix: `hitTestElement` calls `windowPointToGlobalPoint` directly. This is one line and also removes the latent double scaling (plan Q6). Pin it with a grep invariant: only drag calls `screenshotToGlobalPoint`.
2. **The live batch check does not verify where the text landed.**
   - Phase 05 M5 says its guard checks that the search field holds `combio`. `bench/ocu-speed-bench.py` `batch()` checks only `Step 3 … : ok` and `isError`, and never calls `require_search_value`. A step reported as "ok" was posted, not necessarily delivered to the right place.
   - If typing outruns Mail's focus change, `combio` and Return go to the message list, where Return opens the selected message and marks it read. Fix: add `require_search_value` on the batch result, and run a first round of [cmd+option+f, type_text] with no Return.
3. **The phase 01 grep misses click, the most heavily weighted tool.** `grep 'refreshSnapshot(for: query), style: .actionResult'` matches 15 of the 16 action tails. The click tail at :774 spans several lines. Instead, assert that `style: .actionResult` appears only inside `finishAction`.
4. **The live-focus test covers the helper, not the wiring.** The `typingTargetElement` test would still pass if `typeText` passed `snapshot.focusedElement` straight into the helpers' new signatures. Add a grep invariant so that correction 1 is actually enforced: `typeText` calls `typingTargetElement`, and no helper call passes `focusedElement: snapshot.focusedElement`.

## Coverage of the acceptance criteria

- **swift test** (batch semantics, the text-only default, the disk cache's 0600 mode and key-change miss): covered by pure unit tests in phases 01, 05 and 06, and by the two-run checks. Good.
- **Server time −30%:** L2 covers it. However, click and set_value carry 7 of the 13 weight units, so the pooled weighted median sits in the low tail of the click samples. The cursor cap alone nearly passes it. Report a weighted mean next to it so the keyboard-path gains are visible.
- **jev:** covered by the unit test showing that a disk hit makes 0 `/tokenize` calls, plus L4.
- **Missing:** no run exercises `perform_actions` end to end through the dispatcher and the service before live Mail; L1 only checks the tool count. Add one fixture smoke case: click, type_text, press_key, plus a bad index to prove the batch stops at the first failure. Also, `summarize` silently drops error calls, so acceptance-grade runs should require zero errors.

## Over-scoped or low value

- **C3b (trim the settle to 0.1s).** The plan itself expects about 0 effect on M_server: the only real-app site is performSecondaryAction. Meanwhile it shortens the one value the batch needs to be long enough. Keep C3a and drop C3b. That is a trade-off against decision 5's "trim where safe", not a breach of the lock.
- **Phases 01, 02 and 06 "depend on 00".** They depend on it only for measurement. Code can start before the baseline session, because every commit is measured in order later.

## Top risks

1. Batch steps outrun Mail, now that the implicit ~1.3s settle between steps is gone. This is mitigated only once finding 2 is fixed.
2. The AX multi-read changes the rendered text in WebKit views. The M4 render bracket is the only guard; it is a good one.
3. `J_warm` ≤ 3s stays borderline: the walk plus about 1.9s of model time. The escalation path in the plan is right.
4. L3 turns come from 3 headless runs. They vary with the model, and the gate passes vacuously if the headless B0 control is already ≤ 9.

## Decisions for the user

1. **hitTestElement.** Fix the geometry (recommended), or keep today's mis-scaling through a non-throwing path.
2. **Turns gate.** Is it absolute ≤ 9 only, or must it also be ≤ 50% of the headless B0 control? Either way, pin `--model` for both runs, and state whether the headless agent sees HEAD's SKILL.md and usage.md (`--strict-mcp-config` passes only the MCP instructions).
3. **Settle.** Drop C3b. If M5 fails, pre-authorize raising the shared constant to at most 0.3s, instead of stopping for escalation.
4. **Smoke suite.** Track A owns main.swift:199-200 and adds one fixture `perform_actions` case.
5. **Unchanged behaviour.** Keep compact get_app_state and single type_text unchanged in PR A (plan Q3 and Q4): neither affects a gate, and both change behaviour. Accept the 7-day jev TTL.

## Work checklist

- [ ] Phase 01: add the hitTestElement change and its grep invariant, and replace the Task 1.5 grep.
- [ ] Phase 05: add the focus-wiring grep. Fix the bench `batch()` guard and add the 2-step warm-up round.
- [ ] Phase 03: drop C3b, or mark it optional, and record the pre-authorized settle range.
- [ ] Phase 08: add the relative turns gate, the pinned model, the zero-error rule and the fixture batch smoke case.

## Unresolved questions

1. Does AXPress fail on Mail's search field, which would force the nearby hit-test path? If so, finding 1 hits the combio flow directly.
2. Does the open-computer-use skill load in the headless `claude -p` run, and from which checkout?
3. Should a batch with element_index steps fail closed on a snapshot-cache miss, when there is no state the agent actually saw, instead of building a fresh pinned snapshot?
