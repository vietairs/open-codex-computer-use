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
3. Start the sidecar: `scripts/decision-model/start-sidecar.sh`. It starts `llama-server` bound to loopback only, on
   a deterministic per-user port (`39000 + uid % 1000` by default), and prints an export line such as:
   ```sh
   export OPEN_COMPUTER_USE_DECISION_MODEL_URL=http://127.0.0.1:39xxx
   ```
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
5. Stop the sidecar with `scripts/decision-model/stop-sidecar.sh` when done.

The sidecar is always user-started; open-computer-use never spawns it. About 16 GB of unified memory is recommended
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
- `latency_ms`: wall-clock time for the model call(s) behind this result.
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

`recommended_min_margin` is **0.72**: at that margin, precision is 0.90 on dev and 0.9286 on test, at roughly 17%
coverage. Below the margin, unconditional advice is wrong more often than right — the full analysis and failure
causes are in `docs/exec-plans/active/20260922-local-decision-model-mcp-tool.md`. Full numbers, including the
per-cause pruning breakdown, are in `scripts/decision-model/eval-data/summary.json`.

## Security notes

- **Loopback only.** The client accepts only literal `127.0.0.1` or `[::1]` hosts (not `localhost`), follows no
  redirects, and enforces a request size cap and timeouts.
- The goal string and the pruned candidate rows are sent to the local sidecar over that loopback connection. A
  same-uid process that already has access to this host can already read the same accessibility tree via
  `get_app_state`, so this does not grant a new capability, but it is still local network traffic worth knowing
  about.
- **Screen text is untrusted input to the model.** Special tokens and stray angle-bracket sequences are stripped
  from goal and row text before they reach the prompt, and the readout is grammar-constrained to the offered labels,
  but the result is still advice, not a verified fact.
- **Follow the destructive-action rule regardless of margin.** A high margin never overrides the requirement to ask
  before sending, deleting, purchasing, or otherwise acting outside the current app state.

## Not supported

- Linux and Windows runtimes: this tool is macOS-only (`Package.swift` declares `.macOS(.v14)` only); the Go-based
  Linux/Windows runtimes do not gain this tool.
- Automatic weight download: weights are fetched only when `fetch-model.sh` is run explicitly.
- Weights bundled in npm: the npm package never carries model weights; the sidecar and weights are always a
  separate, user-managed local step.
