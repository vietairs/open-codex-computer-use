# Codex Upstream Traffic Capture and Eval Sample Storage

This document describes how to use `mitmdump` plus the repo's own `scripts/codex_dump.py` to capture Codex's HTTP / WebSocket traffic to its upstream, and store the samples under the repo's `artifacts/codex-dumps/` directory for later analysis and eval.

In the default troubleshooting order, this document should take priority over `docs/references/codex-local-runtime-logs.md`:

- First look at the upstream LLM call dump.
- Then look at `local-sessions/*.json` in the same dump directory, to confirm the local `function_call` / `function_call_output`.
- Only check Codex's own lower-level local logs when these two layers still aren't enough to explain the local tool / MCP behavior.

The current `scripts/codex_dump.py` uses the `session_id` from the websocket handshake to also drop a summary of the corresponding `~/.codex/sessions/rollout-*.jsonl` into the current session directory, so many questions about the official `computer-use` no longer need an immediate detour into `logs_2.sqlite`.

## Use Cases

- Observing the actual shape of requests Codex sends upstream.
- Recording real response traces under different prompts / configs / models.
- Storing samples for later eval, regression comparison, or reverse-engineering analysis.
- Letting an agent start the capture in the background directly, then run a batch of Codex cases.

## Directory Convention

Capture results are recommended to consistently go to:

```text
artifacts/codex-dumps/<session-name>/
```

This directory is already ignored by `.gitignore`, so it's suitable for keeping real samples in the repo working tree long-term without accidentally committing them.

It's recommended to create a separate session directory per experiment, e.g.:

```text
artifacts/codex-dumps/20260417-basic-ok/
artifacts/codex-dumps/20260417-tool-call-case-a/
artifacts/codex-dumps/20260417-reasoning-compare-gpt54/
```

## Prerequisites

1. `mitmproxy` / `mitmdump` is installed locally.
2. The mitm CA file exists:

```text
$HOME/.mitmproxy/mitmproxy-ca-cert.pem
```

3. If you also need GUI apps to go through the proxy, you'll additionally need to import and trust the mitm CA in the system keychain; but for CLI capture, explicitly setting `SSL_CERT_FILE` is usually enough.

## Starting mitmdump in the Foreground

The most direct foreground way to run it:

```bash
mitmdump \
  --listen-host 127.0.0.1 \
  --listen-port 8082 \
  -s scripts/codex_dump.py \
  --set codex_dump_dir=artifacts/codex-dumps/session-001
```

Then, in another terminal, have Codex go through this proxy:

```bash
HTTPS_PROXY=http://127.0.0.1:8082 \
NO_PROXY=127.0.0.1,localhost \
SSL_CERT_FILE=$HOME/.mitmproxy/mitmproxy-ca-cert.pem \
codex exec --skip-git-repo-check -C /tmp 'reply with one word: ok'
```

## Starting mitmdump in the Background

If you want an agent or script to launch the capture in the background itself, prefer using the repo's own script directly:

```bash
./scripts/start-codex-mitm-dump.sh basic-ok
```

This script will automatically:

- Create `artifacts/codex-dumps/<session-name>/`
- Start `mitmdump` in the background
- Write `mitmdump.log`
- Write `mitmdump.pid`
- Generate `codex-proxy.env`, for convenient later `source`ing

The most common follow-up usage is:

```bash
source artifacts/codex-dumps/basic-ok/codex-proxy.env
codex exec --skip-git-repo-check -C /tmp 'reply with one word: ok'
```

If you need full manual control, you can also use the following equivalent low-level approach:

```bash
session_dir="artifacts/codex-dumps/$(date +%Y%m%d-%H%M%S)-basic-ok"
mkdir -p "$session_dir"

nohup setsid mitmdump \
  --listen-host 127.0.0.1 \
  --listen-port 8082 \
  -s scripts/codex_dump.py \
  --set codex_dump_dir="$session_dir" \
  </dev/null >"$session_dir/mitmdump.log" 2>&1 &

echo $! >"$session_dir/mitmdump.pid"
```

This approach has several advantages:

- Doesn't depend on an interactive terminal, so it's suitable for an agent to run directly.
- The log, PID, and captured content all land in the same session directory.
- When later batch-running multiple Codex cases, there's no need to keep manually watching the mitm UI.

Stop the capture:

```bash
kill "$(cat "$session_dir/mitmdump.pid")"
```

## Running a Codex Case Through the Proxy

The recommended fixed form is:

```bash
HTTPS_PROXY=http://127.0.0.1:8082 \
NO_PROXY=127.0.0.1,localhost \
SSL_CERT_FILE=$HOME/.mitmproxy/mitmproxy-ca-cert.pem \
codex exec --skip-git-repo-check -C /tmp 'reply with one word: ok'
```

If you need to run multiple cases, it's recommended to start `mitmdump` only once, then run multiple Codex commands serially, creating a separate session directory for each case.

## What Gets Captured Mainly

Currently, Codex's main model calls will typically hit:

```text
https://chatgpt.com/backend-api/codex/responses
```

This isn't a normal REST body; instead:

1. A `GET /backend-api/codex/responses` request is made first
2. It returns `101 Switching Protocols`
3. Subsequent traffic is carried over WebSocket frames:
   - `response.create`
   - `response.created`
   - `response.in_progress`
   - `response.output_text.delta`
   - `response.completed`

Supplementary traffic may also include:

- `https://chatgpt.com/backend-api/wham/apps`
- `https://chatgpt.com/backend-api/plugins/featured`
- analytics-related requests

## Output Structure

By default, `scripts/codex_dump.py` will produce:

```text
artifacts/codex-dumps/<session-name>/
  http/
  websocket/
  local-sessions/
```

Where:

- `http/*.json`
  Saves matched HTTP requests and responses.
- `websocket/*.jsonl`
  Saves WebSocket start, message, and end events, one per line.
- `local-sessions/*.json`
  A structured summary exported from `~/.codex/sessions/rollout-*.jsonl`, keeping only the user prompt, tool call, tool result, and final answer that match the current capture's `session_id`.
- `mitmdump.log`
  If started in background mode, contains mitmdump's own log.
- `mitmdump.pid`
  If started in background mode, holds the background process PID.

Putting these three layers together usually directly answers:

- `websocket/`
  When the model decided to call which tool, and what the call arguments were.
- `local-sessions/`
  Which `function_call` the Codex host actually dispatched to the local MCP, and what `function_call_output` was returned.
- `http/`
  Supplementary non-websocket requests, e.g. `wham/apps`, plugin/config initialization, etc.

## Redaction Defaults

The repo's `scripts/codex_dump.py` redacts the following by default:

- `Authorization`
- Cookie / Set-Cookie
- common token / api key fields

This reduces the risk of accidentally writing authentication info directly to disk, but it doesn't mean capture results can be shared freely. Samples may still contain:

- prompts
- tool call arguments
- model replies
- session metadata

So it's recommended to:

- Keep capture results local first.
- When archiving for eval, only share the necessary fragments or a further-redacted summary.
- Not remove `artifacts/codex-dumps/` from `.gitignore`.

## Recommended Workflow

1. Create a clearly named session directory.
2. Start `mitmdump` in the background.
3. Run a batch of Codex cases via `HTTPS_PROXY`.
4. Stop `mitmdump` when done.
5. Focus analysis on:
   - `response.create` in `websocket/`
   - `response.output_item.done` in `websocket/`, especially where `item.type=="function_call"`
   - the corresponding `tool_calls[].output` in `local-sessions/`
   - `response.output_text.delta`
   - `response.completed`
6. Record conclusions, differences, and eval results in the repo docs, rather than committing the raw captures directly.

## FAQ

### 1. Only some requests are visible, and the main LLM call is missing

Check in priority order:

- Whether Codex actually inherited `HTTPS_PROXY`
- Whether `SSL_CERT_FILE=$HOME/.mitmproxy/mitmproxy-ca-cert.pem` was set
- Whether you're actually capturing `chatgpt.com/backend-api/codex/responses`
- Whether you only looked at HTTP and not `websocket/*.jsonl`
- If you need local tool results, whether you also checked `local-sessions/*.json`

### 2. Why not just capture `api.openai.com` directly

On this machine, Codex's main path currently actually goes through `chatgpt.com/backend-api/codex/responses`, not the traditional `api.openai.com/v1/...`.

### 3. Why `ALL_PROXY` is not recommended by default

`ALL_PROXY` may also route local `127.0.0.1` MCP traffic through the proxy, which can easily interfere with the local debugging chain. Setting only `HTTPS_PROXY` is more stable by default.

### 4. The prompt says `computer-use` vs `open-computer-use` — why does the call path differ

In real samples on this machine as of 2026-04-17, the prompt wording itself noticeably affects which tool namespace the model tries first:

- When the prompt directly says `computer-use`
  the model first tries the official bundled `mcp__computer_use__*`.
- When the prompt directly says `open-computer-use`
  the model prefers the repo plugin's `mcp__open_computer_use__*`.

This means that when doing A/B debugging, the prompt naming itself is a variable that can't be ignored. To compare the two implementations more reliably, it's recommended to:

1. Use nearly identical task semantics for both groups of cases.
2. Only swap the tool-name anchor, e.g. `computer-use` vs `open-computer-use`.
3. Add a unique marker per experiment, to make precise filtering from `websocket/*.jsonl` and local logs easier.

### 5. When `open-computer-use` calls fail, how to tell whether it's the plugin host cancelling or the MCP server itself being broken

It's recommended to split the problem into two layers first:

1. Use MITM or local logs to see whether the Codex host actually initiated an `mcp__open_computer_use__*` call.
2. Directly do a minimal JSON-RPC probe against the plugin launcher, to verify whether the server itself can `initialize`, `tools/list`, `tools/call`.

For example:

```bash
printf '%s\n%s\n%s\n' \
'{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
'{"jsonrpc":"2.0","id":2,"method":"notifications/initialized","params":{}}' \
'{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_apps","arguments":{}}}' \
| ./plugins/open-computer-use/scripts/launch-open-computer-use.sh
```

If the direct JSON-RPC returns normally, but the Codex session still shows the tool as cancelled or never actually executed, suspect first:

- the Codex host / plugin gate
- the current session's policy toward third-party plugins
- the plugin cache or install state not being synced to the latest

Don't assume from the start that the MCP server's own logic is broken. Separating "host problem" from "server problem" first keeps the troubleshooting cost much lower.

### 6. When A/B testing the official `computer-use` against `open-computer-use`, explicitly isolate the other plugin

If both plugins are enabled at the same time, the tool-name anchor in the prompt will significantly affect the model's routing. For a cleaner A/B test, it's recommended to temporarily disable the other plugin for a single `codex exec` run, rather than running them side by side.

The repo already provides a helper for this:

```bash
./scripts/run-isolated-codex-exec.sh computer-use --skip-git-repo-check -C /tmp \
  'use computer-use to list the top three running apps'

./scripts/run-isolated-codex-exec.sh open-computer-use --skip-git-repo-check -C /tmp --json \
  'use open-computer-use to list the top three running apps'
```

Under the hood, it just adds a temporary config override to `codex exec`:

- `computer-use`
  adds `-c 'plugins."open-computer-use@open-computer-use-local".enabled=false'`
- `open-computer-use`
  adds `-c 'plugins."computer-use@openai-bundled".enabled=false'`

This is safer than editing `~/.codex/config.toml` directly, because:

- It only affects this single command.
- There's no need to manually change the global config and restore it afterward.
- It's better suited to batch eval or agent background scripts.

### 7. Isolation-verification conclusions on this machine

Isolation samples from 2026-04-17 have verified:

1. The `-c 'plugins."...".enabled=false'` override is effective.
2. With only the official `computer-use` kept enabled, `computer-use/list_apps` completes normally.
3. With only `open-computer-use` kept enabled, `open-computer-use/list_apps` still directly returns `user cancelled MCP tool call`.
4. Meanwhile, sending JSON-RPC directly to `./plugins/open-computer-use/scripts/launch-open-computer-use.sh` for `tools/list` / `tools/call list_apps` works normally.

This indicates that in the current environment:

- "The two plugins interfering with each other" is not the main issue.
- The `open-computer-use` MCP server itself is not the main failure point at this stage.
- The bottleneck is more likely still in the Codex host's gate or session policy for third-party plugin calls.

### 8. Background `mitmdump` reports a successful start, but the proxy port disappears quickly

Check `mitmdump.log` first. The repo's `scripts/start-codex-mitm-dump.sh` now additionally checks whether the port is actually listening, but in some sandboxed runner / agent hosts, the background child process can still get cleaned up when the parent process exits.

If you run into this, prefer one of the following more reliable approaches:

1. Run `./scripts/start-codex-mitm-dump.sh` in a real login shell, `tmux`, or a separate terminal.
2. Or run `mitmdump` / `mitmweb` in the foreground directly, and run `codex exec` in another terminal.
3. Don't mistake "the script returned a PID" for "the proxy must still be alive" — confirm the listening state first with `lsof -nP -iTCP:<port> -sTCP:LISTEN`.
