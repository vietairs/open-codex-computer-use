# impl-governance report

Worktree: `.claude/worktrees/fork-release-ready` (branch `chore/fork-release-ready`). No commits made.

## A. CODEOWNERS
`CODEOWNERS:1-3` before:
```
# 基于这个模板创建新项目后，请替换成真实的代码所有者。

* @example-org/example-team
```
after:
```
* @vietairs
```
Dropped the template comment (task said "no invented teams", so kept it minimal: single owner, no sub-paths).

## B. SECURITY.md (repo root)
Fully rewritten in English. Confirmed I was editing the root file (`SECURITY.md`), not `docs/SECURITY.md` (checked both exist, left `docs/SECURITY.md` untouched — out of scope per instructions).
Content now states:
- Supported version: `0.3.6-vietairs.1` on fork `main`.
- Reporting: GitHub private vulnerability reporting URL `https://github.com/vietairs/open-codex-computer-use/security/advisories/new` (verified against `git remote -v` — `origin` = `vietairs/open-codex-computer-use`), plus fallback to maintainer profile `@vietairs`.
- No email address invented — none was available to verify, so none was written.
- Notes that some code is inherited from upstream and points reporters to `iFurySt/open-codex-computer-use` for upstream-origin issues.

## C. docs/releases/RELEASE_GUIDE.md
Grepped for all `iFurySt` occurrences — only 2, both maintainer-facing `gh` commands, no other references needed changing.
`docs/releases/RELEASE_GUIDE.md:152-153` before:
```
gh run list -R iFurySt/open-codex-computer-use --limit 10
gh run view -R iFurySt/open-codex-computer-use <run-id> --log-failed
```
after:
```
gh run list -R vietairs/open-codex-computer-use --limit 10
gh run view -R vietairs/open-codex-computer-use <run-id> --log-failed
```
Surrounding Chinese prose left unchanged.

## D. .gitignore
`.gitignore` before had no rule matching `plugins/**/*.app` or `.claude/worktrees/`.
Added two lines:
```
plugins/**/*.app/
```
(placed after `dist/`, covers the `.app` bundle under `plugins/open-computer-use/`)
```
# Agent-managed git worktrees
.claude/worktrees/
```
The task brief said "the existing diff already adds `.claude/worktrees/` — keep that", but this worktree's `.gitignore` (matching `HEAD` and current working tree) had no such line — confirmed via `git diff .gitignore` and `git show HEAD:.gitignore`. Added it myself since `.gitignore` is my file and the line is clearly wanted; did not touch any other agent's files to reconcile the discrepancy.

**Untracked residue found in main checkout (`/Users/hvnguyen/Projects/open-codex-computer-use`, NOT this worktree) — NOT deleted, reporting only:**
- `plugins/open-computer-use/Open Computer Use (Dev).app/` — built app bundle, now ignored by the new `.app/` rule.
- `plugins/open-computer-use/mcp/`, `mcp_servers/`, `mcpServers/` — three duplicate dirs, each holding `mcpServers.json`, `open-computer-use.json`, empty `test.txt`. Not build output in the conventional sense (JSON config, not a compiled artifact) — did NOT add an ignore rule for these since deleting/ignoring config-shaped duplicates without the user's judgment risked silently hiding user experiment files rather than just build noise. Left for the user to decide (delete duplicates, or fold into the tracked layout).
- `plugins/open-computer-use/plugin.json` (symlink) → `.codex-plugin/plugin.json` — shadows the tracked file; another agent's file (owns `plugin.json`), out of my scope, not ignored or touched.

## Hygiene check
```
./scripts/check-repo-hygiene.sh; echo "exit=$?"
```
Output: 8 "缺少必要文件" (missing required file) errors, all under `.github/` (dependency-review-config.yml, ISSUE_TEMPLATE/*, workflows/*). `exit=1`. These are outside my ownership (`.github/` belongs to another agent) — not caused by my four files.

## Refused to invent
- No security-contact email address (none verifiable from repo/remotes).
- No CODEOWNERS sub-path or team entries beyond `@vietairs`.

## Unresolved questions
- Should the `mcp/`, `mcp_servers/`, `mcpServers/` duplicate dirs in the main checkout be consolidated/deleted, or are they intentional local experiments to keep? (left untouched per instructions — user's call)
- The `.claude/worktrees/` gitignore line the brief referenced as "already added" was not actually present anywhere I could find in this worktree — added it now under D; flagging in case another agent's copy conflicts on merge.

Status: DONE
Summary: Filled CODEOWNERS/SECURITY.md/RELEASE_GUIDE.md repo-slug fixes and added build-output + worktree ignore rules; reported (not deleted) untracked residue in the main checkout; hygiene script only fails on another agent's `.github/` files.
