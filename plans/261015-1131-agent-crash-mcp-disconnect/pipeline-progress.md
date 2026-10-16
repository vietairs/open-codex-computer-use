# Progress — agent crash / MCP disconnect + release 0.3.11-vietairs.1

Request: analyse why open-computer-use MCP keeps disconnecting; fix; then (user) merge on green CI, cut a new release, update this Mac; also scout upstream iFurySt releases for features worth adopting (haiku fan-out).

Done:
- Root cause: NaN/inf AX frame -> Int(Double) trap in shared agent -> every MCP proxy exits. Report in chat; fix = PR #29 merged (b0762ca): renderedInt, proxy survives agent loss, sticky menu Quit, SO_NOSIGPIPE, lock opt-in off on relaunch.
- Release PR #30 (release/0.3.11-vietairs.1): version bump + notes. CI: 4/5 pass, swift pending at last check.
- Local notarized build DONE (Accepted, stapled, spctl Notarized Developer ID). Tarballs: <scratchpad>/npm-0311 (scratchpad = /private/tmp/claude-501/-Users-hvnguyen-Projects-open-codex-computer-use/7c881d6e-e25c-464c-8829-88c61a16b76e/scratchpad). Publish script: <scratchpad>/publish-0311.sh (user must run in real Terminal, npm passkey).
- Upstream scout workflow wf_df950dee-533 (6 haiku scouts) running; upstream is v1.1.0 (fork last synced v0.3.5).

Status (updated 2026-10-16):
1. DONE — PR #30 merged 2026-10-15 01:29Z.
2. DONE — 0.3.11-vietairs.1 published; superseded. Current release is 0.3.12-vietairs.2 (PR #43, tag `v0.3.12-vietairs.2` on e6140b9, GitHub release 2026-10-16 00:51Z, npm `@vietairs/*` latest = 0.3.12-vietairs.2).
3. DONE — tag v0.3.11-vietairs.1 pushed at f61ebb8; 0.3.12-vietairs.2 tag pushed later.
4. Mac: `npm i -g @vietairs/open-computer-use@0.3.12-vietairs.2` done 2026-10-16; `doctor` shows permissions granted. Running agent (pid 85797, started 11:51 local) predates or postdates the install, not verified; restart needs user OK because it serves other sessions.
5. DONE — worktree `agent-crash-nonfinite-frame` torn down earlier; `release-0-3-12-2` torn down 2026-10-16 (archive at `.claude/worktrees/.archive/`).
6. OPEN — upstream scout verdicts were not recorded in this file; which ports were chosen is unknown here.
7. OPEN — follow-ups not in #29: concurrent-relaunch flock, dev/release eviction fight, proxyMCP e2e test, NaN source app unidentified. Also listed in `plans/reports/checkpoint-261016-sky-key-port-plan.md`.

Resume prompt: In /Users/hvnguyen/Projects/open-codex-computer-use read plans/261015-1131-agent-crash-mcp-disconnect/pipeline-progress.md and continue from item 6/7 above.
