# Pipeline — sync fork to upstream v0.3.5, release, redeploy

Task: Merge upstream iFurySt v0.3.5 into the vietairs fork preserving all fork
developments, cut a fork release, and restart Open Computer Use on this Mac.

Task source: free text (`/hvn:cortex ... --auto --counsel`)

Started: 2026-09-21 23:35 (Australia/Melbourne)

## Route card

Complexity: moderate -> hard. Upstream v0.3.5 lands 3,627 insertions across 77
files; five of those files were also modified by the fork, including the
security-sensitive `ComputerUseService.swift` and a 750-line fork test delta.

Risk: medium-high — the conflict surface includes auth and lock-security code.
Familiarity: high (a prior v0.2.1 sync run is archived under `plans/archive/`).
Scope: multi-phase. Payoff: high — this MCP runs on the user's Mac daily.

Change set (fork ∩ upstream): `AccessibilitySnapshot.swift`,
`ComputerUseService.swift`, `ComputerUseToolDispatcher.swift`,
`InputSimulation.swift`, `OpenComputerUseKitTests.swift`.

Merge: authorized — fork only, never upstream iFurySt.

## Stages

1. Worktree `.claude/worktrees/sync-upstream-v0.3.5`, branch
   `worktree-sync-upstream-v0.3.5`
2. Merge `v0.3.5`, resolve conflicts preserving fork work
3. Build + full test + repo CI
4. Version bump to `0.3.6-vietairs.1`, release notes, history record
5. PR to vietairs fork
6. Pre-merge review fan-out (correctness, security) + fixes
7. Merge, tag, push release
8. Rebuild app, redeploy over the plugins copy, restart MCP runtime
9. Teardown: sync base, remove worktree, archive plan dir

## Decisions that must not be re-litigated

- Fork release version is `0.3.6-vietairs.1`, not `0.3.5`. The fork is upstream
  0.3.5 plus fork-only work, so reusing the upstream tag name would collide with
  the already-fetched upstream tag. The prerelease segment sorts above 0.3.5 and
  below a future upstream 0.3.6, and can never collide with an upstream tag.
- Both conflicts resolved by keeping both sides; see the history record at
  `docs/histories/2026-09/20260921-2335-sync-upstream-v0-3-5-and-release.md`.
- `check-repo-hygiene.sh` failures are pre-existing on `main` and out of scope.
