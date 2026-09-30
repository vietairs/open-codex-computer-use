# Correctness review — remote jev decision backend (2026-09-28)

Scope: uncommitted diff in worktree `.claude/worktrees/jev-remote-decision-backend` (branch
`feat/jev-remote-decision-backend`) vs plan `plans/260928-1817-jev-remote-decision-backend/plan.md`.
Lens: correctness only. Paths below are relative to `packages/OpenComputerUseKit/`.
Tests run: `swift test --filter 'Decision|ToolDefinition|MCPServer'` → 143 tests, 0 failures (the sandbox blocks
SwiftPM's `sandbox-exec`, so this ran outside it).

## High

### H1. When labels are missing, the parser sets them to 0, which reports false high confidence (margin up to 1.0)
Confidence: medium-high.
- `Sources/.../DecisionJevClient.swift:51-65` maps each label through `letterMap[label].tokenStr` into `top_logprobs`.
  Any label it does not find becomes probability 0. The chosen label falls back to `token_logprobs[0]` (lines 54-60).
- Under the documented engine contract (`processed_logprobs`, `allowed_token_ids` = the n offered ids,
  `logprobs: n`), every offered label MUST appear in `top_logprobs`. A missing label is therefore a contract
  violation, not a normal case. When every other label is missing, the chosen label gets p=1.0 and margin=1.0. That is
  above `recommendedMinMargin` 0.72 (`DecisionAdvisor.swift:47`), so the host is told it may auto-follow advice that
  carries no information.
- Concrete trigger: vLLM's `/tokenize` `return_token_strs` returns `convert_ids_to_tokens` strings. For byte-level BPE
  these are raw pieces (`ĠA`, `Ċ`). Completion `top_logprobs` keys are *decoded* text (` A`). If a letter token is ever
  a space- or byte-marked piece, no `tokenStr` lookup ever hits. Every non-chosen label then goes missing, and every
  answer comes back at margin 1.0. For Qwen, a bare letter after `\n\n` decodes as `A` on both sides, so today this
  is latent. It depends entirely on the tokenizer and prompt suffix, and nothing checks it at resolve time.
- The test fake hides this. `Tests/.../DecisionJevClientTests.swift:27-32` uses `Ġ`-style strings for the base
  tokens but `" " + letter` for the letter `token_str`, and the completion fixtures key on `" A"`. So it assumes
  `token_strs` and `top_logprobs` share a representation, which is exactly the assumption in question.
- Fix: in the jev parser, fail closed (`readout("offered label missing from top_logprobs")`) when any offered label is
  missing, since the engine guarantees full coverage. Or at least fail when `missingLabels.count == labels.count - 1`
  and `labels.count > 1`. Optionally, at resolve time, reject a `tokenStr` that starts with `Ġ`/`Ċ`/`▁`.

### H2. The production jev path offers only 26 candidates and never pages; the 30-candidate "stage 2" test does not cover it
Confidence: high.
- `DecisionCandidates.swift:64` sets `defaultMaxPages = 1`. `ComputerUseService.swift:~538` calls `advise(..., pageSize:
  pageSize)` without `maxPages`, so the jev path runs with maxPages=1. With pageSize 26, candidates ranked 27-52 are
  now marked `.overflow` (`DecisionCandidates.swift:254-257`) and never offered. The llama path offered them (page
  size 52). On a busy window (>26 actionable survivors), the correct target can be dropped silently for the remote
  backend only.
- The plan's acceptance ("page size 26 with 30 candidates → 2 pages + stage 2") is satisfied only by
  `DecisionAdvisorTests.testAdviseWithPageSize26And30CandidatesProducesTwoPagesPlusStageTwo`. That test passes
  `maxPages: 2` explicitly and drives the *llama* `DecisionModelClient` with grammar assertions. It never exercises
  `DecisionJevClient` or the production maxPages, so multi-page stage 2 on the jev client has zero coverage. If it did
  run in production, it would cost 2×(pages+1) remote calls against a 12 s deadline (see M1).
- Fix: decide explicitly. Either pass `maxPages: 2` for remote (keeps 52-candidate coverage parity; 6 completions per
  decision), or document that remote offers 26. Then add an advisor test that uses `DecisionJevClient` +
  `FakeJevTransport` with 30 candidates at the production maxPages.

## Medium

### M1. The first remote call ignores the time bound; the ~17 s guarantee no longer holds
Confidence: high.
- `DecisionAdvisor.swift:9-10,87` checks `overallDeadline` only before each *readout*. For jev, one readout does a lazy
  letter resolution (`DecisionJevPrompt.swift:59-75`, 27 sequential `/tokenize` POSTs) plus 2 completions, each
  bounded at 5 s (`DecisionJevClient.swift:88`). Worst case for the first call: 29×5 = 145 s. After that, 10 s per
  readout, and a readout that starts at t=11.9 s can run to ~22 s.
- `URLSessionDecisionModelTransport` creates a fresh ephemeral session per request (`DecisionModelTransport.swift:~81`),
  so each of the 29 requests pays a full TCP+TLS handshake over WAN. At a realistic 100-150 ms RTT, the first call takes
  roughly 8-13 s.
- On a background MCP thread, nothing bounds this. On the main thread, `runOffMainThread` gives up at 17 s and returns
  `deadlineExceeded` while the work continues in the background (the cache still fills, which is harmless).
- Fix: check a deadline inside `resolveLetters` (pass `now`/start through, or give the resolver its own budget).
  Update the header comment in `DecisionAdvisor.swift` and the docs to state the remote bound. Consider resolving
  letters with one batched request if the engine allows it.

### M2. The target prompt lists every screen row twice; the operation prompt reuses the letters A-G for two things
Confidence: high (code); impact on model quality unverified.
- `DecisionJevPrompt.swift:126-128` passes `options: screenRows(page:)`, and `prompt(...)` (lines 139-146) always
  emits `Screen rows:\n<rows>` as well. The target prompt therefore carries the identical labelled rows under both
  "Screen rows:" and "Options:". That doubles input tokens (26 rows × up to `maxRowCharacters`) and departs from the
  plan's `[Screen rows:…]` (optional) shape.
- In the operation prompt, screen rows are labelled `A:`, `B:`… and the operation options are also `A:`…`G:`. The model
  sees two meanings for one letter in a single prompt. A tokenizer-level `allowed_token_ids` mask cannot resolve that
  ambiguity.
- Fix: omit the Screen rows block in `targetPrompt`. In `operationPrompt`, render rows unlabelled (or with `-`), or
  match whatever `jev_client.py` actually sends. Verify against the reference client, because the engine was tuned
  on that shape.

### M3. The advisor treats a missing operation distribution as a count check only (already existed, now reachable remotely)
Confidence: low-medium. `DecisionAdvisor.swift:133-138` zips `allCases` with `operationProbabilities`. The jev parser
always returns 7 entries, so this is fine today. Noted only because the jev client builds operation labels
independently from the prompt (`DecisionJevClient.swift:110` vs `DecisionJevPrompt.swift:120-122`). Both derive from
`allCases`, so they are consistent now; a future reordering of one without the other would silently mislabel. No
action required beyond keeping them sourced from `allCases`.

## Low

- L1. The letter cache never invalidates within the agent's lifetime (`DecisionJevPrompt.swift:18-54`, key =
  `base_url|model`). If the server redeploys a different tokenizer under the same model name, the cached ids go stale
  and every call fails with "generated text is not an offered label" until the agent restarts. Consider evicting the
  cache entry when parse fails with that error.
- L2. Concurrent first calls both miss the cache and each run 27 tokenize requests (`resolve()` releases the lock
  before resolving). The duplicate work is harmless and the last writer wins with identical data. It is acceptable,
  but the comment should say so.
- L3. `tokenize` accepts any `NSNumber` as an id (`DecisionJevPrompt.swift:91-94`), including JSON `true`/`1.7`,
  which become 1. Tighten with `CFNumberIsFloatType`/`CFGetTypeID` checks, as the rest of the parser does if
  applicable.
- L4. The parser accepts generated text with surrounding whitespace (`DecisionJevClient.swift:36`), while the
  `tokenStr` keys are exact. If the text were ` A`, the chosen label would resolve but its `top_logprobs` key might
  not, which falls into H1.
- L5. Apple lists `Authorization` among the headers URLSession "reserves". Setting it on `URLRequest` works in
  practice, but the URLProtocol-stub test (`DecisionModelClientTests.swift` `testPostJSONAcceptsHTTPSToAnyHost…`)
  cannot prove that the real CFNetwork stack sends it. Worth one manual smoke test against the real endpoint.
- L6. Listing gate: an unknown `BACKEND` value together with a valid llama URL still lists the tool
  (`ToolDefinitions.swift:179-181`, because `llamaConfigured` is true), and the call then fails. That is consistent
  with fail-closed, but `testToolDefinitionsListedExcludesDecideNextActionForAnUnknownBackend` only covers the no-URL
  case.

## Llama sidecar path: regression check
- The llama branch in `ComputerUseService.decideNextAction` keeps the same endpoint parse, error prefix,
  `sidecarVerifier.verify(port:)` before the first request, page size 52, and maxPages 1. The added
  `DecisionBackendSelection.resolve` runs first, but for `llama` it only reads the URL key to check emptiness. The
  only new failure is an explicitly set invalid BACKEND value. No regression found.
- Transport: `http` still requires a loopback host. `https` is new for every caller, but the llama endpoint
  validation (`DecisionModelClient.swift:69`) still refuses https, so the llama path cannot reach it.
- Env forwarding: `sanitizePeerEnvironment` forwards `OPEN_COMPUTER_USE_*` keys (`MacSessionGuard.swift:64-66`), so
  `…_BACKEND` reaches the agent and needs no allowlist change.

## Test gaps that hide real bugs
1. No service-level test of the `.remote` branch in `ComputerUseService.decideNextAction`: config error mapped to
   `invalidArguments`, sidecar verifier skipped, pageSize 26 passed. `remoteBackendConfigURL` has no test caller.
2. The advisor multi-page test uses the llama client and maxPages 2 (H2).
3. `FakeJevTransport` treats `token_strs` and `top_logprobs` keys as one representation (H1).
4. No test covers the deadline across the first-call resolution (M1).

## Unresolved questions
- What exact prompt shape does `jev_client.py` send (rows in the target call? labels on rows in the operation
  call?) (M2)
- Is the engine's `--max-logprobs` really ≥26? vLLM's default is 20. A 26-label page would get HTTP 400 if not.
- Is dropping candidates 27-52 for remote intended (H2)?
