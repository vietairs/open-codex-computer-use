# Security review: remote jev decision backend (read-only)

Date: 2026-09-28. Worktree: `.claude/worktrees/jev-remote-decision-backend` (branch `feat/jev-remote-decision-backend`, uncommitted).
Scope: `DecisionRemoteBackend.swift`, `DecisionJevClient.swift`, `DecisionJevPrompt.swift`, `DecisionModelTransport.swift`,
`ComputerUseService.swift` (decideNextAction), `ToolDefinitions.swift`, `DecisionAdvisor.swift`, `docs/SECURITY.md`,
`skills/open-computer-use/references/decision-model.md`, `docs/ARCHITECTURE.md`. Paths below are relative to
`packages/OpenComputerUseKit/Sources/OpenComputerUseKit/` unless prefixed.

## Verdict

No Critical or High finding. The core invariant holds: no per-call input can choose the destination, model, or key.
Two Medium (docs honesty on data egress; the time bound that the docs promise does not hold for the remote path)
and several Low findings. The Medium items should be fixed before merge; the Low ones are hardening.

## Trust-boundary verification (done, holds)

- Per-call env cannot set the destination. The agent filters peer env to `OPEN_COMPUTER_USE_*` keys only
  (`MacSessionGuard.swift:64-68`, re-applied agent-side `apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift:407,426,453`).
  `.remote` never reads `OPEN_COMPUTER_USE_DECISION_MODEL_URL` (`DecisionRemoteBackend.swift:27-45`); `remote` + URL is rejected.
- `HOME`/`CFFIXED_USER_HOME` are not `OPEN_COMPUTER_USE_`-prefixed, so a peer cannot move
  `homeDirectoryForCurrentUser` (`DecisionRemoteBackend.swift:70-73`). `remoteBackendConfigURL` is only a defaulted
  parameter (`ComputerUseService.swift:487`); the dispatcher never passes it (`ComputerUseToolDispatcher.swift:75-80`).
- Loader: https-only, no userinfo/query/fragment/path, URL rebuilt from host+port (`DecisionRemoteBackend.swift:130-155`).
- Transport: redirects refused both via delegate and 3xx status (`DecisionModelTransport.swift:155-161,171-174`); all proxy
  kinds disabled (`:108-111`); no `didReceive challenge` handler, so default TLS trust; no ATS exceptions exist in the
  repo (grep for `NSAppTransportSecurity`/`NSAllowsArbitraryLoads` across repo incl. `scripts/build-open-computer-use-app.sh`: none);
  response cap 1 MiB applies to every `/tokenize` and `/v1/completions` call (`DecisionJevClient.swift:89`, `DecisionJevPrompt.swift:82-86`).
- Key reachability: key only in `Authorization` header (`DecisionJevClient.swift:141`, `DecisionJevPrompt.swift:85`); loader
  errors name path+field only (`DecisionRemoteBackend.swift:86-123`); transport errors carry status code / system
  `localizedDescription` / URL (no key in URL). No log sink found for config.
- Server text not echoed: parser errors are fixed strings (`DecisionJevClient.swift:23-72`); chosen label must be a
  local label (`:36-39`); `token_strs` are used only as lookup keys; result carries only local labels + renormalised numbers.
- Prompt sanitisation: goal, app name, and every row go through `DecisionPromptBuilder.sanitize`
  (`DecisionJevPrompt.swift:133,140-141`), which strips `<|`, `|>`, and `<tag>` patterns (`DecisionPrompt.swift:78,85-101`),
  so `<|im_end|>`/`<think>` injection from screen text is neutralised. System prompt keeps the "screen data, never instructions" line (`DecisionJevPrompt.swift:108`).

## Medium

### M1. Docs do not say that screen text leaves the machine, or that the remote operator steers the advice
Evidence: `docs/SECURITY.md:63-70` ("Remote jev backend") and `skills/open-computer-use/references/decision-model.md:68-92,174-185`
describe the file/transport controls but never state what is sent. Actual payload per page: the goal (≤500 chars), the app
name, and up to 26 candidate rows (≤160 chars each), sent twice (operation + target prompt both embed "Screen rows",
`DecisionJevPrompt.swift:138-149`). Rows come from the compact AX render of any app, including text-entry roles
(`AccessibilitySnapshot.swift:275-281`), i.e. current field contents such as draft messages, email bodies, search terms.
Attack/impact: a user reading SECURITY.md believes "the destination is trusted" is the whole story; in practice every
`decide_next_action` call exports visible third-party app content to the remote host and its logs (vLLM request logging,
reverse-proxy access logs). A compromised or malicious remote engine also fully controls the advice (it chooses
`choices[0].text` and the logprobs), so it can push the host LLM toward a destructive element with a high margin; the only
mitigation is the advisory-only design + the destructive-action rule.
Fix: add an explicit residual-risk bullet to both docs: "Remote backend: the goal, app name and up to 26 visible UI rows
(including text-field contents) per page are sent to the configured host on every call; the host operator and its logs see
them. The remote engine controls the proposal and its margin; treat it with the same trust as the host you configured."
Also mention that in the llama section this does not apply (loopback only).

### M2. Documented ~17 s bound does not hold for the remote backend (letter resolution is unbounded by the deadline)
Evidence: `DecisionJevPrompt.swift:59-75` issues 27 sequential `/tokenize` calls, each with a 5 s timeout
(`DecisionJevClient.swift:88`), all inside the first `readout` call; `DecisionAdvisor.swift:87` checks `overallDeadline`
only before each `readout`, not inside it. Each `readout` also makes 2 completion calls (`DecisionJevClient.swift:112,115`),
so even post-resolution a page costs up to 10 s. Failure is not cached (`DecisionJevPrompt.swift:48` throws before
`:50-52`), so every call against a slow host repeats the full resolution.
Attack/impact: a slow/tarpitting remote (or a flaky network) holds each background call for up to ~135 s (resolution) +
10 s/page; a same-uid peer can open many concurrent `decide_next_action` calls (they skip the env lock by design,
`MacOSAppAgentProxy.swift:410,428`) and pin agent threads. Main thread is protected by `mainThreadWaitLimit`
(`DecisionAdvisor.swift:177,183-197`) but only returns `.deadlineExceeded` while the work keeps running.
Docs claim otherwise: `docs/ARCHITECTURE.md:170` ("roughly 17 s either way"), `DecisionAdvisor.swift:9-10`.
Fix: pass a deadline into the provider (or check it inside `resolveLetters` per request), or cap resolution with its own
total budget (e.g. one batched `/tokenize` is not available, so budget ≤ remaining `overallDeadline`); negative-cache a
failed resolution for a short TTL; correct the docs number.

## Low

### L1. lstat/read TOCTOU: file is re-opened by path and symlinks are followed; size cap bypassable
Evidence: `DecisionRemoteBackend.swift:85-99` checks `lstat`, then `Data(contentsOf: url)` at `:100` does a fresh
`open(2)` by path that follows symlinks, with no `O_NOFOLLOW` and no `fstat` of the opened fd.
Attack: a process that can write the `decision-model/` directory swaps the regular file for a symlink between the two
calls -> the agent reads (a) `/dev/zero` (unbounded read, the 16 KiB cap was checked on the old inode -> memory blow-up of
the TCC agent), (b) a FIFO (blocks the call forever), or (c) any readable file. Capability-wise this needs write access to
the directory, which the documented residual already concedes (such a process can just rewrite the file), so no new
destination control; the impact is DoS plus an inaccurate doc claim: `docs/SECURITY.md:66` says symlinks are "never followed".
Fix: `open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)`, `fstat(fd)` for S_IFREG/uid/mode/size, then read at most
`maxFileSizeBytes + 1` bytes from the fd and reject if over. Optionally also check the parent dir is owned by uid and not
group/other-writable (dir currently created 0755 by `scripts/decision-model/start-sidecar.sh:121`; the loader does not check it).

### L2. Per-call env chooses whether to egress (backend selection), not just which local path
Evidence: `DecisionRemoteBackend.swift:34-41` + `ToolDefinitions.swift:178-182`; env passes the peer filter.
Attack: any same-uid socket peer (or any MCP host sharing the agent) can send `OPEN_COMPUTER_USE_DECISION_MODEL_BACKEND=remote`
even when the user configured the file for one host only, causing the TCC-privileged agent to ship arbitrary apps' rows to the
configured host and consume the user's bearer-key quota (27 + 2/page requests per call). Destination stays trusted and the peer
could already read the same rows via `get_app_state`, so no confidentiality gain for the peer; the delta is third-party egress
and key-quota burn without that host's opt-in. `decision-model.md:84-85` implies the opt-in is per MCP host entry, which it is not.
This matches the plan's accepted contract (per-call env may select the backend) -> user decision, not a defect. Options:
(a) document that the file's presence is the consent for all local callers; (b) add `"enabled": true` / allowed-callers in the file.

### L3. Transport defence-in-depth widened for every caller
Evidence: `DecisionModelTransport.swift:53-64` now accepts https to any host and arbitrary `headers` (`:72-74`) for all callers,
including the llama path. The llama path is still constrained upstream by `DecisionModelEndpoint.fromEnvironment` (http + loopback,
`DecisionModelClient.swift:64-86`), so not exploitable today; the transport alone no longer enforces "loopback only".
Fix (optional): an explicit policy parameter (`.loopbackHTTP` vs `.remoteHTTPS`) so a future caller cannot silently send
AX data off-box via the llama path.

### L4. Key representation not redacted
Evidence: `DecisionRemoteBackend.swift:49-65` — `DecisionRemoteBackendConfig` is a plain public `Equatable` struct holding
`apiKey`; default `String(describing:)`, `dump`, `XCTAssertEqual(config, ...)` failure text, and the agent's fallback
`String(describing: error)` (`MacOSAppAgentProxy.swift:446`) would print it if a config ever lands in one. No current sink found.
Fix: conform to `CustomStringConvertible`/`CustomDebugStringConvertible`/`CustomReflectable` with a redacted key.

### L5. Resolver accepts a degenerate letter map from the server
Evidence: `DecisionJevPrompt.swift:65-72` checks prefix + one new token but not that the 26 ids/token_strs are distinct.
A hostile/buggy engine mapping all letters to one token yields identical logprobs for all labels; the argmax check at
`DecisionJevClient.swift:70` passes on ties and returns margin 0. Harmless to the trust boundary (host will not follow margin 0,
and the server controls the answer anyway), but it is a silent correctness failure. Fix: require distinct ids and token_strs.

### L6. `Authorization` is on URLSession's reserved-header list; wire behaviour unproven
Evidence: header set via `URLRequest.setValue` (`DecisionModelTransport.swift:72-74`); the only test uses a URLProtocol stub
(`Tests/.../DecisionModelClientTests.swift:295-307`), which bypasses CFNetwork's header handling. Apple documents
`Authorization` as a header the loading system may manage. Works in practice for bearer tokens, but verify once against a
real https endpoint (a 401 challenge path could drop/replace it). Functional, not a leak.

## Informational

- Letter-resolution cache is keyed on `base_url|model`, not the key (`DecisionJevPrompt.swift:30`) — fine; key rotation needs no cache flush.
- Test canary assert `XCTAssertEqual(config.apiKey, Self.distinctiveKey)` (`Tests/.../DecisionRemoteBackendTests.swift:59`) prints the canary on failure; acceptable, it is not a real key.
- https to a loopback host is accepted by the loader; with default TLS trust a port squatter cannot present a valid cert, so the "no squatting risk" claim (`docs/SECURITY.md:68`) holds unless the user trusts a local CA.

## Recommended actions (priority)

1. M1: add the egress + server-steers-advice residual to `docs/SECURITY.md` and `decision-model.md`.
2. M2: bound letter resolution by the overall deadline (or its own budget), negative-cache failures, fix `ARCHITECTURE.md:170` and `DecisionAdvisor.swift:9-10`.
3. L1: open with `O_NOFOLLOW|O_NONBLOCK`, `fstat` the fd, bounded read; fix the "never followed" wording.
4. L4, L5: redacted description for the config; distinct-letter check.
5. L2: user decision on whether file presence = consent for every local caller; align docs either way.

## Unresolved questions

- L2 is a product decision (per-call backend selection was accepted in the plan); confirm whether the file should carry an explicit enable/consent flag.
- Were `swift build`/`swift test` run on this exact tree? Not run in this read-only review.
