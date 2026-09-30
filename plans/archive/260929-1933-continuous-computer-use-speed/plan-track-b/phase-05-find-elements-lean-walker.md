# Phase 05: `find_elements` lean walker and snapshot merge (agent side)

Depends on: phase 00. Parallel group G1 (with 01 and 02; disjoint files). **Cook this phase first in G1**, so the
main loop can take the early live ratio probe (phase 10, "Early probe") before G2 starts. Blocks: 06, 07.
Risk: Medium-High (stale-index resolution, row forgery by injected AX text, focus loss on hits-only snapshots,
off-window hits clicked at an off-window point, Track A clash in shared files, the <=50% target). Effort 7.25h.
Residual (documented): hit indices stay above existing keys only while full trees stay below the 1M base plus the
seed offset; `max_tree_nodes` is unbounded (`K/ComputerUseToolDispatcher.swift:70`), but `allocate(above:)` always
allocates above the cached snapshot's highest key, so a collision needs a later, larger refresh, which drops the hits
anyway.
**Touches files Track A also edits** (append-only regions): `ComputerUseService.swift`, `ToolDefinitions.swift`,
`ComputerUseToolDispatcher.swift`, and the count sites in `OpenComputerUseKitTests.swift` / `DecisionAdvisorTests.swift`.

## Execution constants

- `WT=/Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/fast-macos-channels`; run as `cd "$WT" && ...`.
- Test hygiene (binding): no plan ids in names/comments/commits; range-check before subscripting; the walker is tested
  through a fake node source only (no live AX, no running app, no TCC); never call an MCP tool or start the agent.
- Roles: tester writes Task 5.1; a different implementer does Task 5.2 and never edits the new test file. The count-site
  edits in existing test files belong to the tester (Task 5.1 step 3).

## Verified source facts

- `AppSnapshot` is a struct of `let`s with an internal memberwise init (`K/AccessibilitySnapshot.swift:105-121`);
  `elements` is `[Int: ElementRecord]`, so lookup is optional and cannot trap (`K/ComputerUseService.swift:997-1003`).
- `snapshotsByApp`, `currentSnapshot`, `refreshSnapshot`, `lookupElement` are `private` (`K/ComputerUseService.swift:460,
  961, 970, 997`). Swift lets an extension **in the same file** use them, so the service hook is an extension appended
  at the end of `ComputerUseService.swift`: no visibility change and no edit near Track A's `refreshSnapshot` rewrite.
- `refreshSnapshot` stores one snapshot under three keys: query, app name, bundle id, all lowercased (`:984-992`).
- Reusable internal helpers: `childTraversalAttributes` (`K/AccessibilitySnapshot.swift:1199`), `meaningfulActions`
  (`:2019`), `windowRelativeFrame` (`:1978`), `sanitizeText(_:textLimit:)` (`:2186`, escapes `\n` only, caps at
  `defaultTextLimit` 500, `:73`), `WindowCaptureCandidate` (`:679`), `preferredWindowCaptureCandidate` (`:689`).
  `CGRect.renderedLocalFrame` (`:2341-2345`) is inside a `private extension`, so it is NOT reusable from another file;
  this phase keeps a private copy (`elementSearchRenderedFrame`) that renders the same
  `x=<Int>, y=<Int>, w=<Int>, h=<Int>` text, pinned by a literal in `testRowFormat`, and phase 09 lists it for dedupe.
- `typeText` reads the cached snapshot (`K/ComputerUseService.swift:876`, `currentSnapshot`) and needs
  `snapshot.focusedElement` (`:1535-1536`, `:1556-1557`); with focus nil it falls into the branch that activates the
  target app and then restores the previous one (`:886-896`). A hits-only snapshot must therefore carry focus.
- `click` converts a record's `localFrame` with the cached snapshot's `windowBounds` (`:647-653`), so a merge is valid
  only when the window has not moved since the cached refresh.
- The click point is the midpoint of `localFrame` (`clickPoint`, `K/ComputerUseService.swift:154-166`); a nil
  `localFrame` makes `click` throw `element <n> has no clickable frame` (`:649-651`) before any event is posted.
  `windowPointToGlobalPoint` only adds the window origin (no window-bounds guard), and auto-click then hit-tests and
  posts a pid-targeted click at that point (`:660-677`). A hit whose frame lies outside the window (a table row scrolled
  out of view) would therefore be a wrong click or a silent no-op. `visibleRows` (`K/AccessibilitySnapshot.swift:2297`)
  is private, so the walker cannot reuse it.
- Fixture snapshots have `targetWindowID: nil` and `mode: .fixture` (`K/AccessibilitySnapshot.swift:568-575`); the
  fixture app name is `FixtureBridge.appName` (`K/FixtureBridge.swift:111`). `WindowCapture` (`:594`) is private and captures an image, so this phase
  reads the CGWindowList itself (no capture). `shouldSkipChild` (`:1223`, private) only affects the menu bar; the walker
  walks the window only, so it is not needed.
- `AXUIElementCopyMultipleAttributeValues` is used nowhere today (brainstorm §1).
- Full-tree indices are `< max_tree_nodes`, which is an unbounded positive int (`K/ComputerUseToolDispatcher.swift:70`);
  hence hit indices start at 1_000_000 and are always allocated above the highest existing key.
- A fresh `refreshSnapshot` (every action and `get_app_state`) replaces the merged snapshot, so hits live until the next
  refresh. This is intended and documented in the tool description.

## Task 5.1 (tester): failing tests first, plus count sites

- Goal: `T/ElementSearchTests.swift` and the updated count assertions.
- Steps:
  1. Write every assertion under Acceptance in `T/ElementSearchTests.swift`, with a `FakeElementNodeSource` whose nodes
     are value-type ids and which counts `read` calls.
  2. The dispatcher lock test: add `"find_elements"` to the `guiTools` list and change `XCTAssertEqual(guiTools.count, 9)`
     to 10 (`T/OpenComputerUseKitTests.swift:2964-2966`).
  3. Count sites: `T/OpenComputerUseKitTests.swift:256` 9 -> 10; `T/DecisionAdvisorTests.swift:436` rename
     `testToolDefinitionsAllStaysNineAndExcludesDecideNextAction` -> `testToolDefinitionsAllStaysTenAndExcludesDecideNextAction`,
     `:437` 9 -> 10; `:448` 10 -> 11; `:455` rename `...StaysAtNine` -> `...StaysAtTen`, `:457` 9 -> 10.
- Verify (RED is the pass condition): `cd "$WT" && swift build --build-tests 2>&1 | tail -40` exits non-zero and the
  output contains `error:` and `ElementSearch`.

## Task 5.2 (implementer): make them pass

- Target files: new `K/ElementSearchWalker.swift`, `K/ElementSearchAccessibilitySource.swift`,
  `K/ElementSearchSnapshotMerge.swift`; append to `K/ComputerUseService.swift` (end of file only);
  `K/ToolDefinitions.swift` (append one element at the end of `all`, before `]` at :156);
  `K/ComputerUseToolDispatcher.swift` (one `case` before `default:` at :128).
- Steps:
  1. `ElementSearchQuery.init` throws `ComputerUseError.invalidArguments` when role, label and identifier are all nil or
     empty (`find_elements needs at least one of role, label or identifier`), when `maxResults` is outside
     1...20, or `maxNodes` outside 1...10_000.
  2. `matches`: every provided criterion must hold. Role: case-insensitive equality after stripping a leading `AX` from
     both sides (`button` == `AXButton`). Label: compared to title OR description. Identifier: identifier. Mode `exact` =
     case-insensitive equality; `contains` = case-insensitive substring.
  3. `ElementSearchWalker.search`: iterative breadth-first walk from `root` (FIFO queue with a head index; children
     enqueued in document order); exactly one `source.read` per visited node;
     skip a child that `isSameNode` as any ancestor; stop when `hits.count == maxResults` (`stoppedAtMaxResults`) or
     `nodesVisited == maxNodes` with nodes still pending (`truncated`); do not descend below `maxDepth`. Hits come
     back shallowest first, then in document order. (Originally pre-order DFS; switched 2026-09-30 through the
     pre-approved walk-order lever after the live Mail probe read 216 of ~238 nodes for a toolbar button, see
     impl-notes "Breadth-first walk". Toolbar-first priority and iterative deepening were rejected.) Raising
     `defaultMaxNodes` is not a lever.
  4. `AccessibilityElementSearchSource.read`: ONE `AXUIElementCopyMultipleAttributeValues` call for
     `batchedAttributes`; attribute errors come back as placeholder values and map to nil. Children:
     `childTraversalAttributes(role:hasRows:hasVisibleChildren:)` over the already-fetched arrays (no further reads),
     rows capped at `rowCap` (first 20; no visibility filter, documented), de-duplicated with `CFEqual`. Off-window
     rows are made unclickable by step 6, not filtered here.
  5. `resolveElementSearchWindow(for:)`: AX focused window of the app element, else the first `AXWindows` entry with role
     `AXWindow`; no activation, no recovery, no capture. Also read the app element's `AXFocusedUIElement` once into
     `focusedElement` (nil on error). Window id/layer/bounds from `CGWindowListCopyWindowInfo([],
     kCGNullWindowID)` candidates for the pid chosen with `preferredWindowCaptureCandidate(_:titleHint:)`. No window ->
     `ComputerUseError.stateUnavailable`.
  6. `readElementSearchHitDetails`: one multi-read for `AXPosition` + `AXSize`, one `AXUIElementCopyActionNames`; local
     frame via the pure helper `elementSearchClickableLocalFrame(elementFrame:windowBounds:)`: it computes
     `windowRelativeFrame` and returns it only when that frame's midpoint lies inside
     `CGRect(origin: .zero, size: windowBounds.size)`; otherwise nil. An off-window hit is still listed (its row omits
     `frame=`), but `click` on it fails with `no clickable frame` instead of clicking outside the window. (Chosen over
     fetching `AXVisibleRows` in the batch: the guard covers every role, not only table, outline and list, and needs
     no extra attribute.)
  7. `ElementSearchIndexAllocator.shared.allocate(count:above:)`: under an `NSLock`, returns `count` consecutive indices
     starting at `max(next, base, (above ?? 0) + 1)`; `next` only grows and never resets inside one process. The shared
     instance seeds `next` per process as `base + (Int(Date().timeIntervalSince1970) % 100_000) * 100`, so an index an
     agent kept from before an agent restart is unlikely to name a new element (not impossible: document it). An
     internal `init(initialNext:)` exists for tests.
  8. `canMergeElementSearchHits(into:window:)` is true only when `cached` is non-nil, `cached.mode == .accessibility`,
     `cached.targetWindowID != nil`, `cached.targetWindowID == window.windowID` AND `cached.windowBounds ==
     window.bounds`. `mergeElementSearchHits`: when it is true, return a new `AppSnapshot` equal to `cached` with
     `elements` = cached elements plus hits (all other fields unchanged, including focus, `treeLines` and
     `treeLineOffsets`). Otherwise return a hits-only snapshot: app, `window.title`, `window.bounds`, `window.windowID`,
     `window.layer`, `screenshotPNGData: nil`, `mode: .accessibility`, `treeLines: rows`, `treeLineOffsets: [:]`,
     `focusedElement: window.focusedElement`, `focusedSummary: nil`, `selectedText: nil`, `elements` = hits.
  9. Row format (also the tool output): `[<index>] <role> "<label>" id=<identifier> frame=<elementSearchRenderedFrame>
     actions=<meaningfulActions joined by ", ">` (omit empty parts). Every AX-sourced string (role, label, identifier,
     window title, app name) goes through `escapeElementSearchText(_:)`: `sanitizeText(_:)` (escapes `\n`, caps at 500
     characters), then each CR becomes the two characters backslash + `r`, U+2028 / U+2029 become the text `\u2028` /
     `\u2029`, and `"` becomes backslash + `"`. Injected page or
     email text therefore cannot start a new row or close the quoted label. Header: `App=<bundle id or name> (pid <pid>)`,
     `Window: "<title>", App: <name>.`, then `find_elements: <n> match(es), nodes_visited=<v>, truncated=<bool>. These
     element_index values work with click, set_value, scroll and perform_secondary_action until the next state refresh.`
  10. Service extension `findElements`: `AppDiscovery.resolve(query)`; if `app.name == FixtureBridge.appName` throw
      `ComputerUseError.invalidArguments("find_elements is not available for the fixture app; use get_app_state")`
      (a hits-only snapshot would drop the fixture indices and bypass `FixtureBridge`); require `PermissionDiagnostics.current().accessibilityTrusted`
      (same message as `SnapshotBuilder.build`); resolve window; walk; allocate indices above the cached snapshot's max
      key; build `ElementRecord`s (identifier, element, localFrame, role, rawActions, prettyActions =
      `meaningfulActions(raw, role:)`); merge with `snapshotsByApp[query.lowercased()]`; store under the same three keys
      `refreshSnapshot` uses, computed by the pure helper `snapshotCacheKeys(query:app:)` (same rule as
      `K/ComputerUseService.swift:984-988`: query, app name and bundle id, lowercased, empties dropped). This loop is
      the only other writer of `snapshotsByApp`; phase 09 folds both writers into one `storeSnapshot` helper after
      PR A merges. Return `ToolCallResult.text` (no image).
  11. `ToolDefinitions`: `find_elements`, read-only annotations, schema {app*, role, label, identifier, match enum
      [exact, contains], max_results integer 1-20, max_nodes integer >= 1}; description ends with
      `This tool is part of plugin \`Computer Use\`.`
  12. Dispatcher case `find_elements`: build `ElementSearchQuery` from args (`match` default `contains`, parse via
      `ElementSearchQuery.MatchMode(argument:)`) BEFORE calling the service, so bad args fail without AX.
- Verify:
  1. `cd "$WT" && swift test --filter 'ElementSearchTests|DecisionAdvisorTests|OpenComputerUseKitTests' 2>&1 | tail -30`
     exits 0 and prints `with 0 failures`.
  2. `cd "$WT" && swift build && swift test 2>&1 | tail -15` exits 0 and prints `with 0 failures`.
  3. `cd "$WT" && git diff --stat afb60fa -- packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
     prints nothing (file untouched).

## Signature

```swift
// K/ElementSearchWalker.swift
public struct ElementSearchQuery: Equatable, Sendable {
    public enum MatchMode: String, Sendable {
        case exact
        case contains
        public init(argument: String?) throws   // nil -> .contains; unknown -> ComputerUseError.invalidArguments
    }
    public static let defaultMaxResults: Int   // 5
    public static let maximumMaxResults: Int   // 20
    public static let defaultMaxNodes: Int     // 1200
    public static let maximumMaxNodes: Int     // 10_000
    public let role: String?
    public let label: String?
    public let identifier: String?
    public let matchMode: MatchMode
    public let maxResults: Int
    public let maxNodes: Int
    public init(role: String?, label: String?, identifier: String?, matchMode: MatchMode = .contains,
                maxResults: Int = ElementSearchQuery.defaultMaxResults,
                maxNodes: Int = ElementSearchQuery.defaultMaxNodes) throws
    func matches(_ attributes: ElementSearchNodeAttributes) -> Bool
}

struct ElementSearchNodeAttributes: Equatable {
    var role: String?
    var subrole: String?
    var title: String?
    var description: String?
    var identifier: String?
    var enabled: Bool?
}

protocol ElementSearchNodeSource {
    associatedtype Node
    func read(_ node: Node) -> (attributes: ElementSearchNodeAttributes, children: [Node])
    func isSameNode(_ lhs: Node, _ rhs: Node) -> Bool
}

struct ElementSearchHit<Node> {
    let node: Node
    let attributes: ElementSearchNodeAttributes
}

struct ElementSearchOutcome<Node> {
    let hits: [ElementSearchHit<Node>]
    let nodesVisited: Int
    let truncated: Bool
    let stoppedAtMaxResults: Bool
}

enum ElementSearchWalker {
    static func search<Source: ElementSearchNodeSource>(
        root: Source.Node, source: Source, query: ElementSearchQuery,
        maxDepth: Int = AccessibilityTreeLimits.defaultMaxDepth
    ) -> ElementSearchOutcome<Source.Node>
}

// K/ElementSearchAccessibilitySource.swift
struct AccessibilityElementSearchSource: ElementSearchNodeSource {
    typealias Node = AXUIElement
    static let batchedAttributes: [String]   // role, subrole, title, description, identifier, enabled,
                                             // AXChildren, AXRows, AXContents, AXVisibleChildren
    static let rowCap: Int                   // 20
    func read(_ node: AXUIElement) -> (attributes: ElementSearchNodeAttributes, children: [AXUIElement])
    func isSameNode(_ lhs: AXUIElement, _ rhs: AXUIElement) -> Bool   // CFEqual
}

struct ElementSearchWindowContext {
    let root: AXUIElement
    let windowID: CGWindowID
    let layer: Int
    let bounds: CGRect
    let title: String?
    let focusedElement: AXUIElement?
}

func resolveElementSearchWindow(for app: RunningAppDescriptor) throws -> ElementSearchWindowContext
func readElementSearchHitDetails(_ element: AXUIElement, windowBounds: CGRect) -> (localFrame: CGRect?, rawActions: [String])
func elementSearchClickableLocalFrame(elementFrame: CGRect, windowBounds: CGRect) -> CGRect?   // nil when the midpoint is off-window

// K/ElementSearchSnapshotMerge.swift
final class ElementSearchIndexAllocator: @unchecked Sendable {
    static let shared: ElementSearchIndexAllocator         // seeded per process, see step 7
    static let base: Int                                   // 1_000_000
    init(initialNext: Int)
    func allocate(count: Int, above existingMaximum: Int?) -> [Int]
}

typealias ElementSearchWindowInfo = (
    windowID: CGWindowID?, layer: Int?, bounds: CGRect?, title: String?, focusedElement: AXUIElement?
)

func canMergeElementSearchHits(into cached: AppSnapshot?, window: ElementSearchWindowInfo) -> Bool

func mergeElementSearchHits(
    _ hits: [ElementRecord], rows: [String], into cached: AppSnapshot?,
    window: ElementSearchWindowInfo, app: RunningAppDescriptor
) -> AppSnapshot

func snapshotCacheKeys(query: String, app: RunningAppDescriptor) -> Set<String>

func escapeElementSearchText(_ value: String) -> String

func elementSearchRenderedFrame(_ frame: CGRect) -> String   // "x=<Int>, y=<Int>, w=<Int>, h=<Int>"

func renderElementSearchRow(index: Int, attributes: ElementSearchNodeAttributes, localFrame: CGRect?, prettyActions: [String]) -> String

// K/ComputerUseService.swift (appended extension at end of file)
extension ComputerUseService {
    public func findElements(app query: String, search: ElementSearchQuery) throws -> ToolCallResult
}
```

## Boundaries

```
TARGET:    K/ElementSearchWalker.swift, K/ElementSearchAccessibilitySource.swift, K/ElementSearchSnapshotMerge.swift,
           K/ComputerUseService.swift (append-only, end of file), K/ToolDefinitions.swift (one element appended to `all`),
           K/ComputerUseToolDispatcher.swift (one case before `default:`),
           T/ElementSearchTests.swift, T/OpenComputerUseKitTests.swift (:256, :2964-2966 only),
           T/DecisionAdvisorTests.swift (:436-437, :448, :455-457 only)
READ-ONLY: K/AccessibilitySnapshot.swift, K/AppDiscovery.swift, K/Permissions.swift, K/Errors.swift, K/FixtureBridge.swift
FORBIDDEN: any edit to K/AccessibilitySnapshot.swift (Track A owns capture + batched reads; dedupe happens in phase 09);
           any edit inside existing ComputerUseService methods or the class body (Track A rewrites refreshSnapshot and
           the action path); changing visibility of existing symbols; adding find_elements to `listed` instead of `all`
           (would trip `K/MCPServer.swift:26` and leak the cascade guide); capping or changing `max_tree_nodes`;
           screenshots or window recovery/activation in find_elements; phase 01-04 files; K/MCPServer.swift (phase 07)
```

## Acceptance

Command: `cd "$WT" && swift test --filter 'ElementSearchTests|DecisionAdvisorTests|OpenComputerUseKitTests'`
Assertions (write first; must fail before, pass after):
- `testLabelMatchesTitleOrDescription`: node with title `Search` and node with description `Search` both match
  `label: "search"`; exact mode rejects `Search mailbox`, contains mode accepts it.
- `testRoleMatchIgnoresAXPrefixAndCase`: `role: "button"` matches `AXButton`; `role: "AXButton"` does not match `AXButtons`.
- `testAllCriteriaMustHold`: role + label, only one holding -> no match.
- `testQueryRequiresACriterion`: all nil throws; `maxResults: 21` throws; `maxNodes: 0` throws.
- `testWalkStopsAtMaxResults`: 100-node fake tree, 3 matches early, `maxResults: 1` -> 1 hit, `stoppedAtMaxResults`,
  `nodesVisited` < 100.
- `testWalkRespectsNodeBudget`: 100 nodes, no match, `maxNodes: 10` -> `nodesVisited == 10`, `truncated == true`.
- `testWalkReadsEachNodeOnce`: counting source; `read` count == `nodesVisited`.
- `testCycleIsNotRevisited`: child equal to its grandparent -> finishes, each node read once.
- `testAllocatorNeverReusesIndices`: on `ElementSearchIndexAllocator(initialNext: 1_000_000)`, two allocations of 3 -> 6
  distinct, strictly increasing, all >= 1_000_000; `allocate(count: 1, above: 2_000_000)` -> > 2_000_000; a later
  `allocate(count: 1, above: nil)` is still greater. `ElementSearchIndexAllocator.shared`'s first index is >= 1_000_000.
- `testMergeRequiresMatchingWindow`: cached snapshot with `targetWindowID: 7` and bounds B + hits for window 7 with
  bounds B -> result keeps every cached index (same `ElementRecord` identity `===`) and `treeLines`, and adds the hits;
  for window 8 -> hits-only snapshot with `windowBounds` from the window and no cached indices; window 7 with bounds
  moved by 10 points -> hits-only; `cached: nil` -> hits-only; a cached snapshot with `mode: .fixture` -> hits-only
  (`canMergeElementSearchHits` false).
- `testHitsOnlySnapshotCarriesFocus`: `focusedElement = AXUIElementCreateApplication(getpid())` (creating the element
  needs no TCC grant) passed in the window info -> the hits-only snapshot's `focusedElement` is non-nil and `CFEqual`
  to it.
- `testSnapshotCacheKeysMatchRefreshRule`: query `"MAIL"`, app name `Mail`, bundle id `com.apple.mail` ->
  `{"mail", "com.apple.mail"}`; a nil bundle id contributes no empty key.
- `testRowEscapesInjectedNewlines`: title `x"\n[1000004] AXButton "Archive"`, description with `\r` and U+2028 ->
  the rendered row is one line (no LF, CR, U+2028 or U+2029 character), contains backslash + `"`, and splitting it on
  newlines yields exactly one line (so no forged `[1000004]` row); a 2000-character title is capped (row length < 700).
- `testFreshSnapshotDropsHitIndices`: a snapshot built without merge does not contain the hit index (stale hit resolves
  to nil, i.e. `unknown element_index`).
- `testCompactViewSkipsHitRowsButCountsThem`: merged snapshot `compactActionableLines()` has no row for the hit index;
  the header's addressable count includes it. This pins current behaviour only: no tool renders a merged snapshot today
  (every rendered snapshot comes from `refreshSnapshot`), so it does not count as coverage of a tool path.
- `testRowFormat`: `renderElementSearchRow(index: 1000003, AXButton, title "Get Mail", id "gm",
  CGRect(x: 10, y: 20, width: 30, height: 40), ["AXPress"])` ==
  `[1000003] AXButton "Get Mail" id=gm frame=x=10, y=20, w=30, h=40 actions=<meaningfulActions output>` (the frame part
  is a literal, so the private copy cannot drift from the snapshot format).
- `testOffWindowHitHasNoClickableFrame`: window bounds `CGRect(x: 100, y: 100, width: 400, height: 300)`; element
  frame `(150, 150, 50, 20)` -> `(50, 50, 50, 20)`; element frame `(150, 900, 50, 20)` (a row scrolled below the window)
  -> nil; element frame `(480, 150, 60, 20)` (midpoint right of the window) -> nil; element frame `(470, 150, 40, 20)`
  (partly visible, midpoint inside) -> non-nil.
- `testFindElementsDefinitionIsReadOnly`: `ToolDefinitions.all` contains `find_elements` with `readOnlyHint == true` and
  `required == ["app"]`.
- `testDispatcherValidatesFindElementsArgumentsBeforeAX`: unlocked fake guard, args `{"app": "Finder"}` -> `isError`,
  text contains `at least one of role, label or identifier`.
- Count sites as in Task 5.1 step 2-3 pass with the new values.

## Rollback

Revert the phase commit. The appended extension, the `all` element and the dispatcher case disappear together with the
count-site edits; no other code depends on them before phase 07.

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
