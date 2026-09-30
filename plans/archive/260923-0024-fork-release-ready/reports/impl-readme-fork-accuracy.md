# README fork-accuracy fixes

Worktree: `.claude/worktrees/fork-release-ready` (branch `chore/fork-release-ready`). Not committed — working tree only.

Pre-edit verification: fetched `https://github.com/vietairs/open-codex-computer-use` (200 OK, fork exists). Checked service fork-equivalents before deciding badge fate:
- DeepWiki `deepwiki.com/vietairs/open-codex-computer-use` → page body contains literal "404" (not indexed for the fork) → **badge removed**, not repointed.
- LLMAPIS `llmapis.com/api/badge/vietairs/...` → 200, valid PNG, differs from iFurySt's badge → kept, repointed.
- star-history `api.star-history.com/chart?repos=vietairs/...` → 200, valid SVG chart (renders empty history, not an error) → kept, repointed.

## README.md

| Line (pre-edit) | Before | After |
|---|---|---|
| 5 | `img.shields.io/github/v/release/iFurySt/...` badge + link to `iFurySt/.../releases` | → `vietairs/...` (both badge src and link) |
| 6 | `[![Ask DeepWiki](...)](https://deepwiki.com/iFurySt/open-codex-computer-use)` | **removed** — fork not indexed on DeepWiki (verified 404 body) |
| 7 | LLMAPIS badge source+link `iFurySt/...` | → `vietairs/...` |
| 3-7 area | (none) | added `> [!NOTE]` fork-identification line: "This is a fork of iFurySt/open-codex-computer-use, maintained at vietairs/open-codex-computer-use..." |
| 51 | `npm i -g open-computer-use` | → `npm i -g @vietairs/open-computer-use` |
| 93 | `npx skills add iFurySt/open-codex-computer-use -g -a codex ...` | → `npx skills add vietairs/open-codex-computer-use -g -a codex ...` |
| 100 | `npx skills add iFurySt/open-codex-computer-use -g -a claude-code ...` | → `npx skills add vietairs/open-codex-computer-use -g -a claude-code ...` |
| 169 | Cursor Motion releases link `iFurySt/.../releases` | → `vietairs/.../releases` |
| 175, 177, 178, 179 | Star History: anchor href, dark srcset, light srcset, img src — all `iFurySt%2F...` / `ifuryst/...` | → `vietairs%2F...` / `vietairs/...` |

Unchanged (per instruction, upstream's own projects): harness template link + blog link (`:18`), Browser Use pointer to `iFurySt/open-codex-browser-use` (`:10`, inside new fork-note block context but the TIP block itself untouched).

## README.zh-CN.md

Mirrored the same set of changes (badges, fork note in Chinese, npm install command, both skill-install commands, Cursor Motion link, Star History triple-URL block), translated the new fork-identification note into Chinese: "本仓库 fork 自 iFurySt/open-codex-computer-use，当前维护于 vietairs/open-codex-computer-use。原始项目请见上游仓库。" File stayed fully Chinese; no English conversion.

## Verification

- `grep -c $'\r' README.md` → 0
- `grep -c $'\r' README.zh-CN.md` → 0
- Remaining `iFurySt`/`ifuryst` hits in README.md after edit are only the 3 explicitly-preserved references (fork-note upstream credit, harness template, blog, Browser Use pointer).

## Unresolved questions

- None. `@vietairs/open-computer-use` scope name was taken as given from the task brief (owned by the npm-rescope agent); this worktree's root `package.json` (`open-computer-use-repo-tools`) is unrelated tooling and was not touched.

Status: DONE
Summary: Repointed all fork-owned badges/links/install commands in both READMEs from iFurySt to vietairs, removed the dead DeepWiki badge (verified 404), added a short fork-identification note in each file, verified no CRLF.
