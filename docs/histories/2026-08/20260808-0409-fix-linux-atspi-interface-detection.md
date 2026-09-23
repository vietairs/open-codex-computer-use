## [2026-08-08 04:09] | Task: Fix Linux AT-SPI interface detection

### 🤖 Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5.6`
* **Runtime**: `T3 Code / Codex harness`

### 📥 User Query
> Fix the upstream issue found in the Linux text-editing flow, and prepare a Pull Request.

### 🛠 Changes Overview
**Scope:** Linux Computer Use runtime

**Key Actions:**
- **Standard interface detection**: Use `Accessible.get_interfaces()` to determine `Text` and `EditableText` capability, removing access to attributes that don't exist in some PyGObject environments.
- **Regression coverage**: Added Python tests with no desktop dependency, and wired them into the repo's baseline CI.
- **Documentation sync**: Updated the Linux architecture notes, troubleshooting guide, and user-facing feature record.

### 🧠 Design Intent (Why)
Ubuntu 24.04's AT-SPI GI binding does not provide the `Accessible.is_text` and `Accessible.is_editable_text` attributes. The original implementation would throw an `AttributeError` before reaching the fault-tolerant wrapper, making the snapshot and text tools unusable. `get_interfaces()` is the capability-query interface the binding actually provides, and it degrades safely across different toolkit nodes.

### 📁 Files Modified
- `apps/OpenComputerUseLinux/runtime.py`
- `apps/OpenComputerUseLinux/runtime_test.py`
- `scripts/ci.sh`
- `docs/ARCHITECTURE.md`
- `skills/open-computer-use/references/troubleshooting.md`
- `docs/releases/feature-release-notes.md`
