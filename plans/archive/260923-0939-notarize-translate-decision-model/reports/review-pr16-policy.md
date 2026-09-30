# PR #16 review — rules & policy lens

Branch `docs/translate-to-english` (c9814e9) vs `origin/main` (4ac1d5e). Read-only.

## Scope checked
12 steering files compared old-vs-new, line by line: AGENTS.md, CLAUDE.md, CONTRIBUTING.md, docs/HISTORY_GUIDE.md, docs/PLANS_GUIDE.md, docs/REPO_COLLAB_GUIDE.md, docs/QUALITY_SCORE.md, docs/design-docs/core-beliefs.md, docs/histories/template.md, docs/exec-plans/templates/execution-plan.md, docs/releases/README.md, docs/exec-plans/README.md.
Also ran `bash scripts/check-docs.sh` and `bash scripts/check-repo-hygiene.sh` (both exit 0) and grepped the scripts that read these docs.

## Verdict
Translation holds every rule. No rule is weakened, strengthened, dropped or added in the 12 files. One problem is blocking: the "deliberate policy change" the PR describes does not exist in the diff, and the PR's own history entry says it does.

## Blocking

### B1. The English-only doc policy is claimed but never written down
- `docs/histories/2026-09/20260923-1020-translate-docs-to-english.md` Key Actions says: "Switched the doc-language rules to English: where a guide or template told contributors to write histories, plans or notes in Chinese, it now says English."
- Evidence: `git grep -n -E '中文|英文|语言' origin/main -- '*.md'` finds no guide, template or README on main that tells anyone to write docs in Chinese. The only language rules on main are AGENTS.md:37-38 (reply mirroring), and they were translated faithfully. The Chinese convention was only implied by the language the templates and guides were written in.
- On HEAD, no file says docs, histories, plans or notes must be in English. `git grep -i 'english'` over the steering docs finds only AGENTS.md:37-38 and the GitHub-release-body rule in docs/releases/README.md, which was already there.
- Impact: (a) the durable history record makes a false claim about what the PR changed. (b) The maintainer's English-only decision has no text behind it. Nothing stops an agent following the reply-mirroring rule for a Chinese-speaking user from writing a history or plan in Chinese. The next upstream sync from iFurySt can also bring Chinese docs back without anyone noticing. `docs/releases/RELEASE_GUIDE.md`, which AGENTS.md calls a must-read, is still Chinese because it was deferred, so an agent can still see Chinese written in steering docs.
- Fix (pick one):
  1. Add the rule and keep the history claim. For example, add to AGENTS.md "Working rules" or REPO_COLLAB_GUIDE "Documentation Discipline": `- Write repository docs, histories, execution plans, and release notes in English. This does not change reply language, which still follows the user.` Put it next to the reply-mirroring bullets so the two rules cannot be confused.
  2. Or leave the rules untouched and correct the history bullet to "Translated all guides and templates; there was no explicit Chinese-language rule to switch, so the English convention is implied by the templates only."
  Option 1 matches the stated intent. Option 2 is the minimum needed for an accurate record.

## Nits

- N1. REPO_COLLAB_GUIDE "Development Principles" bullet 3: `同源更新` became "updated from the same source". In context it means "updated together, in the same change", which is the same idea as Documentation Discipline bullet 3. "From the same source" reads like a single-source-of-truth or codegen rule. Suggest "Update code, docs, tests, configuration, and release records together as much as possible."
- N2. `脱敏` is translated three ways: AGENTS.md "redact", HISTORY_GUIDE "desensitized", histories/template.md "redacted". The redaction rule itself is intact: HISTORY_GUIDE still bans sensitive info, local paths, secrets and raw log details. Use "redacted" everywhere, because "desensitized" is a calque and weakens the searchable term.
- N3. Rules the new English-only stance would cover are still in Chinese: `docs/releases/RELEASE_GUIDE.md` (deferred on purpose, as the history notes), plus user-facing script output in scripts/check-docs.sh, check-repo-hygiene.sh, new-history.sh, new-exec-plan.sh, init-project.sh and start-codex-mitm-dump.sh. Not a dependency break. Track it as follow-up so "English-only" is not only partly true.

## Verified unchanged (no finding)
- Reply-mirroring rule: AGENTS.md:37-38 keeps both bullets, "follow the user's language; switch when they switch" and "English input -> English reply".
- Push rule: "sync with the latest remote before `git push`" is kept in both AGENTS.md and REPO_COLLAB_GUIDE. Commit rules (scoped, accurate) are unchanged. No push or commit rule was added.
- Must-strength: every `必须`, `一律` and `就要` still maps to "must" (releases README "Every public release must…", REPO_COLLAB "must always use relative paths", "must be updated in the same change"). No MUST became a should. The `应该`/`尽量` wording stays soft.
- History template: all fields are present (Agent ID, Base Model, Runtime, User Query, Scope, Key Actions ×2, Design Intent, Files Modified). The header format `## [YYYY-MM-DD HH:mm] | Task:` is unchanged.
- Execution-plan template: all 9 sections are present (Goal, Scope in/out, Background ×3, Risks ×2, Milestones ×3, Verification ×3, Progress Log, Decision Log).
- Naming and paths: `docs/histories/YYYY-MM/`, `YYYYMMDD-HHmm-task-slug.md`, `docs/exec-plans/{active,completed,templates}`, `tech-debt-tracker.md` are all unchanged.
- CLAUDE.md: same directive, read AGENTS.md first.

## Script dependencies
- `scripts/new-history.sh` and `scripts/new-exec-plan.sh` copy the templates byte-for-byte (`cp`). They do not parse headings or depend on any string.
- `scripts/validate-github-release-notes.mjs` reads only `docs/releases/github/<tag>.md` and requires `## What's Changed` and no CJK. The PR does not touch `docs/releases/github/`.
- `.github/workflows/release.yml:261` reads only `docs/releases/github/${RELEASE_TAG}.md`.
- `check-repo-hygiene.sh:42` greps `make check-docs` in CONTRIBUTING.md, which is still present. `check-docs.sh:50` greps `docs/` in AGENTS.md, which is still present. Both scripts pass.
- The Swift tests contain CJK only as unicode input fixtures and read no docs.

## Unresolved questions
- Does the maintainer want the English-only rule written as an explicit AGENTS.md rule (B1 option 1), or left implied by the templates (option 2)?
