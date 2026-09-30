# Auto-decisions — notarize, translate, publish, decision model

Run mode: --auto --counsel. Every entry lists What / Why / Risk / Alternatives rejected / Reversibility.

## Outcome Contract (ak-goal-warmup, auto-locked from task text)
- Outcome: (A) the Open Computer Use.app bundle is notarized and stapled whenever notary credentials
  exist, for local builds and in CI; (B) no tracked evergreen or record doc is left in Chinese,
  except the deliberate README.zh-CN.md; (C) the `@vietairs/*` npm packages are published with a
  notarized app; (D) `decide_next_action` exists as a read-only, opt-in MCP tool backed by a local
  llama-server readout, with P1/P2 gate measurements recorded honestly.
- Constraints: fork only (never iFurySt); the MCP server never owns a goal (no run_goal, no
  decide_and_act); no model weights in the npm package; real-app snapshots never committed.
- Non-goals: Linux/Windows parity for D; P4 bounded lease; retranslating README.zh-CN.md.

## D1 — "latest plan" resolves to the local-decision-model exec plan, not the completed release plan
- What: continue `docs/exec-plans/active/20260922-local-decision-model-mcp-tool.md` (P0 done, P1-P3 open).
- Why: plans/260923-0024-fork-release-ready is marked PIPELINE COMPLETE. The only open plan whose
  subject the user named ("semif and jevultrafast ... classifier") is this one.
- Risk: low. Alternatives rejected: re-open the release plan. Reversibility: n/a.

## D2 — user request overrides the open P0 stop-gate; P1/P2 gates are still measured and reported
- What: implement P1-P3 even though the P0 gate ("stop if compaction alone is enough") was never closed.
- Why: "i havent seen this implemented" is a direct request to build it. The P1/P2 gates stay
  load-bearing as measurements. The tool ships OFF by default behind an env flag, and the docs
  carry the measured numbers, so a failed gate is visible rather than hidden.
- Risk: medium. If AUROC < 0.7, the advisory output can mislead an agent that trusts it. Mitigation:
  the tool is opt-in and returns the full distribution and margin, and the cascade prompt tells
  hosts to escalate on low margin.
- Alternatives rejected: stop at P0 (contradicts the request); make the tool default-on
  (contradicts the locked gate decision).
- Reversibility: high (env flag, additive tool).

## D3 — the sidecar is user-started, not spawned by the TCC-privileged server
- What: `scripts/decision-model/` fetches pinned weights (explicit, SHA-256 checked) and starts
  llama-server on a deterministic loopback port. The Swift tool only connects to a loopback URL.
- Why: keeps the server stateless (KISS) and avoids process lifecycle inside the process that
  holds the Accessibility grant. This satisfies "no runtime auto-download by default".
- Risk: low. Alternatives rejected: server-spawned sidecar (more lifecycle, more attack surface
  in the privileged process). Reversibility: high.

## D4 — the P1 eval set commits only fixture-app items; real-app captures stay local
- What: real-app snapshots (Finder, etc.) go to a gitignored path. Only fixture-app-derived items
  and aggregate metrics are committed.
- Why: a live Finder capture in the evidence pass contained a third party's name and personal file names.
- Risk: low. Reversibility: n/a.

## D5 — notarization credentials: none present; do not use unrelated .p8 keys
- What: implement notarization keyed on `OPEN_COMPUTER_USE_NOTARY_PROFILE` (keychain profile) or
  the existing `APPLE_NOTARY_*` API-key env vars. Do not use the two AuthKey_*.p8 files found on
  disk; one belongs to an APNs relay, and their purpose and issuer IDs are unknown.
- Why: a credential cannot be inferred. The user must run `xcrun notarytool store-credentials` once.
- Risk: blocks the notarized publish (C) until the user acts. Reversibility: n/a.

## D6 — docs translation scope = tracked .md files only
- What: translate 255 tracked .md files (incl. AGENTS.md, CLAUDE.md, docs/histories/**). Exclude
  README.zh-CN.md (deliberate translation) and plans/**. Script echo strings are code and stay out of scope.
- Why: "chinese docs" names docs. Histories are included because "remaining" means all, and an
  earlier memory said not to retranslate them *unless asked*; this is the ask.
- Risk: every translated file upstream later edits will conflict on the next upstream sync. Accepted:
  the user owns an English-only fork, and upstream syncs already carry manual merges.
- Reversibility: high (a single docs PR).

## D7 — plan-validation gate (decision model), auto-adjudicated after kongming counsel
- Counsel: reports/kongming-plan-validation-decision-model.md (Assumptions block inside). It found no break of the locked constraint.
- What: accept the plan with every kongming amendment:
  - Q1: accept K4 (one /completion call, two sequential heads), with hybrid Qwen3.5-4B primary. Document `target_distribution` as P(target | chosen op), and correct the stated rationale.
  - Q2: ship with P3 unmeasured.
  - Q3: label p50 as an optimistic bound and record prompt_n/prompt_ms.
  - Q4: defer ARCHITECTURE/SECURITY to a follow-up if needed.
  - Q5: the live Dev.app check is a handover step.
  - Security: scrub `<[^<>\s]{1,40}>` special tokens; accept only literal 127.0.0.1 / [::1] (drop `localhost`); state the lock-hold bound as ~17 s.
  - Privacy: add username / ComputerName / LocalHostName greps; exclude the System Settings About, Sharing, Wi-Fi, Bluetooth and Network panes.
  - YAGNI: cut K11 stage-2 paging (defaultMaxPages = 1), drop the `wait` quota, use a small file for the corrupt-hash test.
- Controller amendment to the riskiest item (phase 03 unattended capture): capture uses only read-only get_app_state, on apps that are ALREADY running. No launching, clicking or typing. It runs inside a subagent (workflow agents can load the open-computer-use MCP tools), not the main loop, and writes only to the gitignored artifacts/decision-eval/.
- Why: every amendment narrows scope or closes a verified gap. None widens the trust boundary.
- Risk: medium (pruning may drop targets; reported via gate metrics). Reversibility: high.
- Revision (10:35): the blanket "no clicking" rule for phase 03 would leave too few distinct screens for 180 real items. It is replaced by an explicit allow-list of non-destructive navigation: the synthetic scratch folder in Finder; System Settings sidebar only, with no toggles; an unsaved TextEdit doc with sheets dismissed. Save, send, delete, sign-in and other apps stay forbidden. A human is present at the machine. Reversibility: high (no state changes beyond a scratch folder and an unsaved document).

## D8 — secure timestamp only on Developer ID signatures
- What: `codesign --timestamp` is added only when the identity is "Developer ID Application:". The implementer had added it to every identity-mode signature.
- Why: only Developer ID bundles are notarized. Timestamping an Apple Development signature needs network access to Apple's timestamp server, which would newly break offline local builds for no gain.
- Risk: low. Re-verified with a real Developer ID build: `flags=0x10000(runtime)` plus a secure Timestamp. Reversibility: high (one conditional).
