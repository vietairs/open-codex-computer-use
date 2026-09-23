## [2026-07-18 10:44] | Task: Merge upstream v0.2.0 and add optional lock-screen pass-through

### 🤖 Execution Context
* **Agent ID**: `/hvn:cortex --auto`
* **Base Model**: Claude Opus 4.8
* **Runtime**: Claude Code (background job)

### 📥 User Query
> Pull the latest code from the fork's upstream, `iFurySt/open-codex-computer-use`, diff the fork against the newest version, and merge the features we've built into that latest update; then check whether the agents (Claude Code / Codex) can keep operating the computer while the screen is locked after the merge, and if not, build that capability.

### 🛠 Changes Overview
**Scope:** three-way merge (local Stage Manager + origin lock-screen guard + upstream v0.2.0) + `OpenComputerUseKit` lock-screen policy + app-agent IPC hardening

**Key Actions:**
- **[Three-way merge]**: merged all 17 upstream commits from v0.1.51→v0.2.0 (the breaking `text_limit` change, the tree budget parameter, numeric `element_index`, Windows UTF-8, preserving anonymous web click targets) into the branch carrying both sets of fork features. The one semantic conflict: upstream added `WindowCaptureCandidate.isOnscreen`, which required fixing 4 test constructors.
- **[Lock-screen capability check]**: after the merge, the lock-screen guard was fail-closed and **blocked** every tool — the opposite of the goal.
- **[Optional pass-through]**: added `MacSessionLockPolicy`; setting `OPEN_COMPUTER_USE_ALLOW_LOCKED=1` enables best-effort control while the screen is locked, with fail-closed still the default. This is feasible because every action is delivered process-targeted (AX / `postToPid`), never through the global HID tap. While locked, screenshots return an empty image, so `element_index` is preferred for locating elements.
- **[Security hardening]**: adversarial re-review found a confused-deputy issue — a same-uid, unauthenticated socket could forge this flag per-call. Changed so the flag is only passed in via a trusted launch env and is stripped from the per-call key on the agent side.
- **[Verification]**: +7 lock-screen policy tests, 172 tests total all green; full workspace build passed; `make check-docs` passed.

### 🧠 Design Intent (Why)
Unattended agents need to keep working while the screen is locked, but the team's earlier brainstorm had already concluded that claiming "Lock Screen support" isn't defensible, which is why the guard was deliberately fail-closed. This round doesn't overturn that decision: the default stays unchanged, and only an explicit opt-in is added, honestly documenting the limitations (screenshots unavailable, coordinate-only is unreliable) and the remaining same-uid trust boundary. The security-sensitive switch is only passed through the launch env, avoiding per-call socket forgery.

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MacSessionGuard.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift`
- `README.md`
- `docs/ARCHITECTURE.md`
- `docs/RELIABILITY.md`
- `docs/SECURITY.md`
- `docs/histories/2026-07/20260718-1044-merge-upstream-v020-work-while-locked.md`
