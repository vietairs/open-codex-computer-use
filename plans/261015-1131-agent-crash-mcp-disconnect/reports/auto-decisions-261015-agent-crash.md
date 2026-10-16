# Auto decisions — agent crash / MCP disconnect (2026-10-15)

- Route-card confirm skipped under `--auto`.
- Worktree creation ran outside the sandbox (the sandbox blocks it).
- Implementers: sonnet/high. Reviewers: opus/xhigh (two independent passes, 3 high + several medium issues fixed).
- Merges (#29, #30) done only after a user-approved review and green CI (5/5).
- Publish: `npm publish` needs a real Terminal (passkey 2FA) and `--tag latest` for a prerelease version; the user ran it.
- Tag `v0.3.11-vietairs.1` pushed at f61ebb8 only after all three npm packages were visible.
- Worktrees torn down with worktree-gc (no `--force`) after deleting regenerable build output in them; remote branches kept.
- Upstream scouting: 6 haiku scouts; user chose which ports to do (see pipeline-progress.md).

## Open items (status 2026-10-16)
- Old agent PID 5115 (pre-fix code): no longer running as of 2026-10-16 (not in `ps`). Current agent is pid 85797, started 11:51 local; its version is not verified against 0.3.12-vietairs.2. Restarting it needs user OK because it serves other sessions.
- NaN-source app/element still unidentified.
- Later releases: 0.3.12-vietairs.1 and 0.3.12-vietairs.2 (tag at e6140b9, npm and GitHub release live). Mac installed 0.3.12-vietairs.2 via npm global.
