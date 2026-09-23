## [2026-04-17 16:19] | Task: Add Codex mitm capture script

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Write me a `codex_dump.py` to capture Codex's upstream API and WebSocket traffic via mitmproxy/mitmweb.

### 🛠 Changes Overview
**Scope:** `scripts`, `README.md`, `.gitignore`, `docs/references`, `docs/histories`

**Key Actions:**
- **[Capture script]**: Added `scripts/codex_dump.py` to persist Codex-related HTTP and WebSocket traffic.
- **[Background launch script]**: Added `scripts/start-codex-mitm-dump.sh`, which auto-creates a session directory, launches mitmdump in the background, and prints a proxy environment that can be `source`d directly.
- **[Default redaction]**: Redacts `Authorization`, cookies, and common token fields by default, avoiding writing login credentials to disk verbatim.
- **[Minimal docs]**: Added basic usage for running mitmdump/mitmweb against Codex's main link to `README.md`.
- **[Sample ignore]**: Added `artifacts/codex-dumps/` to `.gitignore` so analysis samples can stay in the repo directory for long-term viewing.
- **[Reusable runbook]**: Added `docs/references/codex-network-capture.md`, spelling out foreground capture, background launch, session directory conventions, and the follow-up eval analysis flow.

### 🧠 Design Intent (Why)
Codex's current main model calls go through the `chatgpt.com/backend-api/codex/responses` WebSocket rather than a traditional REST body. The repo needs a reusable, redacted-by-default script that doesn't commit real capture results into the repo, instead of stitching together an ad hoc addon from chat context each time.

### 📁 Files Modified
- `.gitignore`
- `scripts/codex_dump.py`
- `scripts/start-codex-mitm-dump.sh`
- `README.md`
- `docs/references/README.md`
- `docs/references/codex-network-capture.md`
- `docs/histories/2026-04/20260417-1619-add-codex-mitm-dump-script.md`

## [2026-04-17 17:50] | Task: Improve the Codex dump script, add local session summaries

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Improve `codex_dump.py` so the capture directory makes it easier to see normal requests, MCP tool calls, and tool results directly.

### 🛠 Changes Overview
**Scope:** `scripts`, `README.md`, `docs/references`, `docs/histories`

**Key Actions:**
- **[Local summary export]**: Extended `scripts/codex_dump.py` to, alongside the HTTP/WebSocket dump, export the `~/.codex/sessions/rollout-*.jsonl` matching the current websocket `session_id` into `local-sessions/*.json`.
- **[Structured results]**: `local-sessions/*.json` keeps only high-signal fields, including `user_prompts`, `tool_calls`, parsed `function_call_output` results, and `final_answer`, instead of copying the raw session JSONL directly.
- **[Precise matching]**: Prefers the `session_id` from the websocket handshake header to precisely correlate the local session, avoiding sweeping older sessions from the same time window into the current dump directory.
- **[Startup robustness]**: `scripts/start-codex-mitm-dump.sh` now confirms the port is actually listening before returning, and redirects mitmdump's stdin to `/dev/null`.
- **[Doc ordering update]**: Updated the runbook to state the new default triage order: `websocket/` -> `local-sessions/` -> `logs_2.sqlite`.

### 🧠 Design Intent (Why)
What the user actually needs to analyze usually isn't the "which tool did the model decide to call" half, but "what `function_call` did the host ultimately dispatch to the local MCP, and what `function_call_output` did it get back." Putting this summary layer directly into the same dump directory significantly lowers the cost of switching back and forth between `mitm` samples and `~/.codex/sessions`, and is also better suited for long-term eval archiving.

### 📁 Files Modified
- `scripts/codex_dump.py`
- `scripts/start-codex-mitm-dump.sh`
- `README.md`
- `docs/references/README.md`
- `docs/references/codex-network-capture.md`
- `docs/references/codex-local-runtime-logs.md`
- `docs/histories/2026-04/20260417-1619-add-codex-mitm-dump-script.md`
