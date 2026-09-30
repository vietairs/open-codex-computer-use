# Phase 02: script audit log (0600, O_NOFOLLOW, metadata-only stderr)

Depends on: phase 00. Parallel group G1 (with 01 and 05; disjoint files). Blocks: 04.
Risk: Medium (symlink swap, interleaved writes from several relays, rotation race). Effort 3h.

## Execution constants

- `WT=/Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/fast-macos-channels`; run every command as
  `cd "$WT" && ...`. `K` and `T` as in plan.md.
- Test hygiene (binding): no plan ids or phase numbers in test names, comments or commits; range-check before
  subscripting; every test writes only under its own `FileManager.default.temporaryDirectory` subdirectory and removes
  it in `tearDown`; never touch the real `~/Library/Application Support/OpenComputerUse`.
- Roles: tester writes Task 2.1; a different implementer does Task 2.2 and never edits the test file.

## Task 2.1 (tester): failing tests first

- Goal: `T/ScriptAuditLogTests.swift` pinning file safety, format, stderr hygiene, rotation and concurrency.
- Steps: write every assertion under Acceptance.
- Verify (RED is the pass condition): `cd "$WT" && swift build --build-tests 2>&1 | tail -40` exits non-zero and the
  output contains `error:` and `ScriptAuditLog`. A zero exit is a failure.

## Task 2.2 (implementer): make them pass

- Goal: `K/ScriptAuditLog.swift` matching the Signature.
- Steps:
  1. `record(_:)`:
     - Ensure `directory` exists: create with intermediates at mode 0700. Then `lstat` it: must be a directory (not a
       symlink), owned by `getuid()`, and `(st_mode & 0o077) == 0`; else throw `.directoryUnsafe`.
     - `open(path, O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)`. On `ELOOP` (symlink) throw
       `.fileUnsafe`. `fstat` the fd: regular file, owner `getuid()`, `(st_mode & 0o077) == 0`; else close and throw
       `.fileUnsafe`.
     - `flock(fd, LOCK_EX)`. Then confirm the fd still names the live file: `fstat(fd)` and `lstat(path)` must agree
       on `st_dev` and `st_ino`. On a mismatch (another relay rotated while this one waited on the lock), unlock, close,
       and reopen with the same flags and checks; give up with `.fileUnsafe` after 3 attempts. Only then, if
       `st_size >= maximumFileBytes`: `rename(scripts.log -> scripts.log.1)` (replacing), close, reopen with the same
       flags and checks, `flock` again. This keeps a writer that held the old inode from rotating a second time and
       overwriting the previous generation.
     - Build one line: JSON object (sorted keys) + `\n`. Keys: `kind`, `phase`, `timestamp` (ISO-8601 UTC, fractional
       seconds), `relay_pid`, `parent_pid`, `target_app`, `payload` (request phase only), `payload_sha256`,
       `exit_status`, `duration_ms`, `outcome` (omit nil values).
     - One `write(2)` of the whole line. If the byte count written differs, throw `.writeFailed`. Unlock, close.
     - After the file write succeeds, pass `metadataLine(for:)` to `standardErrorWriter`. The metadata line never
       contains `payload`.
  2. `metadataLine(for:)`: `[open-computer-use] <kind> <phase> app=<target_app or -> sha256=<first 16 hex> exit=<n or ->
     duration_ms=<n or -> outcome=<text or ->\n`. `target_app` and `outcome` are agent-influenced, so every control
     character (`\n`, `\r`, U+0000-U+001F, U+007F, U+2028, U+2029) in them is written as `\u{XXXX}`-style escapes and each
     value is capped at 128 characters; the line can never contain an embedded newline.
  3. `sha256Hex(_:)`: lowercase hex of `SHA256` over UTF-8 (CryptoKit is already used by the Kit,
     `AppAgentSocketNamespace.swift:11`).
  4. `defaultDirectory`: `~/Library/Application Support/OpenComputerUse/logs` built from `NSHomeDirectory()` (same root as
     `DecisionRemoteBackend.swift:87`).
  5. `target_app` is the agent-declared `app` argument, not the app the script actually tells. Say so in the type's doc
     comment ("advisory").
  6. Counsel amendment 5 asked to reuse Track A's owner-only file helper. Not applicable: Track A's helper is a reader
     (`readOwnerOnlyRegularFile`), while this log needs an `O_APPEND` writer. The main loop records "N/A, reader vs
     appender" in the PR body (never in code comments or commit messages) so the security review does not flag it.
- Verify:
  1. `cd "$WT" && swift test --filter ScriptAuditLogTests 2>&1 | tail -30` exits 0 and prints `with 0 failures`.
  2. `cd "$WT" && swift build && swift test 2>&1 | tail -15` exits 0 and prints `with 0 failures`.

## Signature

```swift
// K/ScriptAuditLog.swift
public struct ScriptAuditEntry: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case runScript = "run_script"
        case openURL = "open_url"
        case runShortcut = "run_shortcut"
    }
    public enum Phase: String, Sendable {
        case request
        case result
    }
    public let kind: Kind
    public let phase: Phase
    public let timestamp: Date
    public let relayPID: Int32
    public let parentPID: Int32
    public let targetApp: String?
    public let payload: String?          // full script text / URL / "name\ninput"; request phase only
    public let payloadSHA256: String
    public let exitStatus: Int32?
    public let durationMilliseconds: Int?
    public let outcome: String?
    public init(
        kind: Kind, phase: Phase, timestamp: Date = Date(),
        relayPID: Int32 = getpid(), parentPID: Int32 = getppid(),
        targetApp: String?, payload: String?, payloadSHA256: String,
        exitStatus: Int32? = nil, durationMilliseconds: Int? = nil, outcome: String? = nil
    )
}

public enum ScriptAuditLogError: Error, Equatable {
    case directoryUnsafe(String)
    case fileUnsafe(String)
    case writeFailed(String)
}

public final class ScriptAuditLog: @unchecked Sendable {
    public static let fileName: String                 // "scripts.log"
    public static let rotatedFileName: String          // "scripts.log.1"
    public static let defaultMaximumFileBytes: Int     // 10 * 1024 * 1024 (retention confirmed by the user, 2026-09-29)
    public static var defaultDirectory: URL { get }
    public let directory: URL
    public init(
        directory: URL = ScriptAuditLog.defaultDirectory,
        maximumFileBytes: Int = ScriptAuditLog.defaultMaximumFileBytes,
        standardErrorWriter: @escaping @Sendable (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) }
    )
    public func record(_ entry: ScriptAuditEntry) throws
    public static func sha256Hex(_ text: String) -> String
    static func metadataLine(for entry: ScriptAuditEntry) -> String
}
```

## Boundaries

```
TARGET:    K/ScriptAuditLog.swift, T/ScriptAuditLogTests.swift
READ-ONLY: K/DecisionRemoteBackend.swift (O_NOFOLLOW read pattern, :124-180), K/AppAgentSocketNamespace.swift
FORBIDDEN: editing K/DecisionRemoteBackend.swift (Track A generalises its reader; do not collide);
           keeping a log fd open across calls; any new dependency;
           phase 01/05 files (K/ScriptPolicyFilter.swift, K/ConfinedChildProcessRunner.swift, K/OsascriptChildRunner.swift,
           K/ElementSearch*.swift, K/ComputerUseService.swift, K/ToolDefinitions.swift, K/ComputerUseToolDispatcher.swift)
```

## Acceptance

Command: `cd "$WT" && swift test --filter ScriptAuditLogTests`
Assertions (write first; they must fail before the change and pass after):
- `testLogFileIsOwnerOnly`: after one `record`, `stat` of `scripts.log` has `st_mode & 0o777 == 0o600` and the
  directory has `0o700`.
- `testEntryIsOneJSONLineWithFullPayload`: file has exactly one line; it parses as JSON; `payload` equals the script
  text; `payload_sha256` equals `sha256Hex(text)`; `kind == "run_script"`, `phase == "request"`.
- `testStandardErrorCarriesMetadataOnly`: captured writer output contains the 16-hex prefix and `run_script`, and does
  NOT contain a unique marker string that was inside the payload.
- `testSymlinkedLogFileIsRefused`: pre-create `scripts.log` as a symlink to `victim.txt` (in the temp dir, content
  `original`) -> `record` throws `.fileUnsafe`; `victim.txt` still reads `original`; the writer was not called.
- `testWidePermissionLogIsRefused`: pre-create `scripts.log` with mode 0644 -> throws `.fileUnsafe`.
- `testSymlinkedDirectoryIsRefused`: `directory` is a symlink to another temp dir -> throws `.directoryUnsafe`.
- `testRotationKeepsOnePreviousGeneration`: `maximumFileBytes: 1024`, pre-fill `scripts.log` (0600) with 2048 bytes ->
  after `record`, `scripts.log.1` exists with the 2048 bytes and `scripts.log` holds exactly one line.
- `testConcurrentWritersNeverInterleave`: 8 threads x 50 `record` calls on separate `ScriptAuditLog` instances sharing
  one directory -> 400 lines, every line parses as JSON.
- `testResultEntryOmitsPayload`: a `.result` entry with `payload: nil` has no `payload` key and has `exit_status`,
  `duration_ms`.
- `testConcurrentRotationKeepsPreviousGeneration`: `maximumFileBytes: 1024`; pre-fill `scripts.log` (0600) with 2048
  bytes that contain a unique marker; 8 threads on separate instances each `record` one entry at the same time (start
  them on a shared `DispatchGroup` barrier) -> `scripts.log.1` still contains the marker, `scripts.log` holds exactly 8
  lines, every line parses as JSON.
- `testMetadataLineEscapesControlCharacters`: entry with `targetApp: "Mail\n[open-computer-use] run_script result"` and
  `outcome: "x\ry"` -> `metadataLine` contains exactly one `\n` (the terminator) and no `\r`.

## Rollback

Revert the phase commit (two new files). No existing code references them before phase 04.

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
