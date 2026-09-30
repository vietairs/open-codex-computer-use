# Review — "Hybrid Computer Use" Part 1 (jev_fast_engine, Rust/PyO3 client)

Verdict: **do not implement as written.** Stopped before worktree/implementation/release. The plan collides with a locked
scope decision, with the repo's actual stack, and with the shipped `decide_next_action` security model. A narrow,
in-scope slice is salvageable (see Options).

## Blocking findings

1. **Locked scope violation.** `execute_fast_step(server_url, goal, threshold)` takes a goal, picks a target and clicks
   it. That is the server owning a goal, which the 2026-09-22 decision rejects "regardless of how well it benchmarks".
   The "System 2 Fallback Planner" is a second server-side planning loop. The shipped equivalent,
   `decide_next_action`, is advisory-only by design (`skills/open-computer-use/references/decision-model.md`: "It never
   acts").
2. **No host for the code.** The repo has no Python agent: `src/agent/hybrid_agent.py`, `planner.py`, `System2Planner`,
   `main.py`, `pyproject.toml` and pyautogui do not exist. The MCP server is Swift on macOS
   (`packages/OpenComputerUseKit`) and Go binaries on Linux/Windows (`apps/OpenComputerUse{Linux,Windows}`). A PyO3
   cdylib would have nothing to load it. Adding Rust + Python as a third and fourth toolchain to a fork that tracks
   upstream is a large, permanent sync cost.
3. **Fake data.** `macos.rs` returns two hardcoded candidates ("Search Input" at 450,200; "Submit Flight" at 520,350).
   `windows.rs` and `linux.rs` return empty vectors. The fast path would click fixed screen coordinates on every
   machine. The real AX traversal — the hard part — is unwritten, and already exists in Swift.
4. **Security regression.** Shipped design: loopback-only sidecar, verified by pid/start-time/binary/LISTEN socket
   (`DecisionSidecarVerifier.swift`, `docs/SECURITY.md`). Plan: plaintext, unauthenticated HTTP to
   `192.168.1.100` by default, sending the goal and on-screen labels off-machine, then auto-clicking on the reply.
   Screen text goes into the prompt unescaped, so any window content can steer a click (prompt injection → action).
5. **Measured evidence says the model cannot be trusted to act.** The shipped classifier measured top-1 0.443 (FAIL)
   and correct-target-pruned 0.094 (FAIL); only margin AUROC passed. The plan's 0.75 auto-click threshold is
   uncalibrated and has no eval behind it.

## Correctness defects (would need fixing even if scope allowed)

- `enigo = "0.2"` but code uses the 0.1 API (`MouseControllable`, `Enigo::new()`, `mouse_move_to`); 0.2 uses the
  `Mouse` trait, `Enigo::new(&Settings)` returning `Result`, `move_mouse(.., Coordinate::Abs)`. Won't compile.
- Generic types stripped in the paste (`Vec`, `PyResult>`, `OnceLock`, `Vec>`) — won't compile as given.
- Missing candidates default to logprob -100 and the softmax renormalizes over only returned top-k tokens, so
  confidence is inflated when most options fall outside top-k.
- Alphabet capped at 10 labels (A–J); the shipped tool handles ~52 single-token labels plus deterministic pruning.
- No Retina/points-vs-pixels handling between AX coordinates and the mouse event.
- Model identity is inconsistent: "Qwen3.8-27B-NVFP4" is claimed to come from Qwen2.5-32B; quantization does not
  change parameter count. Treat the model name as unverified.
- Latency table (AX scrape 1.5–3 ms on a real app) is asserted, not measured.

## What is salvageable and in scope

An **OpenAI-compatible `/v1/completions` logprobs backend (vLLM) for the existing `decide_next_action`**, keeping it
advisory. The readout, pruning, labels and cascade guidance already exist; only the transport/response parser is new.
Open issue: a remote vLLM server cannot pass the loopback pid/binary verifier, so it needs an explicit security-model
decision (e.g. opt-in remote endpoint with HTTPS + bearer token, or SSH local-forward to loopback).

## Unresolved questions

- Direction choice (asked at the gate): reject / advisory vLLM backend / override the locked decision.
- If remote backend: acceptable trust model for a non-loopback endpoint.
- Does a real vLLM server with the named model exist for end-to-end verification, or is it fixture-only?

## Addendum — live jev backend on vm100, read-only inspection 2026-09-28

- A vLLM 0.28 container serving the jev model on a self-hosted GPU server. Published on the host's **loopback only**,
  bearer-key required (value not recorded here). Deployment details (hardware, container layout, owning repo) are
  omitted from this public record.
- Contract (`benchmark/jev/jev_client.py`): `/v1/completions`, `max_tokens` 1, `allowed_token_ids` restricted to the
  item's letters, `--logprobs-mode processed_logprobs` so returned logprobs are already renormalised over the allowed
  set, `--max-logprobs 64`. Letter token ids and response keys resolved once via `/tokenize` (`return_token_strs`),
  failing closed if a letter is not a single token. Letters A-Z, cap 26 candidates. Single head: one letter per call.
- Consequences for the client design:
  1. Reachable from the Mac only through an SSH local-forward, so the endpoint the Mac sees is `http://127.0.0.1:<port>`,
     not HTTPS. The earlier "HTTPS + bearer" choice cannot reach it without adding TLS on vm100.
  2. No GBNF grammar: the two-head (operation + target) readout needs two single-token calls, or a single target call
     with the operation derived from the row's role.
  3. Pages must be <= 26 candidates (the shipped builder uses up to 52 labels per page).
