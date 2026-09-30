# Phase 03: scripting-dictionary lookup and URL / Shortcuts launcher

Depends on: phase 01 (`ConfinedChildProcessRunner`, `ScriptRunOutcome`). Parallel group G2 (may overlap phase 02 or 05
if run in a sibling worktree). Blocks: 04. Risk: High (file disclosure via XInclude, resource exhaustion from a hostile sdef, dangerous URL handlers). Effort 5h.

## Execution constants

- `WT=/Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/fast-macos-channels`; run as `cd "$WT" && ...`.
- Test hygiene (binding): no plan ids in names/comments/commits; range-check before subscripting; fixtures are built at
  test time inside a temp directory (fake `.app` bundle with `Contents/Info.plist` and `Contents/Resources/*.sdef`); no
  `Package.swift` resource change; tests never call `NSWorkspace.open`, never run a real shortcut, never launch an app.
- Roles: tester writes Task 3.1; a different implementer does Task 3.2 and never edits the tests.

## Verified source facts (this Mac, 2026-09-29)

- Mail's sdef (`/System/Applications/Mail.app/Contents/Resources/Mail.sdef:4,13`) uses namespace
  `http://www.w3.org/2003/XInclude`, an `href` of `file://localhost/System/Library/ScriptingDefinitions/CocoaStandard.sdef`,
  and an XPath-style `xpointer(/dictionary/suite/node()[not(self::command and ((@name = 'delete') or ...))])`. The
  include sits inside a `<suite>` element.
- `/System/Library/ScriptingDefinitions/` holds one file, `CocoaStandard.sdef` (suite `Standard Suite`).
- The DOCTYPE references `file://localhost/System/Library/DTDs/sdef.dtd`; it must not be loaded.
- `OSAScriptingDefinition` is not always a file name with an extension: Messages.app has `Messages` while the file on
  disk is `Messages.sdef`; Notes has `Notes.sdef`, Calendar `iCal.sdef` (PlistBuddy, this Mac).
- Every `xpointer` in `/System/Applications/*.app/Contents/Resources/*.sdef` has one of three shapes: `/dictionary/suite`,
  `/dictionary/suite/node()[not(self::command and @name = 'save')]`, or the parenthesised or-chain
  `/dictionary/suite/node()[not(self::command and ((@name = 'delete') or (@name = 'duplicate') or (@name = 'move')))]`
  (grep, this Mac).

## Task 3.1 (tester): failing tests first

- Goal: `T/ScriptingDictionaryLookupTests.swift` and `T/ShortcutAndUrlLauncherTests.swift`.
- Verify (RED is the pass condition): `cd "$WT" && swift build --build-tests 2>&1 | tail -40` exits non-zero and the
  output contains `error:` and `ScriptingDictionaryLookup` or `ShortcutAndUrlLauncher`.

## Task 3.2 (implementer): make them pass

- Target files: new `K/ScriptingDictionaryLookup.swift`, new `K/ShortcutAndUrlLauncher.swift`.
- Steps, `ScriptingDictionaryLookup`:
  1. `definitionURL(appBundleURL:)`: read `Contents/Info.plist` key `OSAScriptingDefinition`; if the value has no path
     extension, append `.sdef`; resolve under `Contents/Resources/`; `realpath` both the bundle and the file; require the
     file path to start with the bundle's real path + `/`; else throw `.definitionOutsideBundle`. Missing key -> the
     first (sorted by name) regular `*.sdef` file directly inside `Contents/Resources/`, with the same `realpath` check;
     none -> return nil. This is a static read only.
  2. `readDefinitionFile(_:)`: `open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)`; `fstat` the fd: must be a
     regular file (a FIFO, device or directory throws `.definitionNotRegularFile`) with `st_size <=
     maximumDefinitionBytes` (else `.definitionTooLarge`); read exactly that many bytes; close. Never
     `Data(contentsOf:)`, which blocks forever on a FIFO. Parse with
     `XMLDocument(data:options: [.nodeLoadExternalEntitiesNever])`; never pass a URL to `XMLDocument` and never set
     `.documentXInclude`.
  3. Resolve includes by hand, depth <= `maximumIncludeDepth`, at most `maximumIncludesPerDocument` include elements
     per document (the rest are skipped with one note), and a running total of loaded bytes across the whole expansion
     capped at `maximumExpandedBytes` (further includes are skipped with a note). For every element with local name
     `include` in namespace
     `http://www.w3.org/2003/XInclude` or `http://www.w3.org/2001/XInclude`:
     - `href` must be a `file:` URL (host empty or `localhost`) or a relative path; any other scheme -> skip.
     - Relative paths resolve against the including file's directory. `realpath` the target.
     - Allowed only if `isAllowedIncludePath(resolved, bundleRoot:)`: under the bundle real path + `/` or under an entry
       of `allowedIncludeRoots` + `/`. Otherwise skip.
     - Load the target the same way (step 2). No `xpointer` -> take the included root's children. With `xpointer`,
       accept only the three verified shapes, matched as a whole string by `isSupportedXPointer(_:)`: exactly
       `xpointer(/dictionary/suite)`, or `xpointer(/dictionary/suite/node()[not(self::command and <names>)])` where
       `<names>` is either `@name = '<w>'` or `(<one>( or <one>)*)` with `<one>` = `(@name = '<w>')` and `<w>` matching
       `[A-Za-z ]{1,40}`. Only a supported expression is evaluated with `nodes(forXPath:)`; any other expression is
       skipped with the note `unsupported xpointer`. Copy the resulting nodes in place of the include element.
       XPath error -> skip.
     - Every skip replaces the include with nothing and adds one note `include skipped: <reason>` to the summary.
  4. `summary(appBundleURL:term:)`: suites -> commands (name, description, direct parameter type, parameters with
     name/type/optional) and classes (name, description, properties name:type, elements). `term` filters
     case-insensitively on names and descriptions. Cap the output at `maximumSummaryCharacters`, ending with
     `... (truncated; pass term to narrow)` when cut. `definitionURL` nil -> throw `.noScriptingDefinition` with the
     text `<app> has no static scripting dictionary (no .sdef in its bundle)`.
  5. No in-process `OSACopyScriptingDefinitionFromURL` fallback. For dynamic-terminology apps it may send an Apple Event
     to the target or launch it from the relay, which a read-only, auto-allowed tool must never do, and it may expand
     XIncludes before step 3 sees them. Apps with only legacy `aete` or dynamic terminology get
     `.noScriptingDefinition`; `run_script` still works for them. Static-only lookup accepted by the user
     (2026-09-29).
  6. `locateAppBundle(_:)`: running app whose localized name or bundle id matches (case-insensitive) -> `bundleURL`;
     else `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)`; else first existing of
     `/Applications/<q>.app`, `/System/Applications/<q>.app`, `/System/Applications/Utilities/<q>.app`.
- Steps, launcher:
  1. `UrlOpenPolicy.evaluate`: reject when the URL has no scheme, when the lowercased scheme is in `blockedSchemes`, when
     `handlerResolver` returns nil, when the handler path extension is not `app`, or when its bundle id (compared
     lowercased) is in `blockedHandlerBundleIdentifiers`. Rejections carry a reason string naming the rule. Doc comment:
     this policy is friction, not a boundary; `run_script` can still `open location` or drive Finder.
  2. `openURL(_:)`: parse with `URL(string:)`; evaluate; only on `.allowed(handler:)` call `opener(url, handler)` once,
     so the app that was checked is the app that opens the URL (no second handler resolution); return
     `Opened <url> with <handler app name>.`; throw `.rejected(reason)` otherwise, and `.openFailed` when `opener`
     returns false. The default `opener` calls `NSWorkspace.shared.open([url], withApplicationAt: handler,
     configuration: NSWorkspace.OpenConfiguration())` and waits on a semaphore for its completion handler for at most
     10s.
  3. `runShortcut`: reject empty names and names starting with `-` (`.invalidShortcutName`). If `input` is non-nil, create
     a private temp dir (0700) under `temporaryRoot`, write `input.txt` at 0600, pass
     `shortcutRunArguments(name:inputPath:)`, and remove the temp dir in `defer`. Run through
     `ConfinedChildProcessRunner` with `scrubbedEnvironment(from: baseEnvironment)`; map to `ScriptRunOutcome`
     (`errorNumber` nil).
  4. `listShortcuts(timeout:)`: `shortcuts list` via the same runner; return stdout.
- Verify:
  1. `cd "$WT" && swift test --filter 'ScriptingDictionaryLookupTests|ShortcutAndUrlLauncherTests' 2>&1 | tail -30`
     exits 0 and prints `with 0 failures`.
  2. `cd "$WT" && swift build && swift test 2>&1 | tail -15` exits 0 and prints `with 0 failures`.
  3. `cd "$WT" && grep -nE "documentXInclude|OSACopyScriptingDefinition|contentsOf:" packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ScriptingDictionaryLookup.swift`
     prints nothing.

## Signature

```swift
// K/ScriptingDictionaryLookup.swift
public enum ScriptingDictionaryLookupError: Error, Equatable {
    case appNotFound(String)
    case noScriptingDefinition(String)
    case definitionOutsideBundle(String)
    case definitionTooLarge(Int)
    case definitionNotRegularFile(String)
    case malformedDefinition(String)
}

public struct ScriptingDictionaryLookup {
    public static let allowedIncludeRoots: [String]       // ["/System/Library/ScriptingDefinitions"]
    public static let maximumIncludeDepth: Int            // 2
    public static let maximumIncludesPerDocument: Int     // 16
    public static let maximumDefinitionBytes: Int         // 4 * 1024 * 1024
    public static let maximumExpandedBytes: Int           // 8 * 1024 * 1024
    public static let maximumSummaryCharacters: Int       // 16_000
    public init()
    public func summary(appBundleURL: URL, term: String?) throws -> String
    static func definitionURL(appBundleURL: URL) throws -> URL?
    static func readDefinitionFile(_ url: URL) throws -> Data
    static func isAllowedIncludePath(_ resolvedPath: String, bundleRoot: String) -> Bool
    static func isSupportedXPointer(_ attribute: String) -> Bool
    public static func locateAppBundle(_ query: String) -> URL?
}

// K/ShortcutAndUrlLauncher.swift
public enum UrlOpenVerdict: Equatable {
    case allowed(handler: URL)
    case rejected(String)
}

public enum UrlOpenPolicy {
    public static let blockedSchemes: Set<String>
        // ["file", "shortcuts", "x-man-page", "ssh", "telnet",
        //  "smb", "afp", "nfs", "cifs", "ftp", "ftps", "sftp", "vnc", "help"]
    public static let blockedHandlerBundleIdentifiers: Set<String> // stored lowercased
        // verified on this Mac: "com.apple.terminal", "com.apple.scripteditor2", "com.apple.shortcuts",
        //   "com.apple.automator", "com.apple.netauthagent", "com.microsoft.vscode", "com.runningwithcrayons.alfred"
        // [UNVERIFIED, app not installed here; confirm in phase 10 with PlistBuddy where available]:
        //   "com.googlecode.iterm2", "com.apple.screensharing", "com.apple.helpviewer",
        //   "com.todesktop.230313mzl4w4u92" (Cursor), "com.raycast.macos", "org.hammerspoon.hammerspoon",
        //   "com.hegenberg.bettertouchtool", "com.stairways.keyboardmaestro.engine"
    public static func evaluate(
        _ url: URL,
        handlerResolver: (URL) -> URL?,
        bundleIdentifierResolver: (URL) -> String?
    ) -> UrlOpenVerdict
}

public enum ShortcutAndUrlLauncherError: Error, Equatable {
    case invalidURL(String)
    case rejected(String)
    case openFailed(String)
    case invalidShortcutName(String)
}

public struct ShortcutAndUrlLauncher {
    public static let defaultShortcutsExecutablePath: String   // "/usr/bin/shortcuts"
    public init(
        handlerResolver: @escaping (URL) -> URL? = { NSWorkspace.shared.urlForApplication(toOpen: $0) },
        bundleIdentifierResolver: @escaping (URL) -> String? = { Bundle(url: $0)?.bundleIdentifier },
        opener: @escaping (_ url: URL, _ handler: URL) -> Bool = ShortcutAndUrlLauncher.openWithCheckedHandler,
        shortcutsExecutablePath: String = ShortcutAndUrlLauncher.defaultShortcutsExecutablePath,
        temporaryRoot: URL = FileManager.default.temporaryDirectory,
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment
    )
    public func openURL(_ rawURL: String) throws -> String
    public func runShortcut(name: String, input: String?, timeout: TimeInterval) throws -> ScriptRunOutcome
    public func listShortcuts(timeout: TimeInterval) throws -> String
    public static func openWithCheckedHandler(_ url: URL, handler: URL) -> Bool
    static func shortcutRunArguments(name: String, inputPath: String?) -> [String]
        // ["run", name] or ["run", name, "--input-path", inputPath]
}
```

## Boundaries

```
TARGET:    K/ScriptingDictionaryLookup.swift, K/ShortcutAndUrlLauncher.swift,
           T/ScriptingDictionaryLookupTests.swift, T/ShortcutAndUrlLauncherTests.swift
READ-ONLY: K/ConfinedChildProcessRunner.swift, K/OsascriptChildRunner.swift (phase 01), K/AppDiscovery.swift
FORBIDDEN: /usr/bin/sdef (xcrun shim, 1.67s, needs developer tools); XMLDocument(contentsOf:) or any URL-based load;
           Data(contentsOf:) for definition files; `.documentXInclude`; OSACopyScriptingDefinitionFromURL or any
           other in-process call that can send an Apple Event or launch the target; NSWorkspace.open(_:) without an
           explicit handler URL;
           an allowlist of URL schemes (would defeat decision 7); editing phase 01/02/05 files;
           K/MCPServer.swift, K/ToolDefinitions.swift, K/ComputerUseToolDispatcher.swift
```

## Acceptance

Command: `cd "$WT" && swift test --filter 'ScriptingDictionaryLookupTests|ShortcutAndUrlLauncherTests'`
Assertions (write first; must fail before, pass after):

ScriptingDictionaryLookupTests (fake bundle `Fake.app` in a temp dir)
- `testSummaryListsCommandsAndClasses`: sdef with suite `Fake Suite`, command `search mailbox`, class `message` with
  property `subject:text` -> summary contains all four names.
- `testTermFiltersSummary`: `term: "search"` -> contains `search mailbox`, does not contain `message`.
- `testAllowedSystemIncludeIsResolved`: include `file://localhost/System/Library/ScriptingDefinitions/CocoaStandard.sdef`
  with `xpointer(/dictionary/suite/node()[not(self::command and ((@name = 'delete')))])` inside a suite -> summary
  contains `count` and does not list a `delete` command.
- `testIncludeOutsideAllowedRootsIsSkipped`: include of a valid sdef placed in the temp dir OUTSIDE the bundle defining
  command `leakedcommand` -> summary lacks `leakedcommand` and contains `include skipped`.
- `testTraversalAndSymlinkIncludesAreSkipped`: relative `../outside.sdef` and an in-bundle symlink pointing outside ->
  both skipped (`leakedcommand` absent).
- `testNonFileIncludeSchemeIsSkipped`: `href="http://127.0.0.1:9/x.sdef"` -> skipped; test finishes in < 10s (bounded, not hung;
  CI headroom).
- `testExternalEntityIsNotLoaded`: DOCTYPE declaring `<!ENTITY leak SYSTEM "file:///<tempdir>/secret.txt">` (file
  contains `TOPSECRET`) and `&leak;` in a description -> summary lacks `TOPSECRET`.
- `testDefinitionOutsideBundleIsRefused`: `OSAScriptingDefinition = ../../outside.sdef` -> throws
  `.definitionOutsideBundle`.
- `testSummaryIsCapped`: 2000 generated commands -> summary length <= 16_000 + 60 and ends with `truncated`.
- `testExtensionlessDefinitionKeyResolves`: `OSAScriptingDefinition = Fake`, file `Contents/Resources/Fake.sdef` ->
  summary lists its command.
- `testAppWithoutKeyUsesBundledSdef`: no key, `Contents/Resources/Other.sdef` present -> summary lists its command.
- `testAppWithoutAnySdefThrowsNoScriptingDefinition`: no key, no `.sdef` -> throws `.noScriptingDefinition`.
- `testIncludeDepthIsBounded`: A includes B includes C includes D (all in bundle) -> no hang, a skip note present.
- `testIncludeCountIsBounded`: one suite holding 100 includes of the same small in-bundle sdef -> finishes in < 10s and
  the summary contains `include skipped` (count cap).
- `testUnsupportedXPointerIsSkipped`: include with `xpointer="xpointer(//*)"` and one with
  `xpointer="xpointer(/dictionary/suite[1]/command[1])"` -> both skipped with `unsupported xpointer`.
- `testSupportedXPointerShapes`: `isSupportedXPointer` is true for the three verified shapes (single name, or-chain of
  three, bare `/dictionary/suite`), false for `xpointer(//*)`, `xpointer(/dictionary/suite/node()[not(self::command and
  @name = 'x' or 1=1)])` and an empty string.
- `testFifoDefinitionIsRefusedWithoutBlocking`: `mkfifo` at `Contents/Resources/Fake.sdef` (no writer) -> throws
  `.definitionNotRegularFile` within 10s (a blocking open never returns).

ShortcutAndUrlLauncherTests (injected resolver maps; `opener` records calls)
- `testUrlPolicyTable`: `file:///etc/hosts`, `FILE:///etc/hosts`, `ssh://h`, `telnet://h`, `x-man-page://ls`,
  `shortcuts://run-shortcut?name=x`, `smb://h/s`, `afp://h/s`, `nfs://h/s`, `cifs://h/s`, `ftp://h/f`, `vnc://h`,
  `help:anchor=x` -> rejected; `myterm://x` resolved to a `.app` with id `com.apple.Terminal` -> rejected; same for
  every entry of `blockedHandlerBundleIdentifiers` (loop over the set, and once with an upper-case variant of an id);
  handler nil -> rejected; handler `/tmp/evil.command` -> rejected; `https://example.com` -> Safari `.app`, allowed.
- `testOpenerIsCalledOnlyWhenAllowed`: across the table, `opener` call count == number of allowed URLs (1).
- `testOpenerReceivesTheCheckedHandler`: resolver maps `https://example.com` to `/Applications/Safari.app`; the recorded
  `opener` call receives exactly that handler URL.
- `testShortcutNameCannotInjectOptions`: names `-i`, `--output-path` and `` -> throw `.invalidShortcutName`.
- `testShortcutRunArguments`: (`Mail Digest`, nil) -> `["run", "Mail Digest"]`; with path -> adds
  `["--input-path", path]`.
- `testShortcutInputFileIsPrivateAndRemoved`: `shortcutsExecutablePath: "/bin/sh"` is not usable (args differ), so use
  a temp executable script (mode 0700) that writes `stat -f %Lp` of its 4th argument into a marker file; after
  `runShortcut(name: "x", input: "hi", timeout: 5)` the marker reads `600` and the temp input dir under `temporaryRoot`
  no longer exists.

## Rollback

Revert the phase commit (four new files). Nothing references them before phase 04.

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
