# Security review — merge of upstream v0.3.5 into fork (PR vietairs/open-codex-computer-use#8)

Worktree: `/Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/sync-upstream-v0.3.5`
Branch: `worktree-sync-upstream-v0.3.5` · Merge commit `8ce8cb0` (parents: fork `70808ae`, upstream `386a260`)
Diff reviewed: `git diff v0.2.1...HEAD` (128 files) and, for provenance, `git diff 70808ae 8ce8cb0` (what the merge actually pulled in).
Method: source read only. No build/test was run — see Unverified.

## Verdict by requested area

| # | Area | Result |
|---|------|--------|
| 1 | Lock-screen work guard (MacSessionGuard) | **Fix intact, but a new bypass path was introduced by the merge** — see H-1 |
| 2 | App-agent socket peer authentication + upstream namespacing | **Clean** (namespacing did not create an unauthenticated path) — see notes N-1/N-2 |
| 3 | Global pointer gate (`OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS`), `sky_click`, `clickBackgrounded` | **Clean** — see verification below |
| 4 | Release signing / secret handling (`scripts/build-open-computer-use-app.sh`, `.github/workflows/release.yml`) | **Clean** (fork hardening survived verbatim) — see note N-3 |

---

## HIGH

### H-1. App-agent `mcp` request applies a peer-supplied environment without stripping the lock-screen opt-in
`apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift:405-412` (added by the merge)

```swift
case "mcp":
    let line = request["line"] as? String ?? ""
    let environment = request["environment"] as? [String: String] ?? [:]
    let response = AppAgentEnvironment.withOverrides(environment) {   // <- no strip
        server.handle(line: line)
    }
```

Compare the sibling `cli` branch, which the fork deliberately hardened (`:419-421`):

```swift
// Defense in depth: never honor a per-call client's attempt to set the lock-screen
// policy. It is fixed at agent launch; a forged value here is silently dropped.
environment.removeValue(forKey: MacSessionLockPolicy.environmentKey)
```

Upstream v0.3.5 added the `environment` field to the **mcp** request (`:130`, `:409`). The merge kept it and did **not** carry the fork's `removeValue` across, so the two branches now disagree. The fork's documented invariant is stated at `MacOSAppAgentProxy.swift:380-386`: the lock opt-in "must travel only through this trusted launch environment … never the per-call socket channel, so a same-uid client cannot forge it against an already-running, TCC-authorized agent." The mcp branch now violates exactly that.

Failure mode (concrete): a peer that reaches the socket sends
`{"kind":"mcp","line":"<any long-running tool call>","environment":{"OPEN_COMPUTER_USE_ALLOW_LOCKED":"1"}}`.
`AppAgentEnvironment.withOverrides` (`:489-519`) `setenv`s that into the **agent process** for the duration of the call. The lock policy is captured by `MacSessionGuard(policy: .fromEnvironment())` at `ComputerUseToolDispatcher` construction (`ComputerUseToolDispatcher.swift:43`), and `StdioMCPServer` — hence the dispatcher and its guard — is a per-connection `let` built after `accept` (`MacOSAppAgentProxy.swift:364-366`, `:456-464`). So any **second connection whose `AppAgentConnection.init` lands inside that setenv window permanently captures `.allowWhileLocked` for its whole lifetime**, on an agent the operator launched with the opt-in absent. The result is exactly what the fork's guard exists to prevent: driving apps through a TCC-authorized agent while macOS is locked, with no operator opt-in.

Note the client side is not the control here — `proxiedEnvironment()` (`:153-159`) already filters the key out; the agent-side strip is the only defense against a hand-crafted socket write, and it is what is missing. Reachability of the socket is bounded by peer auth (area 2), but on every **unsigned/ad-hoc build** — including any CI artifact built under `OPEN_COMPUTER_USE_ALLOW_ADHOC_RELEASE=1`, and every local `swift build` — peer auth degrades to same-uid only (`SocketPeerAuthenticator.swift:19-24`, `AppAgentPeerAuthPolicy.swift:43-47`), so any same-uid process can do this.

Fix: mirror the `cli` strip in the `mcp` branch, and preferably hoist it into a single `sanitizedOverrides(_:)` used by both so the two branches cannot drift again.

---

## MEDIUM

### M-1. Agent applies *arbitrary* peer-supplied env keys — no allowlist on the receiving side
`MacOSAppAgentProxy.swift:408-412`, `:418-426`, `:489-519`

The `OPEN_COMPUTER_USE_` prefix filter exists only on the **client** (`proxiedEnvironment()`, `:153-159`). The agent applies whatever keys the JSON request contains, via `setenv`, inside a TCC-authorized, long-lived GUI process. A crafted request can therefore set `HOME`, `TMPDIR`, `PATH`, `CFNETWORK_*`, etc. in the agent, and those are inherited by subprocesses the agent spawns — `AccessibilitySnapshot.swift:291-295` runs `Process()` → `/usr/bin/open -b <bundleid>` during window recovery. `/usr/bin/open` is a platform binary (SIP/hardened runtime strips `DYLD_*`), so this is not direct code execution, but redirecting `HOME`/`TMPDIR` of a TCC-authorized process is a real integrity/exfiltration surface.

This is **pre-existing** for the `cli` kind (present at `70808ae`); the merge extended the same weakness to the `mcp` kind. Fix alongside H-1: filter to the `OPEN_COMPUTER_USE_` prefix minus the lock key, agent-side.

### M-2. `AppAgentEnvironment.withOverrides` mutates process-global state under a lock that does not cover concurrent readers
`MacOSAppAgentProxy.swift:489-519`

`setenv`/`unsetenv` are process-global; the `NSLock` only serializes *writers*. Concurrent readers — the status-menu/main-thread code, `MacSessionGuard(policy: .fromEnvironment())` on a connection being constructed, `globalPointerFallbacksEnabled(environment: ProcessInfo.processInfo.environment)` (`ComputerUseService.swift:1802, 1851, 1882, 1926`) on another connection's in-flight call — read env without that lock. This is the mechanism that makes H-1 exploitable, and independently it means one client's per-call `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1` can leak into a concurrent client's click/drag/scroll decision (global HID posting, real pointer movement) for the overlap window. `getenv`/`setenv` racing across threads is also formally unsafe (potential use-after-free in libc), independent of the security question.

Also: work escaping the body via `Task { @MainActor … }` (`:445-449`, `:462-466`) runs after the env is restored, so overrides silently do not apply there — a correctness inconsistency, not a security one.

---

## LOW / INFORMATIONAL

### N-1. Socket namespacing (area 2) — verified clean
- `AppAgentSocketNamespace.swift:6-14` only changes the *file name* (SHA-256 prefix of the namespace string); the namespace never reaches `bind()` as raw attacker-controlled text and cannot escape the temp dir via `../` because only the hash is interpolated. Empty/whitespace namespace falls back to the historical name.
- There is exactly one listener (`AppAgentSocketListener.init`, `MacOSAppAgentProxy.swift`), used for every socket path; `chmod 0600` is applied in `init` before `start()`, and **every** accepted fd goes through `SocketPeerAuthenticator.authenticate` in `acceptLoop()` before an `AppAgentConnection` is created. No namespaced path bypasses this, and no socket becomes serviceable before the peer policy is in force.
- Residual (pre-existing, not a merge regression): between `bind()` and `chmod()` the socket carries umask-derived permissions; cross-uid connects in that window are still rejected by the `peerUID == selfUID` check in `AppAgentPeerAuthPolicy.decide` (`:39-41`).
- Residual (weakly worsened by namespacing): a same-uid actor can pick an unused namespace so `connectOrLaunchAgent` finds no agent and launches a **fresh** agent instance carrying that actor's `OPEN_COMPUTER_USE_ALLOW_LOCKED` (`MacOSAppAgentProxy.swift:380-388`), instead of being routed to the operator's non-opted-in agent. Pre-merge the same actor could already invoke the app bundle directly with `__open-computer-use-app-agent <path>` and any env, so this is a convenience delta, not a new capability. Worth one line in `docs/SECURITY.md`.

### N-2. Lock guard (area 1) — the absent-key fix is intact and reached
`MacSessionGuard.swift:135-158`: ordering is unchanged — explicit `CGSSessionScreenIsLocked` is consulted first; the absent-key branch infers *unlocked* only when `kCGSSessionOnConsoleKey` coerces to `true`, otherwise returns `isLocked: true, isUnknown: true`; nil/empty/unparseable stays fail-closed. Cache holds locked/unknown only (`shouldCache`, `:172-174`). `requireUnlocked` is invoked as the first statement of `ComputerUseToolDispatcher.callTool` (`ComputerUseToolDispatcher.swift:50`), which is the single entry point for both `StdioMCPServer` (`MCPServer.swift:89`) and `runOpenComputerUseCall` (`ComputerUseToolDispatcher.swift:279`). The merge did not touch this file.

Pre-existing gap (present identically at `70808ae`, **not** a merge regression, but it is a hole in the guard): the CLI `listApps` and `snapshot` commands construct `ComputerUseService()` and call it directly, bypassing `MacSessionGuard` entirely — `MacOSAppAgentProxy.swift:452-461` and `apps/OpenComputerUse/Sources/OpenComputerUse/OpenComputerUseMain.swift:57-62`. Effect: full accessibility-tree text of any app (window titles, field contents) is readable while the Mac is locked with the default fail-closed policy in force. Recommend routing these through the dispatcher.

Also `#if DEBUG` `OPEN_COMPUTER_USE_LOCK_FAIL_OPEN=1` (`MacSessionGuard.swift:139-143`) unconditionally reports unlocked. Correctly excluded from release builds; flagging only because M-1 lets a peer set arbitrary env, which would make it live in any debug-configuration build.

### N-3. Release signing (area 4) — fork hardening survived the merge verbatim
`scripts/build-open-computer-use-app.sh:207-245` (`enforce_release_signing_policy`, invoked at `:277` before any build) still fails closed on an ad-hoc/unsigned **release** build unless `OPEN_COMPUTER_USE_ALLOW_ADHOC_RELEASE=1`. `.github/workflows/release.yml:78-83` still requires both `OPEN_COMPUTER_USE_CODESIGN_P12_BASE64` and `..._P12_PASSWORD`, and when absent sets the override explicitly with a loud log line. No secret is echoed, no `set -x` near secret handling, no new `pull_request_target`, actions are pinned by SHA, and the new `--notes-file docs/releases/github/${RELEASE_TAG}.md` step introduces no injection (path from `github.ref_name`, passed via env var, not inlined into the script body). No signing-identity or credential regression found.

Standing (accepted, fork's own design) risk: when the CI cert is not configured the release still ships, ad-hoc-signed, with socket peer authentication inactive — which is precisely the configuration in which H-1 is exploitable by any same-uid process.

### N-4. Global pointer gate (area 3) — verified clean
Every global/HID delivery primitive is gated:
- `InputSimulation.swift:172` (`scrollGlobally`) reached only from `ComputerUseService.swift:1802` behind `globalPointerFallbacksEnabled`.
- `InputSimulation.swift:311` (`postMouseEvent` → `.cghidEventTap`, used by `dragGlobally` and `clickGlobally`) reached only from `ComputerUseService.swift:1834` (`dragDeliveryPath == .global`, `:200-202`), `:1851` (non-AX click fallback), and `:1926` (`click_method=global`, re-checked after the service-boundary check at `:479`/`:47-51`).
- `sky_click` (`InputSimulation.clickWithSkyLight` → `SkyClickDispatcher`) posts **only** process-targeted: `SLEventPostToPid` + `CGEvent.postToPid` (`SkyClickSimulation.swift:185-186`); no `cghidEventTap`, no `CGWarpMouseCursorPosition`, no real front-process change — `beginSyntheticTargetFocus` (`SkyLightSPI.swift:155-183`) posts a synthetic activation record to the target's PSN and is unwound in both the success and the `catch` path. Not requiring the pointer gate is consistent with the gate's stated boundary (global pointer/HID, not process-targeted delivery).
- `clickBackgrounded` (`InputSimulation.swift:87-134`) likewise stays on `postToPid` and is only used on the non-global branch (`ComputerUseService.swift:1864`).
- Dead code, cosmetic: the `guard globalPointerFallbacksEnabled … else { throw }` in the `catch` of `performNonAXClickFallback` (`ComputerUseService.swift:1882-1887`) can only be reached when the gate is off (the enabled case returns early at `:1850-1858`), so the empty fall-through after it is unreachable. Pre-existing; harmless but misleading.

### N-5. Test gap
No test covers the agent-side per-call environment sanitisation — neither the existing `cli` strip nor the missing `mcp` one. `MacSessionLockPolicy.fromEnvironment` is well covered (`OpenComputerUseKitTests.swift:2523-2533`), but that is the parser, not the trust boundary. A test asserting that a forged `{"environment":{"OPEN_COMPUTER_USE_ALLOW_LOCKED":"1"}}` does not reach `setenv` would have caught H-1 at merge time; it requires extracting the sanitisation into a testable pure function (which is also the H-1 fix).

---

## Recommended actions (priority order)

1. **Blocking (H-1):** strip `MacSessionLockPolicy.environmentKey` in the `mcp` branch of `AppAgentConnection.handle(requestLine:)`; factor the sanitiser so `cli` and `mcp` share it.
2. **Same change (M-1):** agent-side allowlist — accept only `OPEN_COMPUTER_USE_`-prefixed keys, minus the lock key.
3. **(M-2):** stop relying on process-global `setenv` for per-call configuration, or at minimum capture the effective environment once per connection at construction and thread it through, so concurrent connections cannot observe each other's overrides.
4. **(N-5):** add a unit test for the sanitiser.
5. **(N-2, follow-up, not merge-blocking):** route CLI `listApps` / `snapshot` through `ComputerUseToolDispatcher` so the lock guard covers AX reads.
6. **(N-1, docs):** note in `docs/SECURITY.md` that a client-chosen socket namespace launches a separate agent under the client's environment.

## Unverified

- No `swift build` / `swift test` was run (read-only review); the merge's compile and test status is unconfirmed here.
- Exploitability of H-1 was established by reading the construction lifetimes (`AppAgentConnection` per-accept, `StdioMCPServer` per-connection `let`, guard policy fixed at dispatcher init); it was not demonstrated against a running agent.
- macOS lock-state semantics in `MacSessionGuard` remain empirically verified only on macOS 26 / Darwin 27, per the file's own header — unchanged by this merge.

## Unresolved questions

1. Is per-call environment proxying of `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS` intended? The tool descriptions and `dragDeliveryNote` tell operators to set it "in the server process environment", but the proxy lets any client set it per call. If per-call is intended, the docs should say so; if not, it belongs in the launch-fixed environment next to the lock key.
2. Does the fork intend to keep shipping CI artifacts under `OPEN_COMPUTER_USE_ALLOW_ADHOC_RELEASE=1` when no cert is configured? That is the configuration in which peer auth is inactive and H-1 is trivially reachable.
