# Phase 01: script policy filter, confined child runner, osascript runner

Depends on: phase 00 (go decision). Parallel group G1 (with 02 and 05; disjoint files). Blocks: 03, 04.
Risk: High (fd leakage, SIGPIPE, pipe deadlock, a descendant holding the pipes open are the failure modes). Effort 5h.
Known limit (documented, not fixed): the child sits in its own process group, so if the relay itself is killed
mid-script the osascript child is orphaned and runs to completion inside the target app's Apple Event timeouts; the
audit log then holds a request line with no result line (threat-model T24). Accepted by the user as a documented
residual (2026-09-29); no signal forwarding.

## Execution constants

- Worktree: `WT=/Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/fast-macos-channels`. Every command
  below runs as `cd "$WT" && ...` in one shell call. Never build or test in the main checkout.
- `K=packages/OpenComputerUseKit/Sources/OpenComputerUseKit`, `T=packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests`.
- Test hygiene (binding): no plan ids, phase numbers or finding codes in test names, comments or commit messages;
  range-check before subscripting (use `XCTUnwrap` or a count guard; a trap kills every later test in the run); no test
  sends an Apple Event to another app, opens a URL or needs a TCC grant; never call an open-computer-use MCP tool and
  never start the app agent.
- Roles: Task 1.1 is done by a **tester** agent; Task 1.2 by a different **implementer** agent. The implementer never
  edits the test files; if a test cannot compile against the stated signature, STOP (Failure Protocol).

## Task 1.1 (tester): failing tests first

- Goal: two new test files that pin the filter, runner and osascript contracts.
- Target files: new `T/ScriptPolicyFilterTests.swift`; new `T/ConfinedChildProcessRunnerTests.swift` (holds two
  classes: `ConfinedChildProcessRunnerTests` and `OsascriptChildRunnerTests`).
- Steps: write every assertion listed under Acceptance, importing `@testable import OpenComputerUseKit`.
- Success criteria: the tests exist and fail because the types do not exist yet.
- Verify (RED is the pass condition): `cd "$WT" && swift build --build-tests 2>&1 | tail -40` exits non-zero and the
  output contains `error:` and `ScriptPolicyFilter` or `ConfinedChildProcessRunner`. A zero exit here is a failure.

## Task 1.2 (implementer): make them pass

- Goal: the three source files below, matching the Signature exactly.
- Target files: new `K/ScriptPolicyFilter.swift`, `K/ConfinedChildProcessRunner.swift`, `K/OsascriptChildRunner.swift`.
- Steps:
  1. `ScriptPolicyFilter.normalize`, in this order: NFKC (`precomposedStringWithCompatibilityMapping`, folds fullwidth
     letters to ASCII); lowercase; replace `\r\n` and `\r` with `\n`; delete every `¬` (U+00AC) that is followed only by
     characters of `CharacterSet.whitespaces` and then `\n`, together with that `\n`; collapse every run of
     `CharacterSet.whitespacesAndNewlines` (covers NBSP U+00A0, U+2028/2029 and other Unicode spaces, not only ASCII)
     into one space; delete a space directly after `«` or `<<` and directly before `»` or `>>`; trim.
  2. `evaluate`: build two views: `normalize(source)`, and `normalize(source with every `(*`...`*)` span replaced by a
     space)` (shortest match, repeated until none is left). Return `.rejected(matchedPattern:)` for the first entry of
     `deniedPatterns` contained in EITHER view, else `.allowed`. Checking both views only ever adds rejections, so a
     comment marker inside a string literal cannot hide a denied phrase. The list applies to both languages (union),
     exactly:
     `["do shell script", "run script", "load script", "store script", "do script", "«event", "<<event",
     "use framework", "use scripting additions", "use script", "doshellscript", "runscript", "loadscript",
     "doscript", "objc.", "library(", "$.ns"]`. Add a doc comment: best-effort friction, not a security boundary;
     shell-capable hosts bypass it with Bash `osascript`.
  3. `ConfinedChildProcessRunner.run`. One absolute deadline governs spawn, reap and drain, so a descendant that keeps
     a pipe open can never wedge the serial relay:
     - Reject a non-absolute `executablePath` with `.executablePathNotAbsolute`.
     - Create three pipes; set `FD_CLOEXEC` on every parent-side end; set `O_NONBLOCK` on the two parent read ends; set
       `F_SETNOSIGPIPE` on the stdin write end so a child that exits early can never SIGPIPE the relay.
     - `posix_spawnattr_setflags` with `POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF |
       POSIX_SPAWN_SETSIGMASK`, process group 0, default signal set = all signals, empty mask.
     - File actions: `adddup2` the child ends onto 0, 1, 2 only (nothing else is inherited, CLOEXEC_DEFAULT), and
       `posix_spawn_file_actions_addchdir_np(&actions, "/")` so the child never runs in the relay's working directory.
     - argv = `[executablePath] + arguments`; envp = `request.environment` exactly.
     - Close child ends in the parent. Write stdin on its own thread (EPIPE ends the write quietly), then close it.
     - Reaping: exactly ONE reaper thread owns the child. It calls `waitid(P_PID, pid, &info, WEXITED | WNOWAIT)` to
       observe the leader's exit while the zombie still pins the pid and pgid, signals a semaphore, waits for the
       controller's go-ahead, then calls `waitpid(pid, &status, 0)` once. No other thread ever calls `waitpid`.
       [UNVERIFIED: `WNOWAIT` with `waitid` on Darwin. If `waitid` returns `EINVAL`, the reaper reaps directly with
       `waitpid` and the controller skips the post-exit group kill below; the drain deadline still bounds the call.]
     - Controller: `deadline = start + timeout`. Wait on the reaper semaphore until `deadline`. On timeout:
       `kill(-pid, SIGTERM)`, wait up to `killGracePeriod` on the same semaphore, `kill(-pid, SIGKILL)`, then wait at
       most `reapGracePeriod` more; set `timedOut`. If the leader is still not observed after that, return with
       `exitStatus == nil` and let the detached reaper finish later.
     - Once the leader's exit is observed (normal or after a kill): `kill(-pid, SIGKILL)` to clear any descendant left in
       the group (ESRCH ignored), then let the reaper reap.
     - Drain stdout and stderr on ONE thread with `poll(2)` over both read ends; keep the first `outputByteLimit` bytes of
       each, read and discard the rest, record `...Truncated`. The drain stops at EOF on both, or at
       `leaderObservedTime + drainGracePeriod`, whichever is first. A stream cut by the drain deadline is marked
       truncated. Close both read ends before returning. Worst-case return time is
       `timeout + killGracePeriod + reapGracePeriod + drainGracePeriod`.
     - `exitStatus` from `WIFEXITED`, `terminatingSignal` from `WIFSIGNALED`; `duration` wall-clock.
  4. `scrubbedEnvironment(from:)` returns exactly `PATH = fixedSearchPath`, `HOME` (input value if absolute, else
     `NSHomeDirectory()`), `LANG` (input value or `en_US.UTF-8`).
  5. `OsascriptChildRunner.run`: reject source over `maximumSourceBytes` UTF-8 bytes; build a request with
     `arguments(for:)`, source as stdin, `scrubbedEnvironment(from: baseEnvironment)`; map the result: `resultText` =
     `decodeOutput(stdout)` minus one trailing newline; `errorMessage` = `decodeOutput(stderr)` trimmed, first 2048
     characters, nil if empty. `decodeOutput` is `String(decoding: data, as: UTF8.self)` (never
     `String(data:encoding:)`, which returns nil when the byte cap splits a multi-byte character);
     `errorNumber` = `parseErrorNumber(fromStandardError:)` when exit status != 0.
  6. `parseErrorNumber`: the last `(<signed integer>)` in the text, e.g. `execution error: ... (-1743)` -> -1743.
  7. `userFacingMessage`: -1743 -> "Automation permission denied: the app that launched this MCP server (your terminal,
     or the Claude/Codex app) may not control <app>. Approve it in System Settings > Privacy & Security > Automation,
     then retry."; -600 -> "<app> is not running."; -1712 -> "<app> did not answer in time; keep queries small (one
     mailbox, first N results)."; anything else -> nil.
- Success criteria: all Acceptance assertions pass; full suite still green.
- Verify:
  1. `cd "$WT" && swift test --filter 'ScriptPolicyFilterTests|ConfinedChildProcessRunnerTests|OsascriptChildRunnerTests' 2>&1 | tail -40`
     exits 0 and prints `with 0 failures`.
  2. `cd "$WT" && swift build && swift test 2>&1 | tail -15` exits 0 and prints `with 0 failures`.

## Signature

```swift
// K/ScriptPolicyFilter.swift
public enum ScriptLanguage: String, Sendable, CaseIterable {
    case applescript
    case javascript
}

public enum ScriptPolicyVerdict: Equatable, Sendable {
    case allowed
    case rejected(matchedPattern: String)
}

public enum ScriptPolicyFilter {
    public static let deniedPatterns: [String]
    public static func normalize(_ source: String) -> String
    public static func evaluate(source: String, language: ScriptLanguage) -> ScriptPolicyVerdict
}

// K/ConfinedChildProcessRunner.swift
public struct ConfinedChildProcessRequest: Sendable {
    public let executablePath: String
    public let arguments: [String]
    public let standardInput: Data
    public let environment: [String: String]
    public let timeout: TimeInterval
    public let outputByteLimit: Int
    public init(
        executablePath: String,
        arguments: [String],
        standardInput: Data = Data(),
        environment: [String: String],
        timeout: TimeInterval,
        outputByteLimit: Int = ConfinedChildProcessRunner.defaultOutputByteLimit
    )
}

public struct ConfinedChildProcessResult: Equatable, Sendable {
    public let exitStatus: Int32?
    public let terminatingSignal: Int32?
    public let timedOut: Bool
    public let standardOutput: Data
    public let standardError: Data
    public let standardOutputTruncated: Bool
    public let standardErrorTruncated: Bool
    public let duration: TimeInterval
}

public enum ConfinedChildProcessError: Error, Equatable {
    case executablePathNotAbsolute(String)
    case pipeFailed(errno: Int32)
    case spawnFailed(errno: Int32)
}

public enum ConfinedChildProcessRunner {
    public static let defaultOutputByteLimit: Int          // 65_536
    public static let killGracePeriod: TimeInterval        // 1.0
    public static let reapGracePeriod: TimeInterval        // 2.0
    public static let drainGracePeriod: TimeInterval       // 0.5
    public static let fixedSearchPath: String              // "/usr/bin:/bin:/usr/sbin:/sbin"
    public static func scrubbedEnvironment(from environment: [String: String]) -> [String: String]
    public static func run(_ request: ConfinedChildProcessRequest) throws -> ConfinedChildProcessResult
}

// K/OsascriptChildRunner.swift
public struct ScriptRunOutcome: Equatable, Sendable {
    public let resultText: String
    public let errorNumber: Int?
    public let errorMessage: String?
    public let timedOut: Bool
    public let exitStatus: Int32?
    public let durationMilliseconds: Int
    public let outputTruncated: Bool
}

public enum OsascriptChildRunnerError: Error, Equatable {
    case sourceTooLarge(byteCount: Int)
}

public struct OsascriptChildRunner: Sendable {
    public static let defaultExecutablePath: String            // "/usr/bin/osascript"
    public static let defaultTimeout: TimeInterval             // 20
    public static let maximumTimeout: TimeInterval             // 60
    public static let firstContactMinimumTimeout: TimeInterval // 30
    public static let maximumSourceBytes: Int                  // 65_536
    public let executablePath: String
    public let baseEnvironment: [String: String]
    public init(
        executablePath: String = OsascriptChildRunner.defaultExecutablePath,
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment
    )
    public static func arguments(for language: ScriptLanguage) -> [String]
    public static func parseErrorNumber(fromStandardError text: String) -> Int?
    public static func effectiveTimeout(
        requested: TimeInterval?,
        isFirstContactWithTarget: Bool,
        firstContactFloor: TimeInterval = OsascriptChildRunner.firstContactMinimumTimeout
    ) -> TimeInterval
    public static func userFacingMessage(errorNumber: Int, app: String) -> String?
    static func decodeOutput(_ data: Data) -> String
    public func run(source: String, language: ScriptLanguage, timeout: TimeInterval) throws -> ScriptRunOutcome
}
```

`effectiveTimeout`: requested nil or <= 0 -> 20; clamp to [.., 60]; if first contact, `max(value, firstContactFloor)`
(still <= 60). Phase 04 passes its injected floor through the third parameter, so tests can shorten it.

## Boundaries

```
TARGET:    K/ScriptPolicyFilter.swift, K/ConfinedChildProcessRunner.swift, K/OsascriptChildRunner.swift,
           T/ScriptPolicyFilterTests.swift, T/ConfinedChildProcessRunnerTests.swift
READ-ONLY: K/MacSessionGuard.swift, K/Errors.swift, apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift
FORBIDDEN: Foundation.Process for the child (it gives no CLOEXEC_DEFAULT/pgroup guarantee we can test);
           any new package dependency; process-wide signal(SIGPIPE, ...) changes;
           K/ScriptAuditLog.swift (phase 02); K/ElementSearch*.swift, K/ComputerUseService.swift,
           K/ToolDefinitions.swift, K/ComputerUseToolDispatcher.swift (phase 05);
           K/MCPServer.swift, Package.swift, any entitlements or Info.plist
```

## Acceptance

Command: `cd "$WT" && swift test --filter 'ScriptPolicyFilterTests|ConfinedChildProcessRunnerTests|OsascriptChildRunnerTests'`
Assertions (write first; they must fail before the change and pass after):

ScriptPolicyFilterTests
- `testFilterRejectsEveryDeniedForm` (table; each -> `.rejected`): `do shell script "id"`; `DO   SHELL\tSCRIPT "id"`;
  `do shell ¬\nscript "id"`; `do shell ¬\r\nscript "id"`; `run script "x"`; `load script file "x"`;
  `store script s in "x"`; `tell application "Terminal" to do script "id"`; `«event sysoexec» "id"`;
  `<<event sysoexec>> "id"`; `use framework "Foundation"`; `use scripting additions`; `use script "Lib"`;
  JavaScript: `app.doShellScript("id")`, `app.runScript("x")`, `ObjC.import("stdlib")`, `Library("x")`,
  `$.NSTask.alloc`, `Application("Terminal").doScript("id")`, `app.loadScript("x")`; and `do shell script "id"` passed
  with `language: .javascript` (union rule). Unicode and comment spellings: `do\u{00A0}shell\u{00A0}script "id"` (NBSP),
  `do shell\u{2028}script "id"`, `ｄｏ ｓｈｅｌｌ ｓｃｒｉｐｔ "id"` (fullwidth), `do (* x *) shell script "id"`,
  `do (* a *) shell (* b *) script "id"`, `« event sysoexec » "id"`, `<< event sysoexec >> "id"`,
  `do shell ¬   \nscript "id"` (trailing spaces after the continuation mark).
- `testCommentMarkerInsideStringCannotHideDeniedPhrase`: `set x to "(*" & (do shell script "id") & "*)"` -> `.rejected`.
- `testFilterAllowsPlainMailSearch`: `tell application "Mail" to get subject of (messages of inbox whose subject contains "combio")`
  -> `.allowed`; JavaScript `Application("Mail").inbox.messages.whose({subject: {_contains: "combio"}})().map(m => m.subject())`
  -> `.allowed`; `return 1 + 1` -> `.allowed`.
- `testNormalizeJoinsContinuationAndCollapsesWhitespace`: `normalize("Do Shell ¬\r\n   Script")` == `"do shell script"`.
- `testFilterRejectsDeniedPhraseInsideStringLiteral`: `... whose subject contains "do script"` -> `.rejected`
  (documented false positive, pinned on purpose).

Timing bounds (binding for every duration assertion below): a lower bound proves a floor or a wait; an upper bound
only proves "bounded, not hung", so it sits far below the child's natural run time (30s sleeps) but leaves several
seconds of headroom for a loaded shared macOS CI runner. Never tighten these upper bounds.

ConfinedChildProcessRunnerTests
- `testChildSeesOnlyStandardDescriptors`: in the parent, open `/dev/null` without CLOEXEC and `dup2` it to fd 200;
  create an AF_UNIX `socketpair` without CLOEXEC and `dup2` one end to fd 201 (stands in for the agent socket). Run
  `/bin/ls /dev/fd`. Parsed fd set contains 0, 1, 2; contains neither 200 nor 201; is a subset of {0, 1, 2, 3}
  (3 is the directory handle `ls` opens itself). Close 200/201 in teardown.
- `testChildEnvironmentIsScrubbed`: run `/usr/bin/env` with `scrubbedEnvironment(from: ["PATH": "/evil", "HOME": "/Users/x",
  "LANG": "C", "SECRET_TOKEN": "s", "OPEN_COMPUTER_USE_ENABLE_SCRIPTING": "1", "DYLD_INSERT_LIBRARIES": "/tmp/x"])`;
  the printed keys are exactly {HOME, LANG, PATH} and PATH == `/usr/bin:/bin:/usr/sbin:/sbin`.
- `testStandardInputIsDelivered`: `/bin/cat` with stdin `hello\n` -> stdout `hello\n`, exitStatus 0.
- `testTimeoutKillsChild`: `/bin/sleep 30`, timeout 0.5 -> `timedOut`, `exitStatus == nil`, `terminatingSignal != nil`,
  duration < 10.0.
- `testTermIgnoringChildIsKilled`: `/bin/sh -c 'trap "" TERM; sleep 30'`, timeout 0.5 -> `timedOut`, duration < 10.0.
- `testOutputBeyondCapDoesNotDeadlock`: `/bin/sh -c` writing 300000 `x` to stdout and 300000 `y` to stderr, timeout 10
  -> not timed out, both streams exactly 65536 bytes, both truncated flags true.
- `testRelativeExecutablePathIsRejected`: `executablePath: "osascript"` throws `.executablePathNotAbsolute`.
- `testExitStatusIsReported`: `/bin/sh -c 'exit 3'` -> exitStatus 3.
- `testLingeringDescendantDoesNotWedgeRunner`: `/bin/sh -c 'sleep 30 & echo hi; exit 0'`, timeout 20 -> returns with
  duration < 10.0, `timedOut == false`, `exitStatus == 0`, stdout starts with `hi`.
- `testBackgroundedDescendantWithShortTimeoutReturnsPromptly`: `/bin/sh -c 'sleep 30 & sleep 30'`, timeout 2 ->
  `timedOut`, duration < 10.0 + `killGracePeriod`.
- `testChildWorkingDirectoryIsRoot`: `/bin/pwd` -> stdout `/\n`.

OsascriptChildRunnerTests (real `/usr/bin/osascript`, no Apple Events to other apps)
- `testArgumentsReadSourceFromStandardInput`: `arguments(for: .applescript) == ["-l", "AppleScript", "-"]`,
  `.javascript` -> `["-l", "JavaScript", "-"]`.
- `testAppleScriptReturnsResult`: `return 1 + 1` -> resultText `2`, errorNumber nil.
- `testJavaScriptReturnsResult`: `1 + 1` -> `2`.
- `testScriptErrorNumberIsParsed`: `error "boom" number -1743` -> errorNumber -1743, timedOut false.
- `testParseErrorNumberTable`: `"...: execution error: Not authorized to send Apple events to Mail. (-1743)"` -> -1743;
  `"no number here"` -> nil.
- `testEffectiveTimeoutTable`: (nil,false)->20, (5,false)->5, (90,false)->60, (5,true)->30, (45,true)->45, (0,false)->20;
  with `firstContactFloor: 3`: (1,true)->3, (1,false)->1.
- `testDecodeOutputSurvivesSplitMultibyteCharacter`: `Data(repeating: 0x78, count: 65_535) + [0xC3]` (first byte of
  `é`) -> result is non-empty and has a prefix of 65_535 `x`.
- `testDelayScriptTimesOut`: `delay 30` with timeout 1 -> timedOut, durationMilliseconds < 12000.
- `testOversizedSourceIsRejected`: 65_537-byte source throws `.sourceTooLarge(byteCount: 65537)`.
- `testUserFacingMessageForAutomationDenied`: message for (-1743, "Mail") contains `Automation`, `System Settings`, `Mail`.

## Rollback

Delete the five new files (revert the phase commit). Nothing else references them until phase 03/04.

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
