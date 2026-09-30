# Local Decision Model (`decide_next_action`)

Read this reference when a host wants advisory next-step suggestions from a local decision model, in addition to the
core Computer Use tools.

## What it is

`decide_next_action` is an **experimental, macOS-only, read-only** advisory tool. It prunes the current app's
accessibility tree into an actionable candidate table, runs the decision model (2 single-token model calls per
candidate page — one for the operation, one for the target — plus one more pair for a stage-2 call when there is
more than one page), and
returns a suggested operation and target element with full probability distributions. It **never acts**: the host
agent still calls `click`, `set_value`, `scroll`, and the other action tools itself. The tool is **off by default**
and is not listed by `tools/list` unless a backend is configured (see Setup).

Two backends are supported, chosen per call by `OPEN_COMPUTER_USE_DECISION_MODEL_BACKEND`:

- **`llama` (default)**: a loopback `llama-server` sidecar, configured with `OPEN_COMPUTER_USE_DECISION_MODEL_URL`.
  This is the setup documented below.
- **`remote`**: a remote, OpenAI-compatible vLLM "jev" engine over HTTPS with a bearer key, configured entirely from
  a local trusted file — never from the per-call environment. See "Remote backend" below.

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

## Remote backend (jev engine)

An alternative to the loopback sidecar: an advisory call to a remote, OpenAI-compatible vLLM engine running the
"jev" wire contract, over HTTPS with a bearer key. It is still advisory only — the server never acts — and still
macOS-only. vm100 (the reference jev deployment) is never touched by open-computer-use itself; this is a client only.

1. Create `~/Library/Application Support/OpenComputerUse/decision-model/remote-backend.json`, owned by your user,
   mode `600` (no group or other access — the loader refuses anything else):
   ```json
   {
     "base_url": "https://your-jev-host:8443",
     "model": "Qwen3.8-27B-NVFP4-jev",
     "api_key": "sk-..."
   }
   ```
   `base_url` must be `https`, with no userinfo, query, fragment, or path beyond `/`. `model` is 1-200 characters
   with no control characters. `api_key` is 1-512 printable ASCII characters with no whitespace.
2. Put `OPEN_COMPUTER_USE_DECISION_MODEL_BACKEND=remote` in the MCP server entry's `env` (not the calling shell),
   and leave `OPEN_COMPUTER_USE_DECISION_MODEL_URL` unset — setting both is rejected as ambiguous.
3. Restart the host so it re-reads the server config. `tools/list` (and with it the cascade guide in the tool's description) is gated the same way as
   the loopback backend, just on `OPEN_COMPUTER_USE_DECISION_MODEL_BACKEND=remote` instead of the URL.

The destination, model, and key are read only from that file, never from the per-call environment — see "Security
notes" for why. The remote backend offers up to 26 target candidates per page (the jev engine's single-token label
cap), versus 52 for the loopback backend; everything else about the tool's behavior and result shape is identical.
Each page still costs 2 single-token `/v1/completions` calls (operation, then target), with one more pair for a
stage-2 call when a goal's candidates span more than one page.

The first call against a given `(base_url, model)` in the process also pays a one-time cost: 27 sequential
`/tokenize` requests (the fixed sample prompt, then each letter A-Z) to resolve every letter's single token id,
all inside the same 12 s overall deadline as the rest of the call. Measured Mac→vm100 round-trip time is about
29 ms, so this comfortably fits on a LAN; over a high-latency link the first call's resolution can run out of
deadline and fail, and is retried from scratch on the next call.

## Cascade guide

The following text is the host-facing guidance shipped with the tool (embedded verbatim in the
`decide_next_action` tool description, so a host sees it exactly when the tool is listed, and mirrored here from
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
- **The remote backend's destination and key come only from a local trusted file, never a per-call value.** The app
  agent applies per-call `environment` overrides from any same-uid socket peer, so if the remote URL and key could
  arrive per call, any unprivileged same-uid process could redirect the TCC-privileged agent's accessibility reads to
  a host of its choosing. `remote-backend.json` is read only from
  `~/Library/Application Support/OpenComputerUse/decision-model/`, the same trust root as the sidecar's pid file:
  must be a regular file opened with `O_NOFOLLOW` (refusing a symlink at `open(2)` itself, so there is no
  separate-`lstat`-then-reopen race), owned by the current user, with no group or other access. Per-call environment
  may only select `remote` vs. `llama` (`OPEN_COMPUTER_USE_DECISION_MODEL_BACKEND`), never the destination itself.
  Residual risk, same as the sidecar's pid file: a non-sandboxed same-uid process can rewrite the config file; it
  already has the user's full file access.
- **The remote backend's key never appears in a tool result, log line, or error message.** Every config-loading
  error names the file path and the failing field, never the field's value; `DecisionRemoteBackendConfig` also
  redacts `apiKey` from `description`, `debugDescription`, and `dump(_:)` output. HTTPS uses the system's default
  TLS trust with no custom challenge handling; plain http is still refused for any non-loopback host.
- **What the remote backend actually sends, and who is trusting whom.** Every call sends the goal, the app name, and
  up to 52 screen rows (26 per page, across at most 2 pages, including the text-field contents of any offered rows)
  as plain text to the host named in `remote-backend.json` — the operator of that host sees this text in full. A
  compromised or malicious remote server fully controls the advice it returns (the chosen operation, target, and
  every reported margin), so following its advice without checking margin and operation type means trusting that
  host, not just reading its opinion. Selecting `backend=remote` is available to any local same-uid caller per call,
  but it only ever reaches the one host recorded in your own `0600` config file — that file's mere presence is the
  opt-in that makes every same-uid caller's `remote` selection meaningful. Delete the file to stop the backend from
  being reachable at all.

## Not supported

- Linux and Windows runtimes: this tool is macOS-only (`Package.swift` declares `.macOS(.v14)` only); the Go-based
  Linux/Windows runtimes do not gain this tool.
- Automatic weight download: weights are fetched only when `fetch-model.sh` is run explicitly.
- Weights bundled in npm: the npm package never carries model weights; the sidecar and weights are always a
  separate, user-managed local step.
