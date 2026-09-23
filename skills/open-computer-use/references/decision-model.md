# Local Decision Model (`decide_next_action`)

Read this reference when a host wants advisory next-step suggestions from a local decision model, in addition to the
core Computer Use tools.

## What it is

`decide_next_action` is an **experimental, macOS-only, read-only** advisory tool. It prunes the current app's
accessibility tree into an actionable candidate table, runs one forward pass on a local model, and returns a
suggested operation and target element with full probability distributions. It **never acts**: the host agent still
calls `click`, `set_value`, `scroll`, and the other action tools itself. The tool is **off by default** and is not
listed by `tools/list` unless a decision-model URL is configured (see Setup).

## Setup

1. Install llama.cpp: `brew install llama.cpp`.
2. Fetch the pinned model weights (explicit, never automatic): `scripts/decision-model/fetch-model.sh`. This
   downloads about 2.7 GB and verifies the file's SHA-256 against `scripts/decision-model/model-manifest.json`
   before use.
3. Start the sidecar: `scripts/decision-model/start-sidecar.sh`. It starts `llama-server` bound to `127.0.0.1` only,
   on a deterministic per-user port (`39000 + uid % 1000` by default), records it in a pid file under
   `~/Library/Application Support/OpenComputerUse/decision-model/run/`, and prints an export line such as:
   ```sh
   export OPEN_COMPUTER_USE_DECISION_MODEL_URL=http://127.0.0.1:39xxx
   ```
   Only one sidecar runs per user. Running the script again reuses the recorded sidecar only if it listens on the
   requested port and passes the same readout check (including the served model file); otherwise it exits non-zero
   and asks you to run `stop-sidecar.sh` first.
4. Put `OPEN_COMPUTER_USE_DECISION_MODEL_URL` in the MCP server entry's `env` (not the calling shell), then restart
   the host so it re-reads the server config.

   JSON:
   ```json
   {
     "mcpServers": {
       "open-computer-use": {
         "command": "open-computer-use",
         "args": ["mcp"],
         "env": {
           "OPEN_COMPUTER_USE_DECISION_MODEL_URL": "http://127.0.0.1:39xxx"
         }
       }
     }
   }
   ```

   Codex TOML:
   ```toml
   [mcp_servers.open_computer_use]
   command = "open-computer-use"
   args = ["mcp"]
   env = { OPEN_COMPUTER_USE_DECISION_MODEL_URL = "http://127.0.0.1:39xxx" }
   ```
5. Stop the sidecar with `scripts/decision-model/stop-sidecar.sh` when done. It signals only the recorded pid, and only
   while that pid still has the recorded start time and runs the recorded `llama-server` binary.

The sidecar is always user-started; open-computer-use never spawns it. The tool talks only to a sidecar started by
`start-sidecar.sh` (see Security notes); a `llama-server` started by hand is refused. About 16 GB of unified memory is recommended
to run the 4B model comfortably alongside its KV cache.

## Cascade guide

The following text is the host-facing guidance shipped with the tool (embedded verbatim in the MCP `initialize`
instructions when the tool is enabled, and mirrored here from
`packages/OpenComputerUseKit/Sources/OpenComputerUseKit/DecisionAdvisor.swift`):

```text
decide_next_action (experimental, advisory): a local model proposes the next operation and target from the current app state. It never acts.
- Follow the advice only when margin >= recommended_min_margin AND the operation is non-destructive (not send, delete, purchase, submit, sign in/out, or anything externally visible) AND chosen_row_text matches your intent.
- Otherwise call get_app_state and decide yourself. Low margin means the model is unsure.
- Pass your own sub-goal in plain words. Never paste screen text into goal.
- element_index values are valid for the next click, set_value, or scroll on the same app, exactly like get_app_state.
```

## Result fields

- `advisory` (always `true`): a signal the result is a suggestion, never an already-taken action.
- `experimental` (always `true`).
- `operation`: the chosen operation.
- `element_index`: the chosen target's index, valid for the next `click`/`set_value`/`scroll` on the same app, or
  `null` when the operation needs no target.
- `margin`: the smaller of `operation_margin` and `target_margin` when a target is needed, else `operation_margin`.
- `operation_margin`: top1 minus top2 probability of `operation_distribution`.
- `target_margin`: top1 minus top2 probability of `target_distribution` (1.0 when only one candidate was offered).
- `recommended_min_margin`: the threshold below which the cascade guide says not to auto-follow.
- `chosen_row_text`: the candidate row text for the chosen target, or `null` when no target was chosen. Use it to
  sanity-check the model actually picked the element you expect.
- `operation_distribution`: full probability distribution over every possible operation.
- `target_distribution`: probability distribution over every offered candidate target, `P(target | chosen
  operation)`; the leading entries also carry `row_text`.
- `candidates`: `offered`, `actionable`, `pages_queried`, and `dropped` (pruning reasons with non-zero counts).
- `latency_ms`: wall-clock time for candidate pruning and the model call(s) behind this result. It does not include
  the accessibility refresh that precedes them.
- `note`: a one-line restatement of the cascade guide's core rule.

## Measured quality

Gates measured on the test split of a 254-item local eval set (model `qwen3.5-4b-q4km`, llama.cpp
`b10964-b29c606e2`, measured 2026-09-23 on an Apple M4 Max, 48 GB — latency figures are an optimistic bound; the p50
gate is specified for a 16 GB M-series machine):

| Gate | Threshold | Test value | Result |
|---|---|---|---|
| top-1 accuracy | ≥ 0.80 | 0.443 | FAIL |
| margin AUROC | ≥ 0.70 | 0.8286 | PASS |
| correct target pruned | ≤ 0.05 | 0.0938 (6 of 64) | FAIL |
| p50 latency | < 1500 ms | 509 ms | PASS |

The latency figures are the advisor's `latency_ms` (candidate pruning plus the model round trip). They exclude the
accessibility refresh and rendering the live call performs first, which costs about as much as a `get_app_state`, and
the MCP and app-agent hops, so a live call takes longer. The 79 test items come from only 7 screens (the split is by
snapshot), and items from one screen are correlated, so the test AUROC and the test precision below are weaker
evidence than the item count suggests.

`recommended_min_margin` is **0.72**: at that margin, precision is 0.90 on dev and 0.9286 on test, at roughly 17%
coverage. Below the margin, unconditional advice is wrong more often than right — the full analysis and failure
causes are in `docs/exec-plans/active/20260922-local-decision-model-mcp-tool.md`. Full numbers, including the
per-cause pruning breakdown, are in `scripts/decision-model/eval-data/summary.json`.

## Security notes

- **Loopback only.** The client accepts only the literal `127.0.0.1` host: not `localhost`, and not `[::1]`, because
  the sidecar binds IPv4 only and any same-uid process could listen on the IPv6 loopback port. It follows no
  redirects, and enforces a response size cap and timeouts.
- **The sidecar has no authentication, and its port is predictable.** The goal and up to 52 accessibility rows, read
  by the Accessibility-privileged agent, go to whatever process listens on `127.0.0.1:<port>`. When the sidecar is not
  running, for example after `stop-sidecar.sh`, a crash, or a reboot while the URL is still in the MCP config, any
  process of the same user could hold that port, including a sandboxed app that has no Accessibility access of its
  own. So before each request the agent checks that the listener is the sidecar that `start-sidecar.sh` recorded: the
  recorded pid must be running the recorded `llama-server` binary (as the kernel reports it) and must hold the
  `127.0.0.1:<port>` listening socket. If not, the call fails and nothing is sent. The pid file lives outside every
  sandbox container. Residual risk: a non-sandboxed process of the same user can forge the pid file and run its own
  binary named `llama-server`; such a process already has the user's full file access.
- **Per-host configuration.** In the shared app agent, each call reads the decision-model URL from the calling host's
  own MCP environment only, never from another host's settings.
- **Screen text is untrusted input to the model.** Special tokens and stray angle-bracket sequences are stripped
  from goal and row text before they reach the prompt, and the readout is grammar-constrained to the offered labels,
  but the result is still advice, not a verified fact. Error results never quote text generated by the server.
- **Follow the destructive-action rule regardless of margin.** A high margin never overrides the requirement to ask
  before sending, deleting, purchasing, or otherwise acting outside the current app state.

## Not supported

- Linux and Windows runtimes: this tool is macOS-only (`Package.swift` declares `.macOS(.v14)` only); the Go-based
  Linux/Windows runtimes do not gain this tool.
- Automatic weight download: weights are fetched only when `fetch-model.sh` is run explicitly.
- Weights bundled in npm: the npm package never carries model weights; the sidecar and weights are always a
  separate, user-managed local step.
