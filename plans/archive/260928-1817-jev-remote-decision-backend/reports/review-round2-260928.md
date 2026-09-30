# Review round 2 — PR #21 remote jev decision backend (head 9ee0421)

Scope: `git diff origin/main...HEAD` (19 files, +1752/-47). Paths are relative to
`packages/OpenComputerUseKit/Sources/OpenComputerUseKit/` unless prefixed.
Verification run (outside sandbox, since SwiftPM needs `sandbox-exec`): `swift test --filter 'Decision|ToolDefinition|MCPServer'` gives 153 tests
with 0 failures. `swift build` of the root package, including the `DecisionModelEval` product, is clean.

## Verdict
**0 blockers.** Every round-1 fix listed below is correct. The findings below are non-blocking. The one to act on
first is N1, a liveness risk on high-RTT links.

## Round-1 fixes: verified
| Round-1 item | Status | Evidence |
|---|---|---|
| Correctness H1: missing label scored 0 | Fixed. Parser fails closed on any missing offered label | `DecisionJevClient.swift:56-62`; tests `DecisionJevClientTests.swift:244,259` |
| Correctness H2: remote offered only 26 | Fixed. `maxPages = 2` is wired in the service, and a stage-2 test runs through the jev client | `DecisionJevClient.swift:89`, `ComputerUseService.swift:~563-566`, test `DecisionJevClientTests.swift:365` |
| Correctness M1 / Security M2: unbounded first call | Fixed. An absolute deadline is threaded into the client and resolver. Each request checks it and uses timeout `min(5, remaining)`. The transport bounds the whole call, not just idle time (`DecisionModelTransport.swift:~87-91`) | `DecisionJevPrompt.swift:95-106`, `DecisionJevClient.swift:135-155` |
| Correctness M2: rows duplicated, letters overloaded | Fixed. Operation rows are unlettered; the target prompt has no Screen rows block | `DecisionJevPrompt.swift:143-168` |
| Security M1: egress not documented | Fixed, with a wording error (see D1) | `docs/SECURITY.md` "What actually leaves the machine" |
| Security L1: symlink / TOCTOU | Fixed. Single `open(O_NOFOLLOW\|O_NONBLOCK\|O_CLOEXEC)`, then `fstat` type/uid/mode/size and a bounded read loop on the same fd | `DecisionRemoteBackend.swift:128-173` |
| Security L4: key redaction | Fixed. `description`, `debugDescription` and `customMirror` all redact the key | `DecisionRemoteBackend.swift:70-80`; test `DecisionJevClientTests.swift:407` |
| Security L5: degenerate letter map | Fixed. Distinct ids and token_strs are required | `DecisionJevPrompt.swift:87-91` |
| Security L2: per-call backend selection | Documented as accepted (dismissed) | SECURITY.md / decision-model.md |

Thread-safety of the letter cache is fine. `cache` is read and written only under `lock`
(`DecisionJevPrompt.swift:51-65`). Concurrent cold callers do duplicate work and the last writer wins with identical
data, which is harmless. The cache stores only successful resolutions.

Llama path: no regression. It still uses page size 52, maxPages 1, the verifier before the first request, and the
same error prefix. The transport still requires `http` to a loopback host (`DecisionModelTransport.swift:~53-57`), and
`DecisionModelEndpoint.fromEnvironment` still refuses https.

## Non-blockers

### N1 (High). On links with RTT of about 150 ms or more, remote resolution can never finish, and nothing recovers from that
- Resolution makes 27 sequential `/tokenize` POSTs (`DecisionJevPrompt.swift:72-86`). Each POST builds a fresh
  ephemeral `URLSession` that is then invalidated (`DecisionModelTransport.swift:80-84,97`), so there is no connection
  reuse. Each request likely pays TCP + TLS + HTTP, about 3 RTT.
- All 27 requests must fit inside the same 12 s `overallDeadline` (`ComputerUseService.swift:~552`). At about 150 ms RTT
  that is 27 × 0.45 s ≈ 12.2 s, so `tokenize` throws `deadlineExceeded` (`DecisionJevPrompt.swift:96-97`).
- A failed resolution is deliberately not cached, and the 26 letters resolved so far are thrown away
  (`DecisionJevPrompt.swift:59`). The next call starts again from zero and fails the same way. The remote backend then
  returns "did not answer within 12 seconds" on every call for the life of the agent.
- A cold 2-page call has an even smaller margin, because it also needs 6 `/v1/completions` requests after the 27.
- Fix options:
  1. Cache letters incrementally, so progress survives a deadline.
  2. Give resolution its own budget outside the per-call deadline, for example a one-time warm-up.
  3. Reuse one session for the resolution burst.
- The pipelined option is not verifiable without a live endpoint. Latency to vm100 is unknown.

### N2 (Medium). Stale letter cache can never be evicted
- The cache key is `base_url|model` (`DecisionJevPrompt.swift:37`) and entries are never removed.
- Because the parser now fails closed, a tokenizer redeploy under the same model name makes every call fail with
  "offered label missing from top_logprobs" or "generated text is not an offered label" until the agent restarts.
- Fix: evict `cacheKey` when a completion parse fails with one of those two readout errors.

### N3 (Medium). The service-level remote branch is untested
- No test calls `ComputerUseService.decideNextAction` with `BACKEND=remote`. `grep decideNextAction( Tests/` returns
  nothing, and `remoteBackendConfigURL` has no caller.
- Untested behaviours: a config error maps to `invalidArguments`; the sidecar verifier is skipped; pageSize 26 and
  maxPages 2 are passed through (`ComputerUseService.swift:~517-566`). A swapped arm there would pass CI.

### N4 (Low). Public protocol requirement changed: a source break for any out-of-tree conformer
- `DecisionModelTransport.postJSON` requirement changed to the 5-argument form (`DecisionModelTransport.swift:10-13`).
  The 4-argument extension does not satisfy the new requirement.
- In-repo conformers were updated (the 3 test doubles) and the eval harness still builds.
- `OpenComputerUseKit` is a declared library product (`Package.swift:12`). The release note mentions https but not
  the signature change.
- `DecisionAdvisor.advise(client:)` and `DecisionCandidateBuilder.build(pageSize:)` remain source-compatible (defaulted
  and existential).

### N5 (Low). Error mapping and message accuracy
- `DecisionRemoteBackend.swift:130-135`: any `open` failure other than ELOOP (EACCES, ENOTDIR, EMFILE) is reported as
  "no remote-backend config file at …".
- `:144-145`: a FIFO or device is reported as "not a symlink". Both messages mislead when debugging.
- A missing file becomes `invalidArguments` (`ComputerUseService.swift:~533-536`), while llama "not configured" becomes
  `stateUnavailable`. The history note claims both report "the same way".

### N6 (Low). Audit labels in test comments break the stable-artifact rule
- `DecisionJevClientTests.swift:361` has "H2:", `:406` has "(fix 8)", and `:~425` has "(fix 5)". Replace them with
  plain descriptions of the behaviour.

### N7 (Low, carried over). The transport still enforces no per-caller policy
- `https` to any host is allowed for every caller (round-1 security L3). It is not exploitable today, because the llama
  endpoint parser refuses https. It is optional hardening.

## Doc accuracy
- **D1 (Low)** `docs/SECURITY.md` ("What actually leaves the machine") says screen rows are sent "plus that page's
  `/tokenize` calls". This is wrong on two counts:
  - `/tokenize` only ever sends the fixed `samplePrompt` ("warm up"; `DecisionJevPrompt.swift:136-141`), never screen
    text.
  - It runs once per process per backend on a cache miss, not once per page.
- **D2 (Low)** `decision-model.md` "What it is" says the tool "runs one or two forward passes". A remote call runs 2 per
  page, and up to 6 completions plus 27 tokenize calls when the cache is cold.
- **D3 (Low)** The history note (`docs/histories/2026-09/20260928-1846-...md`, Wiring bullet) says remote "reports
  `.stateUnavailable`/`.invalidArguments` the same way `llama` does". The code maps every remote config failure to
  `invalidArguments`.
- **Accurate**, verified against code:
  - ARCHITECTURE deadline paragraph
  - SECURITY loader/transport bullets
  - Listing gate (`ToolDefinitions.swift:178-183`)
  - 26/52 candidate counts

## Unresolved questions
- Is the jev engine started with `--max-logprobs >= 26`? vLLM's default is 20. If it is not raised, every target call
  with more than 20 labels gets HTTP 400 (fail-closed, but the backend is useless on busy windows).
  `DecisionJevClient.swift:145` sends `logprobs: labels.count`, which can be up to 26.
- Real RTT from the Mac to vm100's HTTPS front. This decides whether N1 is theoretical or immediate.
- Do vLLM `/tokenize` `token_strs` (from `convert_ids_to_tokens`) equal the completion `top_logprobs` keys (decoded) for
  bare letters after `\n\n` on the served tokenizer? If they differ, every call now fails closed, which is safe but
  leaves the backend dead. Only a live check can confirm this.
