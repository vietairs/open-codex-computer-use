## [2026-09-01 10:20] | Task: Isolate the embedded App Agent socket

### 🤖 Execution Context
* **Agent ID**: `Codex desktop`
* **Base Model**: `GPT-5`
* **Runtime**: `macOS arm64`

### 📥 User Query
> Fix the issue where the Electron-embedded OCU has its page-action connection closed because another OCU's App Agent Socket contends with it at runtime; must not affect the user's global OCU.

### 🛠 Changes Overview
**Scope:** macOS App Agent proxy, socket path contract, unit tests, and architecture/security docs.

**Key Actions:**
- **[Optional namespace]**: Added `OPEN_COMPUTER_USE_AGENT_SOCKET_NAMESPACE`. When unset or empty, it strictly keeps using `open-computer-use-agent.sock`.
- **[Private socket]**: When a namespace is set, a short socket filename is derived from the first 16 hex characters of its SHA-256 digest, without leaking the raw value.
- **[Verification]**: Unit tests cover default compatibility, determinism, and isolation between namespaces; `OpenComputerUse` builds successfully.

### 🧠 Design Intent (Why)
Different OCU bundles used to share one fixed socket; when a bundle found the Agent on that socket belonged to another bundle, it would terminate it. The optional namespace lets an embedded host have its own private Agent, without changing the behavior of any existing CLI, MCP, or global install that does not configure a namespace.

### ✅ Verification
- `swift test --filter OpenComputerUseKitTests/testAppAgentSocketFileName`: 2 tests passed.
- `swift build --product OpenComputerUse`: passed; only the pre-existing `nonisolated(unsafe)` warning remains.

### 📁 Files Modified
- `apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AppAgentSocketNamespace.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/ARCHITECTURE.md`
- `docs/SECURITY.md`
