## [2026-04-20 14:16] | Task: Add sequential call support to computer-use-cli

### 🤖 Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `gpt-5.4`
* **Runtime**: `Codex CLI`

### 📥 User Query
> I want to connect to the official bundled `computer-use` myself via `scripts/computer-use-cli/`, reproduce which tool calls trigger the overlay cursor, and test it directly with `go run`.

### 🛠 Changes Overview
**Scope:** `scripts/computer-use-cli`

**Key Actions:**
- **Added the `call-seq` subcommand**: Allows executing multiple tool calls in sequence within the same direct MCP connection or the same app-server ephemeral thread, addressing the official `computer-use`'s requirement that action-type tools be preceded by a `get_app_state` call.
- **Added an official self-test sample**: Added `examples/textedit-overlay-seq.json`, containing a positive-case sequence of `get_app_state -> set_value -> scroll -> perform_secondary_action`.
- **Updated docs and tests**: Added `call-seq` usage and limitation notes to the README, with unit tests covering sequential-call JSON parsing.

### 🧠 Design Intent (Why)
The official bundled `computer-use` requires that, before an action-type tool call, the same thread already holds the latest state for the corresponding app. The original `call` command created a new app-server ephemeral thread every time, making it impossible to reproduce this chain directly with `go run`. With `call-seq` added, users can reliably reproduce the observed path using a single JSON file, which is also better suited for further comparisons against official behavior going forward.

### 📁 Files Modified
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/app_server.go`
- `scripts/computer-use-cli/main_test.go`
- `scripts/computer-use-cli/README.md`
- `scripts/computer-use-cli/examples/textedit-overlay-seq.json`

### 🔁 Follow-up (2026-04-20 15:07)

- **[9-tool coverage sample]**: Expanded `examples/textedit-overlay-seq.json` into a `TextEdit` sequence covering all 9 official tools, making it easy to manually observe the overall effect directly via `go run . call-seq`.
- **[Documented the official stale-state constraint]**: The sample explicitly inserts a `get_app_state` between every action that changes app state, because the official bundled `computer-use` returns a "re-query the latest state first" constraint after a mutation.

**Follow-up Files:**
- `scripts/computer-use-cli/README.md`
- `scripts/computer-use-cli/examples/textedit-overlay-seq.json`

**Follow-up Files:**
- `scripts/computer-use-cli/README.md`
- `scripts/computer-use-cli/examples/textedit-overlay-seq.json`
