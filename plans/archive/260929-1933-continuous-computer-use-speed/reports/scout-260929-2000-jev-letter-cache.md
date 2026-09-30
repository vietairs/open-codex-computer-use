# Scout: jev letter-resolution table caching — facts for disk persistence

## 1. Letter table resolution and caching (DecisionJevLetterResolver)

**Type & storage:**
- `[String: DecisionJevLetterResolver.ResolvedLetter]` where `ResolvedLetter` = `(id: Int, tokenStr: String)`
- Static process-wide cache: `nonisolated(unsafe) private static var cache: [String: [String: ResolvedLetter]]`
- Protected by `NSLock()` (synchronized read/write)

**Cache key:**
- `"\(config.baseURL.absoluteString)|\(config.model)"` — file:line DecisionJevPrompt.swift:37

**When filled & failure handling:**
- Filled on first `resolve()` call after cache miss (lock → resolve 27 /tokenize → lock → store → return)
- **Failed resolutions NOT cached** — per DecisionJevPrompt.swift:59 ("transient or misconfigured server should not poison every later call")

**/tokenize call count & timeouts:**
- 27 total: 1 sample-prompt call + 26 letters A-Z (file:line DecisionJevPrompt.swift:76–85, DecisionJevClientTests.swift:48)
- Per-request timeout: `min(DecisionJevClient.requestTimeout=5s, remaining)` (DecisionJevClient.swift:98, 112, 161)
- Overall deadline: 12 seconds absolute wall-clock (`DecisionAdvisor.overallDeadline`; set at ComputerUseService.swift:515)
- All 27 /tokenize + every /v1/completions bounded by same budget (DecisionJevClient.swift:104–107)

## 2. Config-dir helpers & file safety (DecisionRemoteBackendConfigLoader)

**Config file path:**
- `~/Library/Application Support/OpenComputerUse/decision-model/remote-backend.json` (DecisionRemoteBackend.swift:86–87)

**Permission & ownership checks (readValidated, lines 128–180):**
- `open(path, O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)` — no symlink, no blocking, close-on-exec
- `fstat(fd)`: check `st_uid == getuid()` (current user only), `st_mode & 0o077 == 0` (0o600 permissions)
- File regular (not FIFO/device/dir): `S_IFREG` check
- Size cap: 16 KB (maxFileSizeBytes; checked both at fstat and in read loop)
- TOCTOU safe: all checks on opened fd, never re-resolve path after open

**Reuse candidates for cache file:**
- Same TOCTOU-safe `O_NOFOLLOW | O_CLOEXEC` + `fstat(st_uid, st_mode & 0o077)` pattern applicable

## 3. Pure function & invalidation

**Is cache a pure function?**
- Yes: keyed only by `(base_url, model)`; output depends only on backend's tokenizer state, not prompt content (DecisionJevPrompt.swift:8–11)

**Invalidation triggers:**
- Prompt template change: samplePrompt is static (DecisionJevPrompt.swift:145), tied to assistant suffix context → invalidates letterization
- Model name change: cache key includes model (line 37)
- Tokenizer redeploy under same (base_url, model): detected on completion parse failure (two specific messages in `staleLetterCacheMessages`); evicts cache entry so next call re-resolves (DecisionJevClient.swift:171–173)

**Version constant:**
- None found. `samplePrompt` is generated from fixed helper (operationPrompt with hardcoded strings "warm up"), not versioned

## 4. Existing tests & transport stub

**Test files:**
- `DecisionJevClientTests.swift` — resolves all 26 letters, cache retention, deadline enforcement, stale-cache eviction, end-to-end readout
- `DecisionRemoteBackendTests.swift` — config loader, perms/ownership/size checks, JSON schema validation

**Transport stub:**
- `FakeJevTransport` (DecisionJevClientTests.swift:542–610): implements `DecisionModelTransport` protocol
  - Dispatches on request path suffix: `/tokenize` → runs injected `tokenizer` closure; `/v1/completions` → dequeues scripted response
  - Records headers, timeouts, URLs; thread-safe with NSLock
  - No real socket; test helper `wellBehavedTokenizer` returns sample (5 base tokens) + per-letter new token

---

**Summary:** Letter cache is in-memory, NSLock-synchronized, keyed by `(baseURL, model)`. Not cached on resolution failure. Config file uses TOCTOU-safe open+fstat. Prompt template is static (not versioned). Production uses 12s overall deadline; tests inject ManualClock to force deadline exhaustion.
