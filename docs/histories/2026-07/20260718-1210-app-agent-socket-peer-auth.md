## [2026-07-18 12:10] | Task: app-agent socket peer authentication

### 🤖 Execution Context
* **Agent ID**: `/hvn:cortex` follow-up
* **Base Model**: Claude Opus 4.8
* **Runtime**: Claude Code (background job)

### 📥 User Query
> After merging v0.2.0 + lock-screen allowance into the fork, open a socket peer-auth PR so the agent can safely keep working while the screen is locked.

### 🛠 Changes Overview
**Scope:** app-agent Unix domain socket peer authentication

**Key Actions:**
- **[Pure policy]**: Added `AppAgentPeerAuthPolicy` (Kit, unit-testable) — based on peer uid / self uid / agent TeamID / whether the peer satisfies the signing requirement, produces `allow` / `allowUnsignedFallback` / `reject`.
- **[IO verification]**: Added `SocketPeerAuthenticator` (app) — verifies same uid via `getpeereid`; obtains the audit token via `getsockopt(SOL_LOCAL, LOCAL_PEERTOKEN)` → recovers the peer's `SecCode` via `SecCodeCopyGuestWithAttributes` → verifies the same developer signature using the requirement `anchor apple generic and certificate leaf[subject.OU] = "<agent TeamID>"`; resolves the agent's own TeamID via `SecCodeCopySelf`.
- **[Wiring]**: `AppAgentSocketListener.acceptLoop` authenticates before handling a connection; on reject it closes the fd and logs the reason; unsigned dev builds fall back to `.allowUnsignedFallback` and print a one-time notice.
- **[Verification]**: +5 policy unit tests (uid mismatch, same-team signature allowed, signed agent rejects mismatched peer, unsigned fallback, unsigned still rejects a different uid); all 177 tests pass; full workspace build succeeds.

### 🧠 Design Intent (Why)
Lock-screen allowance (`OPEN_COMPUTER_USE_ALLOW_LOCKED`) lets the agent drive the app while the screen is locked, but the app-agent long-lived process holds the TCC grant, and the socket was only protected by 0600 same-uid permissions — any same-uid process could reuse its grant (confused deputy). Peer signature authentication requires the connecting side to carry the same developer signature as the agent, **raising the bar** — blocking direct connections from external, unsigned, or differently-signed binaries. But its boundary must be stated honestly (confirmed via cross-review with codex + Fable-max): signature verification cannot distinguish a legitimate operator from a same-uid attacker, since the latter could `exec` that legitimately signed CLI to relay commands, so it **does not truly close off** the same-uid confused-deputy issue; an untrusted host should still use a separate login session. Unsigned dev builds degrade to same-uid with a notice, and this state is already exposed in `copyDiagnostics`.

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AppAgentPeerAuthPolicy.swift`
- `apps/OpenComputerUse/Sources/OpenComputerUse/SocketPeerAuthenticator.swift`
- `apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `README.md`
- `docs/ARCHITECTURE.md`
- `docs/SECURITY.md`
- `docs/histories/2026-07/20260718-1210-app-agent-socket-peer-auth.md`

### 🔁 Follow-up
- Cross-review follow-up item #2 has landed: release builds are now fail-closed — when signing would fall back to ad-hoc/unsigned, `build-open-computer-use-app.sh` errors out and refuses to build, avoiding a released version silently degrading to same-uid-only trust.
- Override env: `OPEN_COMPUTER_USE_ALLOW_ADHOC_RELEASE=1` (when set, the script prints a prominent WARNING; peer-auth still doesn't take effect).
