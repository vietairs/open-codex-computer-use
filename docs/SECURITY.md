# Security Default Constraints

## Current implementation boundaries

- The interface exposed to the MCP host is still local `stdio`; between the macOS CLI and the `.app` app agent, a Unix domain socket under the user's temp directory is used — the socket is tightened to current-user read/write after creation, and no TCP/HTTP port is listened on externally. When `OPEN_COMPUTER_USE_AGENT_SOCKET_NAMESPACE` is not set, the legacy socket continues to be used; once set, only a private filename derived from a namespace digest is used, and the host directory or raw namespace is never written into the socket path.
- Every action must explicitly carry an `app` parameter; there is currently no background auto-scan that controls arbitrary apps.
- The real macOS app path depends on `Open Computer Use.app` having been granted `Accessibility` and `Screen Recording` permissions; the terminal-side CLI / Node launcher forwards `mcp`, `doctor`, `call`, `snapshot`, and `list-apps` to the local app agent started by LaunchServices, so the permission requirement never falls on iTerm / Terminal itself.
- The experimental Linux runtime depends on the AT-SPI2 / D-Bus session of the logged-in desktop user; coordinate mouse, drag, and keyboard synthesis are only a best-effort fallback and should not be treated as a general-purpose background input authorization across Wayland compositors.

## Data handling

- For ordinary apps, a screenshot is by default only encoded to PNG in memory and returned directly via the MCP `image` content block; it is not persisted long-term by default.
- The Linux runtime's screenshot is best-effort; if GNOME Wayland returns a black image, the bridge omits the image block, so an invalid screenshot is not mistaken for a real frame.
- The fixture app's synthetic state is only written to a local temporary JSON file, meant to support deterministic smoke tests; the write currently goes through an atomic replace to reduce read/write contention during tests.
- This repository currently introduces no third-party services and does not upload screenshots, AX trees, or input content.

## Authorization and least privilege

- Only one layer of password-manager bundle denylist / bundle-id gate is currently kept:
  - It blocks direct `get_app_state` / action calls against 1Password, Bitwarden, Dashlane, LastPass, NordPass, and Proton Pass.
  - Terminal-type apps, Chrome / Atlas, and system components are no longer built-in blocked targets.
  - Passing a bundle identifier directly returns a safety denial; querying by app name does not, by default, expose these password managers as resolvable targets.
- However, there is currently still no session approval / dynamic app policy like the official closed-source implementation has.
- This means the open-source version's current security boundary is jointly provided by:
  - Explicit tool call parameters
  - The built-in password-manager denylist
  - `Open Computer Use.app`'s system permissions
  - The local usage scenario
- `click_method=global` is an explicit system-level pointer path that may move the real mouse cursor, change foreground focus, or hit other windows at the given coordinates. The call parameter itself is not treated as sufficient authorization; macOS and the Linux runtimes that support this mode also require `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1` to be set in the process environment. When it is not set, the request must be denied before any visible cursor movement or real input event.
- `click_method=app_post`, `sky_click`, and `accessibility` are not allowed to silently fall back to `global`. This guarantees that the non-invasive boundary the caller chose still holds when it fails.
- `click_method=sky_click` is an explicit macOS private-SPI capability and never enters `auto`. It does not move the system pointer, does not change the WindowServer frontmost app, and does not raise or switch the target window; internally it only lets the target app briefly enter a synthetic-active state, never sends a defocus record to the real foreground app, and only revokes the target's synthetic state once the renderer has settled. The post-click action-result snapshot is forbidden from doing an activate / `AXRaise` recovery. It still injects real input semantics into the specified PID/window, so it is only allowed to target an on-screen, same-PID window from the current snapshot, and fails closed when window identity does not match, the target-focus record fails, or private symbols are missing. The first version only supports left-click single/double clicks within the same Space.
- The SkyLight ABI, raw event fields, and Chromium receiving behavior are not protected by any Apple public compatibility promise. A failure after a system upgrade must not trigger a silent global fallback; symbols and controlled targets should be re-verified first before deciding whether to update the implementation.
- The next phase should prioritize adding:
  - session-level approval
  - a clearer protection policy for sensitive apps / system settings

## Lock Guard and the App-Screen Invariant

- `MacSessionGuard` checks the lock state from `CGSessionCopyCurrentDictionary` at every tool call entry point; when the dictionary is missing, empty, or fails to parse, it is always treated as locked (fail-closed), returning a "Lock state unknown" indicator.
- Default policy `.blockWhileLocked`: while locked, no `list_apps` / `get_app_state` / action tool is allowed to run — the security guarantee is unchanged from before.
- Explicit opt-in `OPEN_COMPUTER_USE_ALLOW_LOCKED=1` (`.allowWhileLocked`): allows best-effort control while the screen is locked. When not set, it stays fail-closed. Allowing this only changes whether the guard intercepts calls — it does not bypass Accessibility permission (still requires system authorization), does not persist screenshots to disk, and does not enable the global HID event tap (`globalPointerFallbacksEnabled()` still defaults to false). While locked, window screenshots are subject to system security restrictions and return an empty image.
- **App-agent trust boundary**: in `.app` mode there is a resident agent holding TCC authorization, listening on `$TMPDIR/open-computer-use-agent.sock` (chmod 0600, same uid only; peer authentication is covered in the next item, but it **cannot** distinguish a same-uid attacker). Because the lock-screen opt-in is a security-sensitive setting, it is fixed at agent startup **only through a trusted launch environment** (`NSWorkspace.OpenConfiguration.environment`, passed in by an operator-run proxy from its real shell env), **never through the per-call socket channel**; therefore a third-party process running under the same uid **cannot** forge this flag against an already-running agent. The policy is fixed for the agent's lifetime and can only be changed by quitting the agent from the menu bar and restarting it.
- **The filtering point for per-call environment is on the agent side**: the `environment` passed in by the client is untrusted input, so the **enforcement point is the agent**; the sender-side `proxiedEnvironment()` is only an incidental courtesy filter. Both sides share the same definition, `MacSessionLockPolicy.sanitizePeerEnvironment`, to avoid the two sets of rules drifting apart independently — the `mcp` and `cli` request kinds once drifted this way, resulting in only `cli` stripping the lock-screen key. There are two rules: only keys with the `OPEN_COMPUTER_USE_` prefix can pass through the socket (otherwise arbitrary keys would be inherited by child processes spawned by the agent), and the lock-screen opt-in can never pass through. **Any newly added request kind must also go through this function.**
- **App-agent socket peer authentication**: `AppAgentSocketListener.acceptLoop` calls `SocketPeerAuthenticator.authenticate(fd:)` before each connection is handled:
  - `getpeereid` verifies that the peer's euid matches the agent's euid (same uid), otherwise it is rejected.
  - It obtains the peer's audit token (including pid + pidversion, which precisely pins the connecting process instance and avoids PID-reuse / exec-after-connect TOCTOU) via `LOCAL_PEERTOKEN` → recovers the peer's `SecCode` via `SecCodeCopyGuestWithAttributes`, and verifies it against the requirement `anchor apple generic and identifier "<agent bundle id>" and certificate leaf[subject.OU] = "<agent TeamID>"`: the peer must be signed by the **same developer (Team Identifier)** as the agent, and the signing identifier must match the agent's own bundle identifier (i.e., this app's own executable; a same-team but different-identifier binary is rejected). When the agent itself is not running as a bundle, this degrades to a team-only pin. If any check fails, the connection is rejected.
  - **Development fallback**: when the agent itself is unsigned/ad-hoc (a local `swift build`), signature verification cannot be performed, so it degrades to same-uid only (`.allowUnsignedFallback`) and prints a one-time notice to stderr. The pure policy logic lives in `AppAgentPeerAuthPolicy` (unit-testable).
- **The real boundary of peer authentication (understand honestly, do not overstate)**: signature verification only proves "the connecting process is running this signed code" — it **cannot** distinguish a legitimate operator from a same-uid attacker. Same-uid code can directly `exec` that same legitimate, same-developer-signed CLI (located at a fixed, world-readable path inside the app bundle, see `plugins/.../launch-open-computer-use.sh`) to relay commands, and thereby **still** reuse the agent's TCC authorization — even while locked. So peer authentication only **raises the bar** (blocking external/unsigned/different-developer binaries from connecting directly) and does **not actually close** the same-uid confused-deputy issue. The residual risk recorded in PR#2 still holds.
- **Also note**: release builds now fail closed by default — when signing would fall back to ad-hoc/unsigned, `build-open-computer-use-app.sh` errors out and refuses to build; if you genuinely intend to distribute an ad-hoc release, you must explicitly set `OPEN_COMPUTER_USE_ALLOW_ADHOC_RELEASE=1` (in which case the script prints a prominent warning, and peer-auth does not take effect).
- **Conclusion**: for untrusted/multi-tenant hosts, use a **separate login session**; do not treat peer-auth or the lock-screen opt-in as an isolation boundary. Genuinely stronger isolation requires further tightening the requirement (Developer ID marker OID pinning) — see issue #4.
- `AppScreenSession` maintains a strict target-screen invariant: before an action call executes, it compares pid, target window ID, window bounds (8pt tolerance), and screenshot pixel dimensions; if any dimension has changed, it returns `appScreenStaleStateError`, requiring the caller to call `get_app_state` again first.
- The status menu (`ControlStatusMenuController`) diagnostics only expose toolName, app name / bundle id, pid, and connection count — never element labels, raw action args, screenshot data, or AX text.

## Fixture Bridge Constraints

- `FixtureBridge` is only used for in-repo test fixtures; it is not a control plane for third-party apps.
- Any new capability aimed at real apps must not reuse this test-only channel.

Repo-level dependency, SBOM, and provenance default capabilities are documented together in `docs/SUPPLY_CHAIN_SECURITY.md`.
