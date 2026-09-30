# Phase 06: jev letter table persisted on disk, with progress saved as letters resolve (decision 4)

- **Depends on:** phase 00 (J baseline).
- **Timing:** Tasks 6.1–6.4 touch only jev files and can start at once. Task 6.5, the one-line production wiring in `ComputerUseService.swift`, waits until phases 01, 03 and 05 have committed.
- **Parallel-safe with:** 01, 02, 03, 04 and 05 for Tasks 6.1–6.4; with 07 for Task 6.5.
- **Roles:** Tester ≠ Implementer.
- **Effort:** 3h.
- **Commit (exactly one):** `feat(decision-model): persist the jev letter table per backend`
- Paths: `W`, `S` and `T` are as defined in phase 01.

## Context (verified at afb60fa)

- `DecisionJevLetterResolver` (`S/DecisionJevPrompt.swift:12-121`) caches letters in a process-wide memory dictionary keyed by `"\(baseURL)|\(model)"` (`:20`, `:39`).
  - `resolve()` (`:58-72`) resolves over the network with 27 `/tokenize` calls in `resolveLetters()` (`:79-101`): one for the base prompt, then 26 letters. The progress is held in a local variable and is **thrown away on the deadline**.
  - `invalidateCache()` (`:48-52`) is called for `staleLetterCacheMessages` (`S/DecisionJevClient.swift:170-172`).
- `DecisionJevClient.init` (`S/DecisionJevClient.swift:105-114`) builds the resolver.
  - The production call site is `ComputerUseService.buildDecisionProvider` (`S/ComputerUseService.swift:588-591`).
  - The tests build clients and resolvers through the default inits in 15 places (`T/DecisionJevClientTests.swift`). So the disk cache must default to **nil**, or `swift test` writes into the real config dir and request-count asserts break on the second run (predict: high).
- The owner-only reader is `DecisionRemoteBackendConfigLoader.readValidated(path:)` (`S/DecisionRemoteBackend.swift:128-180`, `private static`). It does O_NOFOLLOW, then fstat for regular file, uid, mode `& 0o077 == 0` and size cap, then a bounded read.
- The sample prompt has no version constant. `samplePrompt` is at `S/DecisionJevPrompt.swift:145`. A sha256 of it detects template changes.
- Decision 4 and decision 12:
  - persist per (base_url, model) in the 0600 config dir;
  - keep one ephemeral session per request, with no keep-alive;
  - entries carry `resolved_at`;
  - letter progress persists as letters resolve.
  - Concurrent stage-1 pages remain out of scope (decision 13).
- The trust root is the same as remote-backend.json. **This phase never reads remote-backend.json. Tests use temp dirs only.**

## Signature

New file `S/DecisionJevLetterDiskCache.swift`:
```swift
struct DecisionJevLetterDiskCache: Sendable {
    static let formatVersion = 1
    static let maxEntryAge: TimeInterval = 7 * 24 * 60 * 60      // resolved_at older than this = miss (7-day TTL: user decision 2026-09-29)
    static let maxFileBytes = 64 * 1024
    /// ~/Library/Application Support/OpenComputerUse/decision-model/jev-letters (dir 0700, files 0600). Production only.
    static var productionDirectory: URL { get }

    struct Entry: Codable, Equatable, Sendable {
        struct Letter: Codable, Equatable, Sendable { let id: Int; let tokenStr: String }   // keys "id", "token_str"
        let version: Int                    // "version"
        let baseURL: String                 // "base_url"
        let model: String                   // "model"
        let samplePromptSHA256: String      // "sample_prompt_sha256"
        let resolvedAt: Date                // "resolved_at", ISO-8601
        let baseTokenIDs: [Int]             // "base_ids": /tokenize ids of the sample prompt (needed to resume)
        let letters: [String: Letter]       // "letters": resolved so far
        var isComplete: Bool { get }        // 26 letters, 26 distinct ids, 26 distinct token_strs
    }

    let directory: URL
    let now: @Sendable () -> Date
    init(directory: URL, now: @escaping @Sendable () -> Date = Date.init)

    func fileURL(baseURL: URL, model: String) -> URL   // directory/<lowercase hex sha256("\(baseURL.absoluteString)|\(model)")>.json
    /// nil on ANY problem: missing, symlink, not regular, wrong owner, group/other bits, oversize, bad JSON, version,
    /// base_url/model/sample hash mismatch, expired resolved_at. Never throws.
    func load(baseURL: URL, model: String, samplePromptSHA256: String) -> Entry?
    /// Best effort, never throws: create directory 0700 if absent (refuse if it exists with group/other write or other
    /// owner); write temp file O_CREAT|O_EXCL|O_NOFOLLOW|O_WRONLY|O_CLOEXEC mode 0600 in `directory`; write; close; rename(2).
    func store(_ entry: Entry, baseURL: URL, model: String)
    func remove(baseURL: URL, model: String)
}
```

`S/DecisionRemoteBackend.swift`. This is a DRY generalization, and the existing error texts must stay byte-identical:
```swift
/// OLD: private static func readValidated(path: String) throws -> Data (body moves here, unchanged checks)
func readOwnerOnlyRegularFile(path: String, maxBytes: Int) throws -> Data
// DecisionRemoteBackendConfigLoader.readValidated(path:) becomes: try readOwnerOnlyRegularFile(path: path, maxBytes: maxFileSizeBytes)
```

`S/DecisionJevPrompt.swift`:
```swift
// OLD init(config:transport:deadline:now:)
init(config: DecisionRemoteBackendConfig, transport: DecisionModelTransport, deadline: Date,
     now: @escaping @Sendable () -> Date = Date.init, diskCache: DecisionJevLetterDiskCache? = nil)
let diskCache: DecisionJevLetterDiskCache?          // internal read-only, for tests
static var samplePromptSHA256: String { get }       // hex sha256 of DecisionJevPromptBuilder.samplePrompt (CryptoKit SHA256, already used by AppAgentSocketNamespace.swift:1)
```
`resolve()` order: memory, then disk (a complete entry, re-validated for 26 distinct ids and token_strs), then network. The network path:
1. Always tokenize the base prompt, which is 1 request.
2. If a partial disk entry exists and its `baseTokenIDs` equal the fresh base ids, resume from its letters. Otherwise start fresh and `remove` the stale partial.
3. After each newly resolved letter, `store` the progress entry with `resolvedAt = now()`.
4. When all 26 are resolved and distinct, `store` the complete entry and fill memory.
5. If a letter check fails, `remove` the entry and rethrow.

`invalidateCache()` evicts memory **and** calls `diskCache?.remove`. `resetCacheForTesting()` stays memory-only.

`S/DecisionJevClient.swift`:
```swift
// public init(config:transport:deadline:now:) — UNCHANGED signature; body forwards to the internal init with diskCache: nil
init(config: DecisionRemoteBackendConfig, transport: DecisionModelTransport, deadline: Date,
     now: @escaping @Sendable () -> Date, diskCache: DecisionJevLetterDiskCache?)   // NEW, internal (the cache type is internal)
```

`S/ComputerUseService.swift:588-591` (Task 6.5 only). `buildDecisionProvider` passes `diskCache: DecisionJevLetterDiskCache(directory: DecisionJevLetterDiskCache.productionDirectory)`.

## Data flow

```
decide_next_action ─► buildDecisionProvider ─► DecisionJevClient(diskCache: production)
  readout ─► resolver.resolve(): memory hit? ─► disk load (owner-only reader) complete & valid? ─► memory ─► done (0 /tokenize)
                                          └─► network: base /tokenize ─► resume partial (same base ids) ─► per letter /tokenize
                                                       ─► store progress (0600, atomic rename) ─► complete ─► store ─► memory
  completion parse stale-letter message ─► invalidateCache(): memory + disk remove
```
The file holds `base_url`, `model`, token ids and token strings. It **never** holds `api_key`.

## Boundaries

```
TARGET:    S/DecisionJevLetterDiskCache.swift (new)
           S/DecisionJevPrompt.swift (resolver init/resolve/resolveLetters/invalidateCache, samplePromptSHA256)
           S/DecisionJevClient.swift (internal init with diskCache; public init forwards nil)
           S/DecisionRemoteBackend.swift (readOwnerOnlyRegularFile extraction only)
           S/ComputerUseService.swift (:588-591 buildDecisionProvider only — Task 6.5, after 01/03/05 commit)
           T/DecisionJevLetterDiskCacheTests.swift (new; Tester only)
READ-ONLY: T/DecisionJevClientTests.swift, T/DecisionRemoteBackendTests.swift (must pass unedited)
FORBIDDEN: reading ~/Library/Application Support/OpenComputerUse/decision-model/remote-backend.json or any credential;
           writing api_key anywhere; HTTP keep-alive / shared URLSession (decision 4); concurrent /tokenize or concurrent
           stage-1 pages (decision 13: out); any test touching productionDirectory on disk; editing existing jev tests;
           files owned by phases 01-05, 07; Track B files
```

## Tasks

### Task 6.1: Failing tests first (Tester)
- Create `T/DecisionJevLetterDiskCacheTests.swift` (class `DecisionJevLetterDiskCacheTests`) with every assertion below.
  - Use a fresh temp dir per test: `FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)`, removed in `tearDown`.
  - Use a counting fake transport. Reuse the fake-transport pattern from `T/DecisionJevClientTests.swift`, and count requests whose URL path ends in `/tokenize`.
  - Call `DecisionJevLetterResolver.resetCacheForTesting()` in `setUp`.
- Verify (RED): `swift test --filter OpenComputerUseKitTests.DecisionJevLetterDiskCacheTests 2>&1 | tail -30` exits non-zero and contains `cannot find 'DecisionJevLetterDiskCache' in scope`.

### Task 6.2: Owner-only reader extraction (Implementer)
- Verify: `swift test --filter OpenComputerUseKitTests.DecisionRemoteBackendTests 2>&1 | tail -15` exits 0, and `git diff afb60fa -- $T/DecisionRemoteBackendTests.swift` prints nothing.

### Task 6.3: Disk cache type (Implementer)
- Create the new file exactly as specified in the Signature block.
- Verify: `swift build 2>&1 | tail -5` exits 0.

### Task 6.4: Resolver and client wiring (Implementer)
- Verify:
  - `swift test --filter OpenComputerUseKitTests.DecisionJevLetterDiskCacheTests 2>&1 | tail -30` exits 0 and contains `with 0 failures`.
  - `swift test --filter OpenComputerUseKitTests.DecisionJevClientTests` exits 0 on **two consecutive runs**.

### Task 6.5: Production wiring, after 01, 03 and 05 have committed (Implementer)
- Steps: `git log --oneline -8` must show the three commit subjects of phases 01, 03 and 05. Then edit only `buildDecisionProvider`.
- Verify, all of:
  - `swift test 2>&1 | tail -15` exits 0 and contains `with 0 failures`. Run it twice.
  - `grep -rn 'productionDirectory' $T` prints only lines in `DecisionJevLetterDiskCacheTests.swift` that compare the path suffix. No test creates or reads that directory.
- Commit with the exact subject above and report the SHA.

## Acceptance

Command: `cd $W && swift test --filter OpenComputerUseKitTests.DecisionJevLetterDiskCacheTests`

Assertions (write first):
- **Miss then write.** A fresh resolver with `diskCache` makes 27 `/tokenize` requests. Afterwards `fileURL` exists with mode `0o600`, and the dir has mode `0o700`. The JSON has `version`, `base_url`, `model`, `sample_prompt_sha256`, `resolved_at`, `base_ids` and 26 `letters`, and it **does not contain the api key string**.
- **Disk hit.** After `resetCacheForTesting()`, a new resolver on the same dir returns identical letters with **0** `/tokenize` requests. This is the unit proof for "cold no longer resolves after the first success".
- **Key change.** Changing only `model` or only `base_url` causes a miss, with 27 requests.
- **Invalidation.** `invalidateCache()` removes the file.
- **Corrupt or unsafe file = miss, never an error:**
  - garbage JSON;
  - mode `0o644`;
  - a symlink at the file path;
  - a `version` of 2;
  - a mismatched `sample_prompt_sha256`;
  - `resolved_at` older than `maxEntryAge` (with `now` injected).

  In every case resolve succeeds over the network (27 requests), and the file is rewritten as 0600.
- **Progress persists.** The transport serves the base prompt and 10 letters, then throws. `resolve()` throws. The file now holds `base_ids` and exactly 10 letters, and `isComplete == false`. A new resolver (after the memory reset) whose transport works makes exactly **1 + 16 = 17** requests, and ends complete.
- **Stale partial.** Same setup, but the second transport's base tokenization returns different ids. That run makes 27 requests and completes, and the file's `base_ids` equal the new ids.
- **Default is off.** `DecisionJevLetterResolver(config:transport:deadline:)` has `diskCache == nil`. `DecisionJevClient(config:transport:deadline:)`, the public init, resolves with 27 requests twice in a row after memory resets. No file appears in the test's temp dir.
- **Production path shape.** `DecisionJevLetterDiskCache.productionDirectory.path` has the suffix `Library/Application Support/OpenComputerUse/decision-model/jev-letters`. The test compares the path string only and does no I/O.

## Live measurement M6 (main loop)

This uses the harness `decide` mode with `--remote-decision` against a build of C6 or a later commit. It needs vm100 jev to be healthy. If jev is overloaded (GPUs at 100%), record that and re-run later; do not count it as a code failure.
1. Remove only `~/Library/Application Support/OpenComputerUse/decision-model/jev-letters/`. Never touch `remote-backend.json`.
2. Kill the bench agent (B-3), then run `decide --calls 5`. Call 0 is fully cold: it may time out, but partial progress must now accumulate. Repeat the kill-and-run until call 0 succeeds. Record how many attempts that took.
3. Kill the bench agent, then run `decide --calls 5` again.
   - `J_cold` is call 0. It must not be an error.
   - `J_warm` is the median of calls 1–4, and must be ≤ 3.0s.
4. Run `ls -l` on the jev-letters dir: it shows `-rw-------` files and a `drwx------` dir. Do not print the file contents.

## Risks

| Risk | L×I | Mitigation |
|---|---|---|
| Tests write into the real config dir | M×H | The disk cache defaults to nil in both inits; there are two-run Verify steps and a grep of the test tree |
| A persisted table goes stale after a tokenizer redeploy that `staleLetterCacheMessages` misses | L×M | `sample_prompt_sha256`, the `resolved_at` TTL of 7 days, and eviction on stale messages |
| Dev and release agents race on one file | L×L | One file per key, atomic rename, last writer wins, and both entries are valid |
| Warm stays above 3s because of jev load or the Mail walk (counsel) | M×M | Phase 01 already gives decide `.never` capture, and phase 04 speeds the walk. If warm still exceeds 3s, **escalate to the user.** Concurrent pages are out of scope under decision 13, so they are not an automatic fix. |

## Rollback

`git revert <C6>`. The on-disk files are then ignored by the reverted code, which never reads them. Optionally remove the jev-letters dir. The change is independent of the other phases.

## Contract Rules
1. Implements to the SIGNATURE exactly. A signature that cannot work is a STOP, not a redesign —
   report it through the Failure Protocol.
2. Edits only within TARGET. Discovering that the change genuinely requires a FORBIDDEN file is a
   STOP with that finding, never a quiet widening.
3. Writes the acceptance assertions first where the plan says tests-first, confirms they FAIL, then
   implements until they pass.
4. Never weakens an assertion, never marks a test skipped, and never stubs an implementation to
   make one pass. A passing suite obtained this way is the specific failure this whole contract is
   built to prevent — cheap tiers reward-hack checkable specs more than strong ones do, so the
   escalation path exists precisely for the moment the spec looks unsatisfiable.
5. On any failed Verify, follows the `## Failure Protocol` already in the phase file. That is the
   backchannel; using it is correct behaviour, not an admission of failure. The escalation names
   the failure's class: a missed edge case, a wrong or incomplete fix, a misread requirement
   (including a wrong reading of an ambiguous one), or a wrong domain rule. The first two are
   fixed by more verification. The last two are not fixed by more effort or by a retry: they need
   the outcome re-locked or the rule looked up, so name the class in the escalation instead of
   retrying.

## Failure Protocol
If any Verify step does not meet its stated pass condition, STOP this phase.
Do not improvise a fix, retry blindly, or reason around the failure.
Spawn the `kongming` subagent for next-step counsel and pass:
- the phase and task id,
- what you attempted (the steps you ran),
- the exact command and its full output,
- the pass condition it failed to meet.
Apply kongming's guidance, then re-run the Verify step.
If `kongming` cannot be spawned in this environment, STOP and report the same
failure evidence to the user. Never continue by self-reasoning.
