# Auto-decisions — jev remote decision backend (--auto --counsel)

## 1. Remote destination read from a 0600 user file, not per-call env
- What: URL/model/key live in ~/Library/Application Support/OpenComputerUse/decision-model/remote-backend.json; per-call env only selects backend=remote.
- Why: app-agent socket applies per-call env from any same-uid peer; a per-call URL would let an unprivileged process exfiltrate any app's AX rows via the TCC-privileged agent.
- Risk: medium — adds a config file the user must create; still HTTPS + bearer as the user chose.
- Alternatives rejected: per-call env URL/key (exfil primitive); env in trusted launch env only (shared agent, first launcher wins).
- Reversibility: high.

## 2. No live end-to-end test
- What: verification uses fixture responses matching vLLM 0.28 jev shape; the vm100 engine is loopback-only http, no TLS front.
- Why: user chose HTTPS-only and not to touch vm100.
- Risk: medium — wire mismatches surface only at first live use.
- Reversibility: n/a.

## 3. No auto-merge
- Risk axis is medium (network egress of screen text, credential handling), so --auto stops at a merge-ready PR.
