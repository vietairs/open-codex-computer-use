# Phase 04: Batched AX attribute reads in the snapshot walk (lever L4, decision 13)

- **Depends on:** phase 01. Both edit `AccessibilitySnapshot.swift`.
- **Blocks:** none. Phase 08 measures it.
- **Parallel-safe with:** 02, 03, 05 and 06.
- **Roles:** Tester ≠ Implementer.
- **Effort:** 3h.
- **Commit (exactly one):** `perf(snapshot): read per-node AX attributes in one round trip`
- Paths: `W`, `S` and `T` are as defined in phase 01.

## Context (verified at afb60fa)

- Each node in `TreeRenderer.render` (`S/AccessibilitySnapshot.swift:881`) makes one IPC per unconditional read:
  - role and subrole (`:893-894`)
  - description (`:896`), help (`:898`)
  - value, through `sanitizedValue` → `stringValue(kAXValue)` (`:900`, `:1375`)
  - identifier (`:901`)
  - selected, expanded and enabled, plus two identical `isSettable(kAXValue)` calls, in `summarizeTraits` (`:1240-1264`, `:1267`)
  - position and size in `resolveLocalFrame` (`:1660-1664`)
- The single-attribute helpers are `attributeValue` `:1320`, `stringValue` `:1330`, `boolValue` `:1355` and `isSettable` `:1369`. The file has no `AXUIElementCopyMultipleAttributeValues` call.
- On Mail the walk costs about 1.3s (counsel). It runs in `get_app_state`, in every action's final refresh, and in `decide_next_action`.
- `resolveLocalFrame` force-casts with `as! AXValue` (`:1674-1675`). An error sentinel must never reach that cast (predict: "`as!` trap").
- The walk has **no automated coverage**: `TreeRenderer` is private, and the tests use fixture or hand-built snapshots. The byte-identical live render diff in M4 is therefore the acceptance guard for rendering.

## Signature

New file `S/AccessibilityAttributePrefetch.swift`:
```swift
import ApplicationServices

/// Attribute values for one element, fetched in a single AXUIElementCopyMultipleAttributeValues round trip.
struct AXAttributePrefetch {
    /// Exactly the attributes TreeRenderer.render reads unconditionally for every node.
    static let renderAttributes: [String] = [
        kAXRoleAttribute, kAXSubroleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXValueAttribute,
        kAXIdentifierAttribute, kAXSelectedAttribute, kAXExpandedAttribute, kAXEnabledAttribute,
        kAXPositionAttribute, kAXSizeAttribute,
    ]
    init(requested: [String], values: [String: CFTypeRef])
    /// nil when the multi-attribute call itself fails or returns a different count: callers then fall back to single reads.
    static func fetch(_ element: AXUIElement, attributes: [String] = renderAttributes) -> AXAttributePrefetch?
    /// Pure. Maps raw values to a dictionary, dropping AXValue error sentinels (AXValueGetType == .axError) and kCFNull.
    /// Returns [:] when attributes.count != rawValues.count.
    static func normalize(attributes: [String], rawValues: [CFTypeRef]) -> [String: CFTypeRef]
    func covers(_ attribute: String) -> Bool        // attribute was requested
    func value(_ attribute: String) -> CFTypeRef?    // nil = requested but absent (error/null), same as a failed single read
}
/// Pure routing: a covered attribute comes from the prefetch (live is NOT called); otherwise live() is called.
func prefetchedOrLive(_ prefetch: AXAttributePrefetch?, _ attribute: String, live: () -> CFTypeRef?) -> CFTypeRef?
```

`fetch` uses `AXUIElementCopyMultipleAttributeValues(element, attributes as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &values)`. The options value 0 means one failed attribute does not stop the call.

`S/AccessibilitySnapshot.swift` (private, added next to the existing helpers; existing helpers keep their signatures):
```swift
private func attributeValue(of element: AXUIElement, attribute: String, prefetch: AXAttributePrefetch?) -> CFTypeRef?
private func stringValue(of element: AXUIElement, attribute: String, prefetch: AXAttributePrefetch?) -> String?
private func boolValue(of element: AXUIElement, attribute: String, prefetch: AXAttributePrefetch?) -> Bool?
// OLD summarizeTraits(of:) -> NEW summarizeTraits(of element: AXUIElement, prefetch: AXAttributePrefetch?) -> [String]
//   (computes isSettable(kAXValue) once and passes it to valueTypeTrait)
// OLD valueTypeTrait(of:) -> NEW valueTypeTrait(of element: AXUIElement, isValueSettable: Bool, prefetch: AXAttributePrefetch?) -> String?
// OLD sanitizedValue(of:textLimit:) -> NEW adds `prefetch: AXAttributePrefetch? = nil`
// OLD resolveLocalFrame(of:windowBounds:) -> NEW adds `prefetch: AXAttributePrefetch? = nil`
```
Callers to update:
- `summarizeTraits`: `render` `:902` only. Confirm with `grep -n 'summarizeTraits(' $S/AccessibilitySnapshot.swift` before editing.
- `valueTypeTrait`: `summarizeTraits` only.
- `sanitizedValue` and `resolveLocalFrame`: `render` passes the prefetch. Every other caller keeps the defaulted `nil`, which means unchanged single reads.

In `render`, after the ancestor check (`:887`), add `let prefetch = AXAttributePrefetch.fetch(root)`. Route the unconditional reads at `:893-907` through the prefetch-aware helpers. All other reads (`roleDescription`, `preferredDisplayTitle`, `placeholderValue`, `children`, …) stay as they are.

## Data flow

The read at node N changes from about 15 single IPCs to one multi IPC for the 11 render attributes, plus the reads that remain in `copyActions`, `isSettable` (now once instead of twice), `children` and the helpers that read other attributes. Rendered text and element records are **byte-identical**.

## Boundaries

```
TARGET:    S/AccessibilityAttributePrefetch.swift (new)
           S/AccessibilitySnapshot.swift (render's read block + the private helper overloads above; nothing in the
                                          capture/WindowCapture region phase 01 changed)
           T/AXAttributePrefetchTests.swift (new; Tester only)
READ-ONLY: S/ComputerUseService.swift
FORBIDDEN: changing any rendered string, element index assignment, or tree budget; prefetching attributes read only
           conditionally; children/traversal changes; concurrency in the walk; files owned by phases 01-03, 05-07;
           Track B's lean walker (its own file, deduped on B's rebase per parallel-tracks rule 6)
```

## Tasks

### Task 4.1: Failing tests first (Tester)
- Create `T/AXAttributePrefetchTests.swift` (class `AXAttributePrefetchTests`) with the assertions listed below.
- Verify (RED): `swift test --filter OpenComputerUseKitTests.AXAttributePrefetchTests 2>&1 | tail -30` exits non-zero and contains `cannot find 'AXAttributePrefetch' in scope`.

### Task 4.2: Prefetch type (Implementer)
- Create the new file exactly as specified in the Signature block.
- Verify: the filtered test exits 0 and contains `with 0 failures`.

### Task 4.3: Wire into render (Implementer)
- Steps: add the private overloads, route `render`'s unconditional reads through the prefetch, memoise `isSettable` in `summarizeTraits`, and add the `prefetch:` parameter to `sanitizedValue` and `resolveLocalFrame`.
  - In `resolveLocalFrame`, when the prefetch covers position and size, take both from it. A nil from either means the function returns nil, and the value never reaches `as!`.
- Verify:
  - `swift test 2>&1 | tail -15` exits 0 and contains `with 0 failures`.
  - `grep -c 'AXUIElementCopyMultipleAttributeValues' $S/AccessibilityAttributePrefetch.swift` prints `1`.
- Commit with the exact subject above and report the SHA.

## Acceptance

Command: `cd $W && swift test --filter OpenComputerUseKitTests.AXAttributePrefetchTests`

Assertions (write first):
- `normalize(attributes: ["AXRole", "AXTitle"], rawValues: ["AXButton" as CFString, <error AXValue>])` returns exactly one key, `AXRole`, whose value is `"AXButton"`. Build the error value with `var e = AXError.noValue; AXValueCreate(.axError, &e)!`.
- `normalize` drops `kCFNull`.
- `normalize(attributes: ["a", "b"], rawValues: [x])` returns `[:]`.
- `AXAttributePrefetch(requested: ["AXRole", "AXTitle"], values: ["AXRole": "AXButton" as CFString])`:
  - `covers("AXTitle") == true` and `value("AXTitle") == nil`;
  - `covers("AXHelp") == false`.
- `prefetchedOrLive`:
  - A covered attribute returns the prefetched value, and the `live` closure is **not** invoked (use a counting closure).
  - An uncovered attribute invokes `live` exactly once.
  - A nil prefetch invokes `live`.
- `AXAttributePrefetch.renderAttributes` equals the 11-attribute list above, in order. This pins the lever's scope.

## Lever measurement M4 (main loop): speed and byte-identical rendering

1. Build C3 in `ocu-speed-bench-prev` (namespace `ocu-speed-bench-prev`) and C4 in `ocu-speed-bench` (namespace `ocu-speed-bench`). Follow phase 00 B-1…B-6 for both.
2. Render bracket. Run `render` on prev (label `C3-r1`), then on C4 (label `C4-r`), then on prev again (label `C3-r2`).
   - Pass: for each of Finder, Mail and TextEdit, the C4 hash equals `C3-r1` or `C3-r2`.
   - For an app flagged volatile in phase 00 step 0.4, use `--save-dir` on all three runs and `diff` the files after dropping lines that differ between r1 and r2. The diff must be empty. Delete the saved files afterwards: they hold Mail text.
3. `MEASURE(C4, <SHA>, extras: gas)` against C3.
   - Expected: `get_app_state` full and compact medians drop, and every action tool drops by the same walk saving.
   - Record the per-tool deltas.
- Any hash mismatch that is not explained by volatility is a Failure-Protocol event. Class it as "wrong domain rule": the AX batch semantics differ from single reads.

## Risks

| Risk | L×I | Mitigation |
|---|---|---|
| A multi-read returns values that differ from single reads for some app (for example web areas), changing the rendered text | M×H | Render bracket on 3 apps including Mail's WebKit view. Fall back to single reads when the multi call fails. |
| An error sentinel reaches `as! AXValue` | M×H without mitigation | `normalize` drops sentinels, and `resolveLocalFrame` returns nil on absent values. Unit-tested. |
| No speed gain because Mail's time is elsewhere | M×M | The per-lever table makes that visible. PR A's pass does not depend on this lever alone (see plan.md, risk "median misses"). |

## Rollback

`git revert <C4>`. It is independent: phases 05–07 do not use the prefetch.

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
