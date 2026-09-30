# Merge Correctness Review — upstream v0.3.5 → fork (PR vietairs/open-codex-computer-use#8)

- Worktree: `/Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/sync-upstream-v0.3.5`
- Branch: `worktree-sync-upstream-v0.3.5`, merge commit `8ce8cb0` (parents: fork `70808ae`, upstream `386a260`), release commit `552a8e4`
- Method: `git diff 8ce8cb0^1 8ce8cb0` (upstream absorbed) and `git diff 8ce8cb0^2 8ce8cb0` (fork contribution) per file, plus `git diff v0.2.1 70808ae` for fork-only provenance; `swift build`, `swift test`, `./scripts/ci.sh`
- Verification: `swift build` OK; `swift test` → **220 passed, 2 skipped, 0 failures**; no conflict markers anywhere in `packages/ apps/ scripts/ plugins/`

## Verdict

The mechanical merge is sound: no fork-touched file lost its fork delta (set difference of `git diff --name-only v0.2.1 70808ae` vs `git diff --name-only 8ce8cb0^2 8ce8cb0` is empty), no upstream test was dropped, and both hand-resolved conflicts are semantically defensible. One **blocking** defect was introduced by absorbing an upstream change into a fork security seam, plus one **high** behavioral regression that the fork's own resolution masks.

---

## Critical

### C1. Peer-supplied environment on the newly merged `"mcp"` branch bypasses the fork's lock-policy strip

`apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift:406-411` (merged from upstream) vs `:416-424` (fork).

```swift
case "mcp":
    let line = request["line"] as? String ?? ""
    let environment = request["environment"] as? [String: String] ?? [:]
    let response = AppAgentEnvironment.withOverrides(environment) {   // :409  no strip
        server.handle(line: line)
    }
...
case "cli":
    var environment = request["environment"] as? [String: String] ?? [:]
    // Defense in depth: never honor a per-call client's attempt to set the lock-screen policy.
    environment.removeValue(forKey: MacSessionLockPolicy.environmentKey)   // :421  fork guard
```

Evidence of provenance: upstream `386a260` added the per-call `"environment"` payload to the **mcp** path (`git show 386a260:...MacOSAppAgentProxy.swift` line 123); fork `70808ae` only had it on the **cli** path (line 138) and guarded that one. The merge correctly kept the fork's sender-side filter (`proxiedEnvironment()`, `:153-159`, excludes `MacSessionLockPolicy.environmentKey`) but did **not** extend the receiver-side strip to the new branch.

Why the sender-side filter is not a defense: the socket peer writes the JSON request itself. `SocketPeerAuthenticator` (`:346`) admits code-signed peers *and* an unsigned same-uid dev fallback (`.allowUnsignedFallback`, `:351-354`), so a crafted `{"kind":"mcp","environment":{...}}` reaches `withOverrides` unfiltered.

Impact, concrete:
- `AppAgentEnvironment.withOverrides` calls **process-global `setenv`** (`:505-507`). Any env read at call time is now attacker-controlled: `globalPointerFallbacksEnabled(environment: ProcessInfo.processInfo.environment)` (`ComputerUseService.swift:1850, 1885, 1925`) — a peer can enable the physical-pointer path (moves the real pointer, steals foreground) for a server started without it, and enable `click_method=global`.
- **Race → lock-guard bypass.** Connections run on detached threads (`MacOSAppAgentProxy.swift:348-357`), each constructing its own `StdioMCPServer` (`:366`) → `ComputerUseToolDispatcher` → `MacSessionGuard(policy: .fromEnvironment())` (`MacSessionGuard.swift:181-186`). The policy snapshot is taken on the connecting thread at arbitrary time. A connection holding `withOverrides([...ALLOW_LOCKED: "1"])` mutates the global env for the duration of a tool call, so a *concurrently accepted* connection can snapshot `allowWhileLocked` and keep it for its whole lifetime. The fork's stated invariant ("fixed at agent launch so a per-call client cannot forge it", `:155-157`) no longer holds.
- DEBUG builds additionally: `OPEN_COMPUTER_USE_LOCK_FAIL_OPEN=1` makes lock detection return unlocked outright (`MacSessionGuard.swift:139-143`).
- Independently: concurrent `setenv` from connection threads while other threads read `ProcessInfo.processInfo.environment` is not thread-safe; `withOverrides`' `NSLock` serializes writers only.

Fix: hoist the strip above the `switch` (or, better, apply an allowlist of forwardable keys on the receiving side) so both `"mcp"` and `"cli"` are covered; and scope overrides per-connection rather than via process env, or serialize connection handling.

---

## High

### H1. `firstAnyWindow` does not steal focus, but it makes upstream's `recoverVisibleWindow` unreachable in the default policy

`packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift:171-179`.

Activation question, answered: `firstAnyWindow` (`:315-318`) is `copyElement(kAXFocusedWindowAttribute)` / `copyArray(kAXWindowsAttribute).first(role == AXWindow)` — pure AX reads, no `activate`, `unhide`, `AXRaise`, or `AXMain/AXFocused` writes (contrast `recoverVisibleWindow`, `:265-289`, which does all four plus `/usr/bin/open -b`). **So the resolution does not violate upstream's deny-activation contract**, and leaving it ungated on `recoveryPolicy` is safe with respect to focus steal.

The real problem is masking, and it affects the `.allowActivation` path, not just `.readOnly`:

1. Gate 1 (`:175-179`): `firstAnyWindow` now satisfies `focusedWindow` for any app exposing any AX window, so the `recoveryPolicy == .allowActivation` recovery below never runs.
2. Gate 2 (`:190-199`): the fork also changed `WindowCapture.resolve` to enumerate **all** windows (`CGWindowListCopyWindowInfo([], …)`, `:437`) and to return a capture with `image = nil` for off-screen ones (`:474`). So `windowCapture` is no longer `nil` for hidden/minimized apps → the second recovery gate never runs either.

Net: upstream's unhide/unminimize/raise recovery is effectively dead code — reachable only when the app exposes zero AX windows *and* `kAXFocusedWindow` is nil. A minimized or hidden app that upstream would raise before acting is now silently acted on in place, screenshot-less. This is the fork's Stage-Manager intent, but it is applied unconditionally to every app and every caller, which is a behavior change upstream did not intend and no test covers.

`.readOnly` (sky_click refresh, `ComputerUseService.swift:19-20, 651`): `firstAnyWindow` does return a window where upstream would `throw .stateUnavailable(computerUseNoWindowFoundMessage)` (`:182-184`). Because the resolution is read-only this is a *reporting* difference, not a focus-steal, and the click side fails closed (see M2). Acceptable, but it should be an explicit, tested decision.

### H2. Screenshot-less snapshot silently degrades coordinate clicks to 1:1 scale

`AccessibilitySnapshot.swift:472-474` (`image = best.isOnscreen ? … : nil`) feeds `ComputerUseService.screenshotPixelScale` (`:222-241`), which returns `CGSize(1,1)` whenever `screenshotPixelSize` is nil. On a 2x display a `click(x:y:)` against an off-screen window is therefore interpreted at half the intended offset and delivered via `clickBackgrounded` into a window the user cannot see. Nothing rejects a coordinate action that has no screenshot — the fork already wrote that guard (`AppScreenSession.requireCoordinateInsideScreenshot`, `AppScreenSession.swift:24-32`) but it is never called (see M3).

---

## Medium

### M1. Conflict resolutions themselves — verified correct

- **InputSimulation.swift**: the only textual overlap was the `clickTargeted` error string, resolved to upstream's `"Failed to create app-post event source."` (`:72-74`). Fork's `clickBackgrounded` survives verbatim (`:83-133`), including the `dlsym` failure fallback to `clickTargeted` (`:96-99`); upstream's drag rework (nil source, per-step deltas, gesture event number, `dragStepCount`) and `clickWithSkyLight` were both taken. The fork's local-point math (`screenPoint - windowBounds.origin`) stays consistent with the caller because `inputEventPoint(fromScreenStatePoint:)` is the identity (`ComputerUseService.swift:121-126`). **No semantic conflict.**
- **AccessibilitySnapshot.swift**: all three fork hunks preserved (`git diff v0.2.1 70808ae` for this file yields exactly the `firstAnyWindow` fallback, the all-windows `CGWindowListCopyWindowInfo`, and `isOnscreen`), all upstream changes taken. Correct as a merge; see H1/H2 for the design consequence.
- **ComputerUseService.swift / ComputerUseToolDispatcher.swift / OpenComputerUseKitTests.swift** (auto-merged, both sides changed): no semantic conflict found. `click_method` is threaded end to end (`ComputerUseToolDispatcher.swift:64-72` → `ComputerUseService.click`), the fork's `MacSessionGuard` call remains the single choke point at the top of `callTool` (`ComputerUseToolDispatcher.swift:50-52`) with the ordering comment intact, and `runOpenComputerUseCall` still injects the guard (`:273-279`). The fork's `typeText` override survived intact (`ComputerUseService.swift:763-773`) and upstream did not touch that region.

### M2. `sky_click` guard text is now false for snapshots the fork can produce

`ComputerUseService.swift:1897-1902` rejects with "requires a current on-screen target window" only when `windowBounds`/`targetWindowID` are nil — which the fork now populates for off-screen windows. The real on-screen check happens deeper, in `SkyClickDispatcher.validate` → `skyClickWindowMatchesTarget` (`SkyClickSimulation.swift:80-98, 225-237`), which requires `kCGWindowIsOnscreen`. So it **fails closed** (good), but with the misleading "target window is stale, off-screen, or no longer owned" message for a window that was resolved that way by design. `AppSnapshot` carries no `isOnscreen`, so no consumer can distinguish or pre-empt this.

### M3. Fork-only modules: reachability audit

| Module | Reached from live code? | Evidence |
|---|---|---|
| `MacSessionGuard.swift` | **Yes** | `ComputerUseToolDispatcher.swift:40-52` (default init + `requireUnlocked` on every `callTool`), `:277-279`; `StdioMCPServer.init` → dispatcher (`MCPServer.swift:22-25`) |
| `AppAgentPeerAuthPolicy.swift` | **Yes** | `SocketPeerAuthenticator.swift:38,47` ← `acceptLoop` `MacOSAppAgentProxy.swift:346` |
| `ControlActivityStore.swift` | **Partially** | wired: `registerConnection`/`unregisterConnection` (`MCPAppRuntime.swift:32,71`; `MacOSAppAgentProxy.swift:191,234`), `markTurnEnded` (`MCPServer.swift:74`). **Never called in production:** `record(_:forConnection:)` (`:91`), `recordError` (`:101`), `recordLocked` (`:107`) — so the status menu can show connections but never tool activity or lock refusals |
| `AppScreenSession.swift` | **No — orphaned** | zero non-test references; `AppScreenSessionValidator`, `buildIdentity`, `validate`, `requireCoordinateInsideScreenshot`, `requireKeyboardOwnership`, `appScreenStaleStateError` are exercised only by `OpenComputerUseKitTests.swift:2808-2932` |

Both gaps are **pre-existing, not merge-induced**: `git grep` at `70808ae` shows the identical situation. Flagging because H2's mitigation is exactly the orphaned validator, and because tests passing here is phantom coverage — they prove the type works, not that anything calls it.

### M4. Guard bypass on direct-service CLI paths (pre-existing)

`list-apps` and `snapshot` construct `ComputerUseService()` directly and skip `MacSessionGuard`: `apps/.../OpenComputerUseMain.swift:57-61` and `MacOSAppAgentProxy.swift:462-468`. Read-only operations, and `snapshot` can return a window screenshot; unchanged by this merge, but it means the lock guard covers the MCP/`call` surface only.

### M5. `type_text` fallback force-activates the target app

`ComputerUseService.swift:763-773` (fork, correctly preserved). When no focused editable element exists, it activates the target app, types, then re-activates the previous frontmost. This is the only tool that deliberately steals foreground, it replaces upstream's explicit `stateUnavailable` error with blind keystrokes into whatever the app focuses, and it runs even under `OPEN_COMPUTER_USE_ALLOW_LOCKED`. Merge-correct; raising as an owner decision.

---

## Low

### L1. One fork test dropped — correctly

`testAccessibilityRendererMarksAnonymousGenericClickTargetsAsButtons` is the only test name present at `70808ae` and absent at `HEAD`. It tested `shouldRenderAnonymousActionTarget`, which upstream itself deleted in `6790494` ("fix(snapshot): 保留文本摘要中的可点击节点边界"). Taking upstream's refactor and dropping the test is right. No upstream test was lost (`comm` over the three test-name sets: fork→merge loses 1, upstream→merge loses 0; 192/163 → 220).

### L2. The merge's risk surfaces are exactly the untested ones

No test constructs a `WindowCaptureCandidate` with `isOnscreen: false` — all four fixtures pass `true` (`OpenComputerUseKitTests.swift:1915, 1924, 1940, 1949`), so the screenshot-skip path (H2) and the off-screen candidate preference are unexercised. No test covers `SnapshotBuilder.build` with `.readOnly` + a window resolvable only through `firstAnyWindow` (H1). `clickActionSnapshotRecoveryPolicy` has a mapping test (`:1549-1555`) but nothing asserts what the policy actually prevents.

### L3. `./scripts/ci.sh` exits 1 before the Swift tests

`check-repo-hygiene.sh` reports missing `.editorconfig`, `.github/PULL_REQUEST_TEMPLATE.md`, `.github/workflows/*.yml`, `.markdownlint.json`, etc. Confirmed **pre-existing and identical at `v0.2.1`, `70808ae`, and upstream `386a260`** (`git ls-tree` finds none of them at any ref), so it is not merge-caused — but `ci.sh` cannot be cited as a green gate for this PR. `swift build` + `swift test` are the usable evidence.

### L4. Dead-ish error branch in the non-AX click fallback

`ComputerUseService.swift:1880-1887`: the `catch` re-checks `globalPointerFallbacksEnabled` and, when enabled, falls through and returns without performing any click — unreachable in practice because the enabled case already returned at `:1851-1859`, but it now silently swallows a `clickBackgrounded` failure if the env flips mid-call (which C1 makes possible). Upstream code, fork-adjacent; worth an explicit `throw`.

---

## Explicit negatives (categories where I found nothing)

- **Lost fork changes**: none. Every file the fork changed relative to `v0.2.1` still differs from upstream in the merge result.
- **Conflict markers / build breakage**: none; package builds and 220 tests pass.
- **`ComputerUseToolDispatcher.swift`**: no semantic conflict; the fork guard is intact and every tool still routes through the single guarded entry, including the new `click_method` argument.
- **Focus-steal from `firstAnyWindow` itself**: none — verified read-only AX attribute access.
- **Version bump**: consistent across all release-guide version sources (`OpenComputerUseVersion.swift`, `plugin.json`, both Go runtimes, Go CLI, smoke suite) at `0.3.6-vietairs.1`; root `package.json` is an unversioned tooling manifest.

---

## Recommended actions (ranked)

1. **Blocker** — move the `MacSessionLockPolicy.environmentKey` strip above the `switch` in `AppAgentConnection.handle(requestLine:)` so it covers `"mcp"`; prefer a receiver-side allowlist of forwardable `OPEN_COMPUTER_USE_*` keys. Separately, stop mutating process-global env per call, or serialize connection handling, to close the cross-connection race and the `setenv`/`getenv` data race. (C1)
2. **Blocker-adjacent** — decide explicitly what the `firstAnyWindow` fallback should do to upstream's recovery: either gate the *second* recovery attempt on `windowCapture.image == nil` rather than `windowCapture == nil`, or keep recovery for `.allowActivation` and let `firstAnyWindow` apply only under `.readOnly`. Add the two missing tests. (H1)
3. Propagate `isOnscreen` onto `AppSnapshot` and either wire `AppScreenSessionValidator.requireCoordinateInsideScreenshot` or reject coordinate actions when `screenshotPNGData == nil`, instead of silently falling back to 1:1 scale. (H2, M2, M3)
4. Either wire `ControlActivityStore.record/recordError/recordLocked` at the MCP layer (the ordering comment in the dispatcher already reserves the spot) or delete them and their tests. (M3)
5. Owner decisions, not merge defects: `type_text` force-activation (M5), guard-free `list-apps`/`snapshot` CLI paths (M4), repo-hygiene CI failure (L3).

## Unresolved questions

1. Is the app-agent socket intended to be reachable by any same-uid process (the `.allowUnsignedFallback` branch), or is that a dev-only affordance that should be compiled out of release builds? C1's severity depends on this.
2. Is the Stage-Manager background path meant to apply to *all* apps by default, or only when the caller opts in? H1's regression is only acceptable under the first reading.
3. Was `AppScreenSession` deliberately parked pending wiring, or forgotten? It is the natural home for the H2 fix.
