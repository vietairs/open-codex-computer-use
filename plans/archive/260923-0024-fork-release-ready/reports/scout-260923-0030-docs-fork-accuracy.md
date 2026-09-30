# Docs fork-accuracy audit — 2026-09-23

Scope: user-facing docs vs. fork release-readiness (vietairs/open-codex-computer-use, release `0.3.6-vietairs.1`, upstream iFurySt/open-codex-computer-use, npm latest `0.3.5`). Read-only.

## 1. README.md / README.zh-CN.md

**CRITICAL — Quick Start installs UPSTREAM's package, not the fork's.**
- `README.md:64` `npm i -g open-computer-use` (also `README.zh-CN.md` equivalent).
- Verified (read, not inferred): `scripts/npm/build-packages.mjs:23-27` defines `metaPackageNames = ["open-computer-use", "open-computer-use-mcp", "open-codex-computer-use-mcp"]` — these are the package names the fork's own build script *would* publish under.
- Verified against the live npm registry: `registry.npmjs.org/open-computer-use` → `"repository":{"url":"git+https://github.com/iFurySt/open-codex-computer-use.git"}`, `dist-tags.latest: 0.3.5`. The published `open-computer-use` package on npm today is owned by upstream and is one release behind the fork (0.3.5 vs. fork's 0.3.6-vietairs.1). Unless the fork has separately claimed/published under this same name (not verified from repo state — a publish is a registry-side fact, not a repo file), a fork consumer following `README.md:64` gets iFurySt's build, not vietairs'.
- Same-name collision affects every command in the "More" section that assumes the fork's binary, e.g. `README.md:126-136` (`make smoke`, `run-agent-smoke-tests.mjs`, etc.) — these work from a source checkout regardless, but the top-of-file quick start does not.

**Badges/links still pointing at iFurySt where a fork consumer needs vietairs:**
- `README.md:5` — `[![Release](https://img.shields.io/github/v/release/iFurySt/open-codex-computer-use)]` — shows upstream's release, not the fork's `0.3.6-vietairs.1`.
- `README.md:6` — DeepWiki badge → `https://deepwiki.com/iFurySt/open-codex-computer-use`.
- `README.md:7` — LLMAPIS badge → `iFurySt/open-codex-computer-use`.
- `README.md:93` — `npx skills add iFurySt/open-codex-computer-use -g -a codex --skill open-computer-use -y` — installs the skill from upstream's repo.
- `README.md:100` — same, `-a claude-code`.
- `README.md:169` — Cursor Motion → `https://github.com/iFurySt/open-codex-computer-use/releases` (upstream releases page — fork's Cursor Motion binary, if any, would be under vietairs' Releases).
- `README.md:175-181` — Star History chart, all three URLs → `iFurySt%2Fopen-codex-computer-use` / `ifuryst/open-codex-computer-use`.
- Identical set of lines in `README.zh-CN.md` (5, 6, 7, 85, 91, 145, 151) — same fixes needed, mirrored.
- Not flagged: `README.md:18` / zh line 18, the "harness template" and author blog links — these are genuinely the original author's personal project/blog, correctly upstream, not a fork-accuracy defect.
- Not flagged: `README.md:10` / zh line 10 — "Interested in Browser Use? … open-browser-use" pointing at `iFurySt/open-codex-browser-use` — a different sibling project by the same upstream author, correctly upstream.

## 2. `docs/` top-level files

Checked every `docs/*.md` at top level (`ARCHITECTURE.md`, `CICD.md`, `DESIGN.md`, `FRONTEND.md`, `HISTORY_GUIDE.md`, `PLANS_GUIDE.md`, `PRODUCT_SENSE.md`, `QUALITY_SCORE.md`, `RELIABILITY.md`, `REPO_COLLAB_GUIDE.md`, `SECURITY.md`, `SUPPLY_CHAIN_SECURITY.md`) for `iFurySt`, `github.com/iFurySt`, `npm i -g`, `vietairs`: **zero matches** in any of them. These are generic template/process docs (harness-template heritage) with no repo-identity claims to be wrong — no defect found here.

- `docs/releases/RELEASE_GUIDE.md:152-153` — `gh run list -R iFurySt/open-codex-computer-use …` / `gh run view -R iFurySt/open-codex-computer-use …` — these are copy-paste CI-inspection command examples that target upstream's Actions runs, not the fork's. For a fork maintainer following this guide verbatim, wrong repo.
- `docs/releases/feature-release-notes.md:63-64` — two historical entries reference `npm i -g open-computer-use` as the install command from `0.1.35`/`0.1.36` (Chinese text, dated 2026-04-23). This is a **stateful history record** (per scope note below), not evergreen docs — reporting for completeness only, not as a defect.
- `docs/releases/feature-release-notes.md:7` — most recent entry (2026-09-21) correctly documents the fork's own `0.3.6-vietairs.1` release and its upstream-merge content; internally consistent, no issue.

`docs/changes/` does not exist in this repo; `docs/histories/` does (dated subfolders `2026-04` … `2026-09`, one dated file, one template). Per task scope these are stateful records, not evergreen authority — not audited line-by-line, reported as out-of-scope-for-errors per instruction.

## 3. `AGENTS.md`, `CONTRIBUTING.md`, `SECURITY.md`, `CODEOWNERS` (repo root)

All four are unmodified harness-template boilerplate — entirely in Chinese, and **none name any concrete repo, owner, or org** (right or wrong):
- `AGENTS.md:1-3` — generic template description, no repo/owner reference.
- `CONTRIBUTING.md` — generic process doc, no repo/owner reference.
- `SECURITY.md:11-13` (root) — explicitly says "this repo is just a base template; a project built from it should replace this with its own real security contact and response process" — i.e. it self-flags as a placeholder.
- `CODEOWNERS:1-2` — `* @example-org/example-team`, with a comment line telling the adopter to replace it — clearly still the unfilled template placeholder, not pointing at iFurySt or vietairs.

Verdict: not "wrong" in the sense of pointing at the wrong owner, but a **release-readiness gap** — `CODEOWNERS` and `SECURITY.md` were never filled in for either iFurySt or vietairs, so a fork consumer gets no real code-owner or security contact.

## 4. Chinese vs. English (user-facing docs)

Per user's standing preference (English-only for docs), the following **user-facing** docs are Chinese:
- Root: `AGENTS.md`, `CONTRIBUTING.md`, `SECURITY.md` — fully Chinese.
- All 12 top-level `docs/*.md` files — fully Chinese (non-ASCII line counts: `ARCHITECTURE.md` 128, `SECURITY.md` 49, `RELIABILITY.md` 42, `REPO_COLLAB_GUIDE.md` 34, `SUPPLY_CHAIN_SECURITY.md` 26, `CICD.md` 23, `HISTORY_GUIDE.md`/`PLANS_GUIDE.md` 17 each, `QUALITY_SCORE.md` 15, `DESIGN.md` 7, `PRODUCT_SENSE.md` 7, `FRONTEND.md` 8).
- `docs/releases/feature-release-notes.md` and `docs/releases/RELEASE_GUIDE.md` — Chinese (spot-checked, confirmed via the grepped lines above).
- `README.zh-CN.md` is a deliberate, explicitly-labeled translation (has its own English-toggle badge back to `README.md`) — **not treated as a defect**, per instruction.
- `README.md` itself is English and correct in that respect.

## Unresolved questions

1. Is `open-computer-use` on npm actually intended to stay upstream-owned (i.e., fork consumers are meant to install from source / a differently-named fork package), or should the fork publish its own package and point README at it? Repo state alone can't answer whether a fork-owned npm package already exists under another name — worth a registry check for `@vietairs/open-computer-use` or similar before deciding the fix.
2. Should `CODEOWNERS`/`SECURITY.md`/`AGENTS.md`/`CONTRIBUTING.md` be filled in with vietairs-specific ownership as part of "release-ready," or left as template scaffolding intentionally?
3. Should `docs/*.md` (process/architecture docs) be translated to English as part of this release push, or is Chinese acceptable there since they're internal-facing (contributor/agent docs) rather than consumer-facing like the README?

Status: DONE
Summary: README (EN+ZH) has upstream-owned badges/links/skill-install commands and — critically — `npm i -g open-computer-use` installs iFurySt's npm package (registry-verified, still at 0.3.5), not the fork's 0.3.6-vietairs.1; `docs/*.md` top-level are generic Chinese template docs with no wrong-owner claims but are release-readiness gaps (untranslated, unfilled CODEOWNERS/SECURITY); `docs/releases/RELEASE_GUIDE.md` has two upstream-targeted `gh` command examples.
