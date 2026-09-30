# Phase 01 — Sidecar and model scripts, readout pin

Parallel group G1 (with 02, 03). No dependencies. Executor: sonnet implementer; an opus reviewer reads `check-readout.mjs` and the pin output.
Worktree: `/Users/hvnguyen/Projects/open-codex-computer-use/.claude/worktrees/decision-model`.

## Goal

Let a user fetch pinned weights explicitly, start and stop `llama-server` on a deterministic per-user loopback port, and
verify, against the installed llama.cpp build, that (a) every label is one token, (b) the chat-template framing is what
the Swift prompt builder will emit, and (c) the readout probability semantics are what phase 04 parses. The output is a
committed, synthetic, personal-data-free pin file that phase 04's unit tests consume.

## Context (verified)

- llama.cpp is installed: `/opt/homebrew/bin/llama-server`, `Version: 0.4.1 (build 10964, commit b29c606e2)`.
  `/opt/homebrew/bin` is **not** on the agent shell's default PATH, so scripts must resolve `llama-server` via
  `command -v`, then `/opt/homebrew/bin`, then `/usr/local/bin`.
- Flags present in this build: `--host`, `--port`, `--parallel`, `--no-webui`, `--ctx-checkpoints`, `--api-key(-file)`,
  `--reasoning [on|off|auto]`.
- `/completion` options used: `prompt`, `grammar`, `n_predict`, `temperature`, `n_probs`, `post_sampling_probs`,
  `cache_prompt`. Response: `completion_probabilities[] = {id, token, logprob, bytes, top_logprobs[]}` when
  `post_sampling_probs` is false. Server code `populate_token_probs` takes the non-post-sampling branch from
  `get_token_probabilities(ctx, idx, n_probs)`, which is the raw logits distribution.
- Model (K9 in plan.md): primary `unsloth/Qwen3.5-4B-GGUF` revision `720bb031aae5488eae5d6a78768e6d826662b2ae`, file
  `Qwen3.5-4B-Q4_K_M.gguf`, 2,740,937,888 bytes, HF LFS sha256
  `00fe7986ff5f6b463e62455821146049db6f9313603938a70800d1fb69ef11a4`, license apache-2.0. Fallback
  `unsloth/Qwen3-4B-Instruct-2507-GGUF` file `Qwen3-4B-Instruct-2507-Q4_K_M.gguf`, 2,497,281,120 bytes, sha256
  `3605803b982cb64aead44f6c1b2ae36e3acdb41d8e46c8a94c6533bc4c67e597`, revision
  `a06e946bb6b655725eafa393f4a9745d460374c9` (HF `main` on 2026-09-23; the tree API at that revision returns the same
  size and oid).
- Re-verified 2026-09-23 10:15: the primary pin `720bb031…` still resolves, and the current `main`
  (`e87f176479d0855a907a41277aca2f8ee7a09523`) carries a byte-identical `Qwen3.5-4B-Q4_K_M.gguf` (same size and oid). Keep
  `720bb031…`. The sha256 is the binding pin, and the revision only fixes the URL.
- Where the real hash comes from: `curl -s https://huggingface.co/api/models/<repo>/tree/<revision>` → entry `lfs.oid`
  (sha256) and `lfs.size`. After download, `shasum -a 256 <file>` must equal it. Both values go in the manifest.
- Uid on this machine is 501, so the default port is `39000 + 501 % 1000 = 39501`.

## Signature

`scripts/decision-model/model-manifest.json`:
```json
{
  "schemaVersion": 1,
  "active": "qwen3.5-4b-q4km",
  "models": {
    "qwen3.5-4b-q4km": {
      "repo": "unsloth/Qwen3.5-4B-GGUF",
      "revision": "720bb031aae5488eae5d6a78768e6d826662b2ae",
      "filename": "Qwen3.5-4B-Q4_K_M.gguf",
      "sizeBytes": 2740937888,
      "sha256": "00fe7986ff5f6b463e62455821146049db6f9313603938a70800d1fb69ef11a4",
      "license": "apache-2.0",
      "chatTemplateKwargs": { "enable_thinking": false }
    },
    "qwen3-4b-instruct-2507-q4km": { "repo": "unsloth/Qwen3-4B-Instruct-2507-GGUF", "revision": "a06e946bb6b655725eafa393f4a9745d460374c9",
      "filename": "Qwen3-4B-Instruct-2507-Q4_K_M.gguf", "sizeBytes": 2497281120,
      "sha256": "3605803b982cb64aead44f6c1b2ae36e3acdb41d8e46c8a94c6533bc4c67e597", "license": "apache-2.0", "chatTemplateKwargs": {} }
  },
  "llamaCpp": { "testedBuild": 10964, "testedCommit": "b29c606e2", "install": "brew install llama.cpp" }
}
```

CLI contracts (all `set -euo pipefail`, `--help` prints usage, exit codes as listed):
```
scripts/decision-model/fetch-model.sh [--model <key>]
    Downloads https://huggingface.co/<repo>/resolve/<revision>/<filename> with curl
    (--fail --location --proto '=https' --tlsv1.2) to
    "$HOME/Library/Application Support/OpenComputerUse/decision-model/models/<filename>.partial",
    verifies size + sha256 against the manifest, then renames it. Exit 0 = verified file in place (already-present-and-valid
    is also 0 with no download); 2 = hash/size mismatch (partial deleted); 1 = other error.
    Never runs implicitly; nothing else calls it.

scripts/decision-model/start-sidecar.sh [--model <key>] [--port <n>]
    Port default: ${OCU_DECISION_MODEL_PORT:-$((39000 + $(id -u) % 1000))}.
    Refuses (exit 3) if the model file is missing (prints the fetch command) or its sha256 != manifest.
    If the pid file names a live llama-server on that port → prints the export line, exit 0 (idempotent reuse).
    If the port is held by any other process → exit 4 with `lsof -nP -iTCP:<port> -sTCP:LISTEN` output; never picks another port.
    Launches: env -i HOME="$HOME" PATH="<dir of llama-server>:/usr/bin:/bin" llama-server -m <model>
              --host 127.0.0.1 --port <port> --parallel 1 --ctx-size 8192 --no-webui -ngl 99
    in the background; pid → ".../decision-model/run/llama-server.pid"; log → ".../decision-model/logs/llama-server.log";
    polls GET /health for up to 60 s; runs `node check-readout.mjs --url http://127.0.0.1:<port> --model <key>`;
    on success prints exactly:  export OPEN_COMPUTER_USE_DECISION_MODEL_URL=http://127.0.0.1:<port>
    On check-readout failure: stops the server it started, exit 5.

scripts/decision-model/stop-sidecar.sh
    SIGTERM the pid in the pid file only if its command line contains llama-server; wait ≤10 s; SIGKILL fallback; remove pid file.
    Exit 0 if nothing was running.

node scripts/decision-model/check-readout.mjs --url <base> --model <key> [--write-pin]
    Exit 0 when every assertion below holds; non-zero with a one-line reason per failed assertion.
    --write-pin writes scripts/decision-model/fixtures/readout-pin.json (see Acceptance).
```

Label and prompt constants that `check-readout.mjs` uses **must equal** what phase 04 hard-codes:
- target labels: `A`–`Z` then `a`–`z` (52), generated as the pieces `" A"`…`" z"`;
- operation labels: `A`–`G` for `click, set_value, type_text, scroll, press_key, wait, done` (in that order);
- grammar (GBNF): `root ::= op "\nTarget:" tgt` with `op ::= " A" | … | " G"` and `tgt ::= " A" | … ` over the page's labels;
- request: `{"prompt":…, "grammar":…, "n_predict":16, "temperature":0, "n_probs":128, "post_sampling_probs":false, "cache_prompt":true, "stream":false}`.

## Boundaries

```
TARGET:    scripts/decision-model/model-manifest.json
           scripts/decision-model/fetch-model.sh
           scripts/decision-model/start-sidecar.sh
           scripts/decision-model/stop-sidecar.sh
           scripts/decision-model/check-readout.mjs
           scripts/decision-model/fixtures/readout-pin.json
READ-ONLY: Package.swift, scripts/ci.sh, docs/SUPPLY_CHAIN_SECURITY.md
FORBIDDEN: any file under packages/, apps/, experiments/ (owned by 02/04/05);
           .gitignore and scripts/decision-model/eval-* and scripts/decision-model/eval-data/** (owned by 03/06);
           any npm dependency (Node scripts use only node: built-ins and global fetch);
           writing the model or any file > 1 MB into the repo; auto-download from any other script;
           binding to anything but 127.0.0.1; --api-key flags (out of scope, see plan.md risks)
```

## Steps

1. Resolve the fallback revision from the HF API and confirm both `lfs.oid` values match the manifest (write them in).
2. Write `fetch-model.sh` and run it for the active model. Paste the `shasum -a 256` output into the phase report.
3. Write `start-sidecar.sh` / `stop-sidecar.sh` using process-management rules: pid file, fixed port, no port hopping,
   and stop only what we started.
4. Write `check-readout.mjs` (tests-first is not applicable to a live-server probe; its assertions are the acceptance). Assertions:
   1. `GET /health` → 200.
   2. `GET /props` → `model_path` basename == manifest filename. Record `build_info` if present.
   3. `POST /tokenize {"content":" X","add_special":false,"with_pieces":true}` for each of the 52 target labels (a superset
      of the op labels): exactly 1 token whose piece == `" X"`.
   4. `POST /apply-template {"messages":[{"role":"system","content":"<<SYS>>"},{"role":"user","content":"<<USER>>"}], "chat_template_kwargs": <manifest kwargs>}`,
      plus `"add_generation_prompt": true` if the build needs it. Split the returned `prompt` around the sentinels into
      `{systemPrefix, systemToUser, userSuffixToAssistant}`, then append the empty think block if the template does not
      already emit it (Qwen3.5 with `enable_thinking:false` → `<think>\n\n</think>\n\n`). Record the result verbatim.
   5. A synthetic prompt: goal "Save the document", 5 fake candidates, `button Save` placed as label `C`. Built with the
      framing from (4) and ending `Operation:`, sent to `/completion` with the grammar and request above. Assert:
      `completion_probabilities.length >= 2`; first entry `token` ∈ op pieces; last entry `token` ∈ the page's target
      pieces; every page label piece appears in the last entry's `top_logprobs`; the op labels likewise at entry 0; at
      least one non-label token appears in `top_logprobs` at entry 0 (this proves the distribution is pre-sampling and raw,
      not grammar-masked); the argmax of the label-renormalised distribution == the generated token at both heads;
      the renormalised probabilities sum to 1 ± 1e-6.
   6. Measure wall time of 5 repeats of (5) and record p50 (informational only).
5. Run `start-sidecar.sh`. It calls `check-readout.mjs`; then run it again with `--write-pin`.
6. If step 4.3 or 4.5 fails on the primary model: follow the Failure Protocol first. If kongming confirms a model-level
   cause, set `"active"` to the fallback, fetch it, re-pin, and record the switch and its reason in the phase report
   (phase 07 copies it into the exec plan).

## Acceptance

Command sequence (run from the worktree root):
```
bash -n scripts/decision-model/*.sh && node --check scripts/decision-model/check-readout.mjs
scripts/decision-model/fetch-model.sh                      # exit 0; second run exits 0 without downloading
scripts/decision-model/start-sidecar.sh                    # exit 0, last line == "export OPEN_COMPUTER_USE_DECISION_MODEL_URL=http://127.0.0.1:39501"
scripts/decision-model/start-sidecar.sh                    # exit 0 again (reuse, no second process: `pgrep -f llama-server | wc -l` == 1)
node scripts/decision-model/check-readout.mjs --url http://127.0.0.1:39501 --model "$(node -e 'console.log(require("./scripts/decision-model/model-manifest.json").active)')" --write-pin   # exit 0
scripts/decision-model/stop-sidecar.sh && ! lsof -nP -iTCP:39501 -sTCP:LISTEN   # port free
make ci                                                     # green
```
Assertions on `scripts/decision-model/fixtures/readout-pin.json`:
- has keys `llamaCppVersion` (string containing `build 10964` or the actually installed build), `model` (manifest key),
  `labelsSingleToken: true`, `probabilitySemantics: "pre_sampling_logprobs_renormalized_over_labels"`,
  `template: {systemPrefix, systemToUser, userSuffixToAssistant}`, `operationLabels` (`["A",…,"G"]`), `targetLabels`
  (the synthetic page's labels, `["A",…,"E"]`), `request` (the exact JSON body sent, prompt and grammar included),
  `response` (the raw `/completion` JSON trimmed to `completion_probabilities` and `content`), `p50Ms`;
- contains no absolute home paths (`grep -c "$HOME" … == 0`) and is < 200 KB.
- Negative: corrupting one byte of a copy of the model and pointing `start-sidecar.sh` at it (via a temporary manifest
  entry in a scratch copy) → exit 3. Report it; do not commit the scratch manifest.

## Success criteria

The pin file is committed, the sidecar starts and stops idempotently on 39501, and all 6 readout assertions pass on the
active model. No weights are in git (`git ls-files | grep -c gguf` == 0).

## Risks and rollback

- Hybrid-model quirks → fallback model (step 6). The template needs an explicit think block → captured in the pin, and
  phase 04 builds from the pin.
- Rollback: `stop-sidecar.sh`, `git revert` the phase commit, and delete `~/Library/Application Support/OpenComputerUse/decision-model/`.

## Contract Rules

1. Implements to the SIGNATURE exactly. A signature that cannot work is a STOP, not a redesign — report it through the Failure Protocol.
2. Edits only within TARGET. Discovering that the change genuinely requires a FORBIDDEN file is a STOP with that finding, never a quiet widening.
3. Writes the acceptance assertions first where the plan says tests-first, confirms they FAIL, then implements until they pass.
4. Never weakens an assertion, never marks a test skipped, and never stubs an implementation to make one pass. A passing suite obtained this way is the specific failure this whole contract is built to prevent — cheap tiers reward-hack checkable specs more than strong ones do, so the escalation path exists precisely for the moment the spec looks unsatisfiable.
5. On any failed Verify, follows the `## Failure Protocol` already in the phase file. That is the backchannel; using it is correct behaviour, not an admission of failure.

## Failure Protocol

On any failed Verify or Acceptance step (non-zero exit, failed assertion, or output that differs from what is specified
here), the executor stops reasoning about the fix on its own. It spawns the `kongming` agent with: this phase file's path,
the exact failing command and its full output, `git diff -- <TARGET files>`, and the approaches already tried. It waits
for the advice, applies it within TARGET only, and re-runs the failed step. If `kongming` is unavailable, or its advice
needs a FORBIDDEN file or a changed Signature, the executor STOPS and reports `Status: BLOCKED` with the evidence. It never
silently retries the same approach and never weakens an assertion to get green.