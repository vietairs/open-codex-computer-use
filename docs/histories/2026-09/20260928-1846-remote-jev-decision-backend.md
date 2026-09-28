## [2026-09-28 18:46] | Task: add a remote jev decision-model backend to decide_next_action

### 🤖 Execution Context
* **Agent ID**: hvn-implementer
* **Base Model**: Claude Sonnet 5 (claude-sonnet-5)
* **Runtime**: Claude Code, worktree `feat/jev-remote-decision-backend`

### 📥 User Query
> Following a review of the "Hybrid Computer Use Part 1" plan, the user rejected an auto-acting Rust/PyO3 fast path
> and instead chose: add an advisory-only remote backend to `decide_next_action` that talks HTTPS + bearer token to
> a vLLM "jev" engine (vm100), as an alternative to the existing loopback llama-server sidecar. vm100 itself is not
> touched. Implement per `plans/260928-1817-jev-remote-decision-backend/plan.md`.

### 🛠 Changes Overview
**Scope:** `packages/OpenComputerUseKit` (Sources + Tests), `skills/open-computer-use/references/decision-model.md`,
`docs/SECURITY.md`, `docs/ARCHITECTURE.md`, `docs/releases/feature-release-notes.md`.

**Key Actions:**
- **Backend selection**: `DecisionBackendSelection` resolves `OPEN_COMPUTER_USE_DECISION_MODEL_BACKEND` per call —
  absent/`llama` keeps today's loopback behavior exactly; `remote` switches to the new backend; any other value, or
  `remote` combined with a non-empty `OPEN_COMPUTER_USE_DECISION_MODEL_URL`, is rejected as invalid/ambiguous.
- **Trusted config file, not per-call env**: `DecisionRemoteBackendConfigLoader` reads
  `~/Library/Application Support/OpenComputerUse/decision-model/remote-backend.json` (`base_url`, `model`,
  `api_key`), the same trust root as the sidecar's pid file — required because any same-uid socket peer can set
  per-call environment on the app agent, and a per-call destination would let it redirect a TCC-privileged
  accessibility read to a host of its choosing. Validates regular-file (no symlink), owner, permission bits
  (`mode & 0o077 == 0`), 16 KiB size cap, https-only `base_url` shape, `model`/`api_key` charset and length; every
  error names the file and field, never the key value.
- **Remote jev client**: `DecisionJevClient` (`DecisionReadoutProviding`, same protocol `DecisionModelClient` now
  also conforms to) issues two single-token `/v1/completions` calls per page (operation head, then target head),
  sharing one process-wide, thread-safe letter resolution (`DecisionJevLetterResolver`, `/tokenize`-based, fails
  closed if a letter is not exactly one new token) and a ChatML prompt builder (`DecisionJevPromptBuilder`, reusing
  `DecisionPromptBuilder.sanitize`). Target page size is 26 (the engine's single-token label cap) versus 52 for the
  loopback backend; `DecisionCandidateBuilder.build` and `DecisionAdvisor.advise` both gained a `pageSize` parameter
  to carry that through without touching paging/label-prefix logic.
- **Transport**: `DecisionModelTransport.postJSON` gained a `headers` parameter (protocol requirement, with a
  headers-free convenience overload for the unchanged loopback call sites); `URLSessionDecisionModelTransport` now
  accepts `https` to any host with the system's default TLS trust (no custom challenge handling anywhere) alongside
  the unchanged loopback-only `http` path.
- **Wiring**: `ComputerUseService.decideNextAction` branches on the resolved backend before any AX read; `remote`
  skips the sidecar-squatting verifier (no equivalent risk — the destination is trust-file-only). Error mapping
  differs by backend: every remote config/file failure maps to `.invalidArguments`, while `llama`'s absent-endpoint
  case maps to `.stateUnavailable` and its malformed-endpoint case maps to `.invalidArguments` — remote has no
  "absent" case distinct from "invalid", since the config file's mere absence is itself an invalid-arguments error.
  `ToolDefinitions.listed(environment:)` now also lists the tool when the backend resolves to `.remote`, checking the
  config file only at call time, never at listing time.

### 🧠 Design Intent (Why)
Keep the trust boundary that already protects the loopback sidecar (destination from a private file outside every
sandbox container, never from the same-uid-forgeable per-call environment) and extend it to a remote destination,
where a forged value would be far more damaging (exfiltration to an arbitrary host, not just a same-uid squatter).
Reuse `DecisionReadoutProviding` so `DecisionAdvisor`'s paging/stage-2 combine logic, and the tool's advisory-only
result shape, stay identical regardless of backend — only how one page's two-head readout is fetched differs.

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/DecisionRemoteBackend.swift` (new)
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/DecisionJevClient.swift` (new)
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/DecisionJevPrompt.swift` (new)
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/DecisionModelTransport.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/DecisionModelClient.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/DecisionAdvisor.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/DecisionCandidates.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/DecisionPrompt.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ToolDefinitions.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/DecisionRemoteBackendTests.swift` (new)
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/DecisionJevClientTests.swift` (new)
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/DecisionModelClientTests.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/DecisionAdvisorTests.swift`
- `skills/open-computer-use/references/decision-model.md`
- `docs/SECURITY.md`
- `docs/ARCHITECTURE.md`
- `docs/releases/feature-release-notes.md`
