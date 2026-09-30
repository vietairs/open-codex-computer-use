# Counsel: Track A (PR A speed) brainstorm, design-approval gate

Mode: one-shot counsel with no interview, because there is no user in this context. All source claims were read at HEAD `afb60fa` in the main checkout, read-only.

## Verdict

Approve Proposal A, but only after one required correction and four smaller ones. Reject B, C and D for the reasons the brainstorm gives. The analysis is mostly accurate, and I verified its key claims. However, A's "pinned snapshot" batch breaks the flagship pattern (click field, type, Return) unless focus is read live. Separately, the −30% median target is at real risk for type_text and press_key. Decide how that metric is defined before any code is written.

## What I verified

- The snapshot cache does persist across calls. The proxy keeps one socket connection per MCP session (MacOSAppAgentProxy.swift:121-136), and each connection owns one `StdioMCPServer` (:363-365). `currentSnapshot` has no freshness check (ComputerUseService.swift:961-967). So assumption 1 holds: the pre-action snapshot costs nothing, and no code change is needed there.
- Cursor travel is fixed at 1.429s: `calibratedTravelDuration` ignores distance (CursorMotionModel.swift:493-494). `animateMove` time-scales the spring (SoftwareCursorOverlay.swift:365-367), so a cap only compresses the motion.
- D is wrong for the reason given: the `--calls` loop calls `callToolAsResult` once per step, and every step refreshes (ComputerUseToolDispatcher.swift:344-366).
- The coordinate-scale hazard is real, but its size depends on the window. The PNG is resized to at most 1280 px (AccessibilitySnapshot.swift:96) and then shrunk further by a byte-budget loop (:721-751). So the pixel scale depends on content and cannot be recomputed later. Carrying the last PNG size forward is therefore the only correct design. For large windows, "double the coordinates" overstates the error, but a click still misses.

## Required corrections before approval

1. **Read focus live in batch steps (blocking).** `typeText` does not use live focus. It uses `snapshot.focusedElement` (ComputerUseService.swift:884-886, 1535-1557), which is captured when the snapshot is built (AccessibilitySnapshot.swift:528-536).
   - In a pinned batch, step 2 (`type_text`) would see the focus from before step 1's click. Depending on what that element was, the text is either appended by AXValue to the wrong element, or the app is activated through the Stage Manager branch (:888-899), which the user sees.
   - The rule should be: the pinned snapshot resolves `element_index` only. Focus, window bounds, and frames for any coordinate fallback must be read live.
   - Add a unit test that fails if `type_text` in a batch reads focus from the pinned snapshot.
2. **Keep the start-of-turn `get_app_state` in the guidance.** The proposed wording ("call it when you have no current state") removes the only freshness mechanism, because the cache never expires. Keep "at the start of each assistant turn, since the user may have changed the app", and drop only "after every action".
3. **Update MCPServer.swift line 10.** That line lists the tools. If `perform_actions` is missing from it, hosts that use tool_search may never find the tool. Track B will edit the same line, so warn the main loop about the conflict.
4. **Update both tool-count tests.** They are OpenComputerUseKitTests.swift:256 and DecisionAdvisorTests.swift:437, not just one. Also update the tool lists in docs/ARCHITECTURE.md and SKILL.md:14-16.
5. **Put the cursor cap in the overlay, not the model.** Apply `min(duration, cap)` in `SoftwareCursorOverlay.animateMove` only. Leave `CursorMotionModel.swift` and the tests at :2639 and :2652 byte-identical, and add one new test for the cap. That model is a recovered copy of the upstream one, so leaving it alone keeps upstream syncs clean and keeps the parity tests meaningful.

## What to avoid

- **Do not refactor the dispatcher's six existing cases in PR A.** Argument parsing happens inline in `callTool` (:81-126), so A needs a new `ActionStep.parse`. It will duplicate about 40 lines of argument mapping, but the append-only contract with Track B allows that. Record routing the single-action cases through the parser as a follow-up after both PRs merge.
- **Do not add a snapshot TTL.** I agree with the brainstorm here.
- **Do not make travel non-blocking (option b).**
- **Do not credit decision 2's removal of the permission review to PR A.** That review alone cut about 1.3s of the 4.5s in-session time.

## Hidden risks and better alternatives

- **The −30% median target.** type_text and press_key have no cursor move, so they gain only 10–20%. If the combio flow is mostly typing and keys, A misses the target. The real remaining cost is the Mail AX walk, about 1.3s. The code reads attributes one IPC call at a time: there are 5 `AXUIElementCopyAttributeValue` sites and no `CopyMultipleAttributeValues`. Batching those reads is the largest untapped lever, and it would also speed up `get_app_state` and `decide_next_action`. It is not among decision 5's listed items, so it needs the user's approval as a contingency. It should not be added silently.
- **jev may never fill its cache.** The recommended fix is to persist letter progress as letters resolve, together with the sample-prompt tokens, and mark the table complete only when all 26 are distinct. A call that times out still saves its progress, so the table fills after a few calls. This stays inside the transport lock and adds no load on a server whose GPUs are already at 100%. Concurrent `/tokenize` does add that load.
- **Warm ≤3s is borderline even when jev is healthy.** The harness measured model-only warm time at 1.9s (test-260929-1720). Add the Mail walk and the call lands at roughly 2.9–3.2s. The multi-page stage-1 readouts are independent and run in sequence (DecisionAdvisor.swift:101-105). Running them concurrently would be a jev change beyond decision 4, so the user must approve it.
- **Disk cache staleness.** A disk cache stays stale for longer than the per-process memory cache. A tokenizer redeploy that `staleLetterCacheMessages` does not detect would persist until someone intervenes. Store `resolved_at` and treat old entries as a miss, for example after 7 days.
- **Lock contention.** A batch of up to 10 steps holds the process-wide env-override lock (MacOSAppAgentProxy.swift:507-540) for its whole run, which serializes other hosts' calls. That is acceptable, but document it.
- **Final snapshot failure.** If the final snapshot throws (for example, the window closed), still return the per-step lines. The batch result must never lose them.

## Check before approving

- The metric is defined in writing: server-side over direct stdio, per tool, using the combio call mix. The baseline is taken on `afb60fa` before any change, and the in-session figure is reported next to it.
- The 0.3s cursor cap is accepted as a visible UX change.
- The focus correction (item 1) is written into the plan's acceptance criteria.

## Unresolved questions

1. What is the combio flow's call mix (clicks versus type_text and press_key)? It decides whether A can reach −30% without batching AX attribute reads.
2. May PR A batch AX attribute reads, or run jev stage-1 pages concurrently, if the measured numbers miss? Both go beyond the listed decisions.
3. Should a single `type_text` also read focus live? That fixes stale-focus bugs, but it changes single-action behaviour.
4. What TTL should the jev disk cache use, if any?
