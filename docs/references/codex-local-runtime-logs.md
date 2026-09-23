# Codex Local Runtime Log Supplementary Observation

This document describes how, when upstream LLM packet captures aren't enough, to use Codex's own local logs to supplement observation of local tool / MCP behavior — especially for an MCP server like `computer-use` that goes over local `stdio`.

The default triage order should be:

1. First look at the upstream HTTP / WebSocket dump described in `docs/references/codex-network-capture.md`.
2. Then look at `local-sessions/*.json` in that same dump directory, which already exports a summary of the `function_call` / `function_call_output` pairs for the current `session_id`.
3. Only when these two layers still aren't enough to explain local tool behavior, check Codex's local logs.
4. Only when local logs still aren't enough, and you genuinely need the raw `stdio` JSON-RPC byte stream, consider a wrapper / shadow plugin / lower-level hook.

In most cases, the first 2 steps are already enough; this document is a deeper supplementary path, not the default entry point.

## Applicable scenarios

- Need to confirm exactly what arguments a given local MCP tool was called with.
- Need to confirm what result or error a given local tool call returned.
- Need to analyze a local `stdio` tool like the official `computer-use`, which doesn't go over the network and therefore won't show up in an MITM capture.
- Need to connect "which tool the model decided to call" with "what the local tool actually returned."

## Why this supplementary path is needed

What `mitmdump` captures is the HTTP / WebSocket traffic from Codex to the upstream model service; the enhanced `scripts/codex_dump.py` in this repo also conveniently drops a local session summary for the same `session_id` into `local-sessions/*.json`. These two layers are well-suited to answering:

- What context the model saw.
- When the model decided to call a given tool.
- What the tool call looks like at the model protocol layer.
- What `function_call` the Codex host ultimately dispatched to the local MCP.
- What `function_call_output` the local tool returned.

But if what you're looking into is more from the host's internal-log perspective, these two layers still can't show you:

- The complete `stdio` exchange byte stream between the Codex host and the local MCP server.
- Additional host-level events, error classifications, and instrumentation fields in `logs_2.sqlite`.
- Some context that isn't in the session JSONL summary.

In that case, looking at Codex's own lower-level local logs is usually enough.

## Main log location

For the current local Codex runtime, the most useful local log store is:

```text
$HOME/.codex/logs_2.sqlite
```

It's recommended to always query it read-only:

```bash
sqlite3 -readonly "$HOME/.codex/logs_2.sqlite" ".tables"
```

## What you can typically see in this log

For local MCP tools, two kinds of records typically show up in the log:

1. `ToolCall: mcp__...`
   These records show the arguments Codex actually dispatched to the tool.
2. `event.name="codex.tool_result"`
   These records show the summarized result the tool returned, its duration, success/failure status, and part of the output.

For the official `computer-use`, a common shape looks like:

```text
ToolCall: mcp__computer_use__click {"app":"com.example.SampleChat","x":194,"y":321}
```

```text
event.name="codex.tool_result" tool_name=mcp__computer_use__click ... arguments={"app":"com.example.SampleChat","x":194,"y":321} ... output=...
```

When the log granularity is sufficient, you can also see:

- `mcp_server=computer-use`
- `mcp_server_origin=stdio`
- Error returns, e.g. `Apple event error -10005: noWindowsAvailable`
- On success, the AX tree, window title, element fragments, or a tool output summary

## Common queries

### 1. Look at recent `computer-use` tool call arguments

```bash
sqlite3 -readonly "$HOME/.codex/logs_2.sqlite" "
SELECT datetime(ts,'unixepoch','localtime') AS t,
       substr(feedback_log_body,1,2400)
FROM logs
WHERE feedback_log_body LIKE '%ToolCall: mcp__computer_use__%'
ORDER BY ts DESC, ts_nanos DESC
LIMIT 50;
"
```

### 2. Look at recent `computer-use` tool return results

```bash
sqlite3 -readonly "$HOME/.codex/logs_2.sqlite" "
SELECT datetime(ts,'unixepoch','localtime') AS t,
       substr(feedback_log_body,1,3200)
FROM logs
WHERE feedback_log_body LIKE '%event.name=\"codex.tool_result\"%'
  AND feedback_log_body LIKE '%mcp_server=computer-use%'
ORDER BY ts DESC, ts_nanos DESC
LIMIT 50;
"
```

### 3. Look at arguments and results together

```bash
sqlite3 -readonly "$HOME/.codex/logs_2.sqlite" "
SELECT datetime(ts,'unixepoch','localtime') AS t,
       substr(feedback_log_body,1,3200)
FROM logs
WHERE feedback_log_body LIKE '%ToolCall: mcp__computer_use__%'
   OR (
        feedback_log_body LIKE '%mcp__computer_use__%'
    AND feedback_log_body LIKE '%output=%'
      )
ORDER BY ts DESC, ts_nanos DESC
LIMIT 100;
"
```

### 4. Filter by a specific tool

For example, only `get_app_state`:

```bash
sqlite3 -readonly "$HOME/.codex/logs_2.sqlite" "
SELECT datetime(ts,'unixepoch','localtime') AS t,
       substr(feedback_log_body,1,3200)
FROM logs
WHERE feedback_log_body LIKE '%mcp__computer_use__get_app_state%'
ORDER BY ts DESC, ts_nanos DESC
LIMIT 50;
"
```

### 5. Narrow down by thread id

If you already know the `thread_id=...` from a given record, you can filter further:

```bash
sqlite3 -readonly "$HOME/.codex/logs_2.sqlite" "
SELECT datetime(ts,'unixepoch','localtime') AS t,
       substr(feedback_log_body,1,3200)
FROM logs
WHERE thread_id = '<thread-id>'
ORDER BY ts DESC, ts_nanos DESC
LIMIT 100;
"
```

This is especially useful when multiple Codex sessions are running at the same time.

## Division of labor with upstream packet captures

The recommended split is:

- Upstream capture:
  Look at model input, model output, tool decisions, and protocol-layer event timing.
- Local runtime logs:
  Look at what arguments the local tool ultimately received, what result it returned, its duration, and the local MCP source.

A simple rule of thumb:

- If you want to answer "why did the model decide to call this tool," look at the upstream capture first.
- If you want to answer "what arguments did this local tool actually get, and what error did it return," look at the local logs first.

## One key conclusion about the official `computer-use`

For the official bundled `computer-use`, a more practical observation approach right now is usually not to intercept `stdio`, but to first make use of the logs the Codex host has already written to disk.

The reasons are:

- The official `computer-use` is itself a local `stdio` MCP.
- Network MITM by default can only capture the upstream LLM call, and can't see this local `stdio` path.
- The Codex host has already written a good amount of `mcp__computer_use__*` arguments and results into the local logs.

This means that in many scenarios, there's no need to do invasive interception at all.

## When a wrapper / shadow plugin is actually worth doing

The local logs may only fall short on questions like these:

- You need to see the raw newline-delimited JSON-RPC messages, not the host's tidied-up log summary.
- You need to confirm whether some edge-case field between the host and the local MCP server actually exists on the wire.
- You need a precise post-mortem of a framing / ordering issue that's beyond the host-side log granularity.

In that case, it's better to:

1. Copy the bundled plugin to make a repo-local shadow plugin.
2. Change the `command` in `.mcp.json` to your own wrapper.
3. In the wrapper, do minimal tee'ing: write stdin/stdout to disk on the side, then forward to the real binary.

Not recommended as a default:

- Network MITM
- `DYLD_INSERT_LIBRARIES`
- A resident binary proxy replacing the real parent process
- A dynamic hook that requires extra system permissions and carries long-term maintenance cost

## Risk and redaction

Local logs may contain:

- Prompt fragments
- Tool arguments
- Tool output
- Window titles, element text, URLs
- Session metadata

So it's recommended to:

- Query read-only, and never directly modify Codex's local state.
- Prioritize distilling conclusions, and don't commit raw log dumps into the repo.
- If results need to be captured in `docs/`, keep only the minimal, redacted fragments and conclusions necessary.

## Recommended workflow

1. First capture an upstream sample following `docs/references/codex-network-capture.md`.
2. First look at `local-sessions/*.json` in the same dump directory, confirming `function_call` and `function_call_output`.
3. If the first two layers of samples already answer the question, capture the conclusion directly in the repo docs.
4. If the question still lies in a deeper host-behavior layer around the local `stdio` MCP / `computer-use`, then check `logs_2.sqlite`.
5. Only when local logs still aren't enough, consider a wrapper / shadow plugin approach.

This order avoids jumping straight to a highly invasive, hard-to-maintain interception path.
