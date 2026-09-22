## [2026-09-23 00:24] | Task: Make the vietairs fork release-ready

### 🤖 Execution Context
* **Agent ID**: `hvn:cortex` (main loop) + 3 scout / 4 implementer subagents
* **Base Model**: `claude-opus-5` controller, `claude-sonnet-5` delegates
* **Runtime**: Claude Code, macOS, worktree `.claude/worktrees/fork-release-ready`

### 📥 User Query
> continue to make this use-ready --auto --counsel

"this" named no target, so the run asked once and the user chose: make the FORK
release-ready — as opposed to fixing the local plugin install or closing out
stale pipeline tails.

### 🛠 Changes Overview
**Scope:** repo root governance, `.github/`, `README` (EN+ZH), `scripts/npm/`, plugin manifest.

**Key Actions:**
- **npm identity**: the fork built three npm packages under names upstream owns
  (`open-computer-use`, `-mcp`, `open-codex-computer-use-mcp`), so it could never
  publish any of them. Rescoped to `@vietairs/…`, added a `packageDirName()`
  flattener because a scoped name contains `/` and `path.join` would otherwise
  nest the staging dir, and replaced hardcoded upstream URLs in generated package
  metadata with a `resolveRepositoryURL()` derived from `git remote` — the same
  pattern `validate-github-release-notes.mjs` already used.
- **README accuracy**: Quick Start told fork users to `npm i -g open-computer-use`,
  which installs upstream's package (registry-verified at 0.3.5 while this fork is
  0.3.6-vietairs.1). Repointed that plus every badge, skill-install command,
  releases link and Star History URL. Removed the DeepWiki badge because the fork page,
  while it returns 200, is an empty 31KB shell against upstream's 545KB — it has
  not been indexed. Kept LLMAPIS and the release badge after confirming both
  return 200.
- **Repo hygiene**: added the 11 files `check-repo-hygiene.sh` requires, which is
  why `scripts/ci.sh` exited 1. Written as real content, not presence-satisfying
  stubs — four workflows, three issue forms, PR template, editorconfig,
  markdownlint config.
- **Governance**: `CODEOWNERS` was still `@example-org/example-team` and
  `SECURITY.md` still self-described as a placeholder. Both filled for this fork.

### 🧠 Design Intent (Why)
A fork is only "release-ready" if someone who finds it can install it, report a
vulnerability to someone real, and see CI that actually checks the deliverable.
All three were broken: the install command pointed at a different project, the
security contact was template text, and the repo's own `make ci` failed.

Two deliberate non-changes. The `com.ifuryst.*` bundle identifiers stay, because
renaming them invalidates the macOS TCC grants and forces the user to re-approve
Accessibility and Screen Recording. Author attribution to Leo stays in
`plugin.json`; only the repository/homepage URLs move to the fork.

The added `swift build` / `swift test` steps in `ci.yml` are the substantive part.
`scripts/ci.sh` covers shell, Node, Go and docs — it has no swift step at all, so
running it alone would have produced a green CI that said nothing about the Swift
binary this project ships.

### 📁 Files Modified
- `.github/workflows/ci.yml` (new), `docs-check.yml` (new), `repo-hygiene.yml` (new), `supply-chain-security.yml` (new)
- `.github/ISSUE_TEMPLATE/{bug_report,feature_request,config}.yml` (new), `.github/PULL_REQUEST_TEMPLATE.md` (new), `.github/dependency-review-config.yml` (new)
- `.editorconfig` (new), `.markdownlint.json` (new)
- `scripts/npm/build-packages.mjs`, `plugins/open-computer-use/.codex-plugin/plugin.json`
- `README.md`, `README.zh-CN.md`, `SECURITY.md`, `CODEOWNERS`, `.gitignore`
- `docs/releases/RELEASE_GUIDE.md`
- `docs/histories/2026-09/20260923-0024-fork-release-readiness.md` (this note)

### ⚠️ Known Gaps
- `@vietairs/open-computer-use` is **not published yet** (registry returns 404),
  so both READMEs carry an explicit build-from-source caveat above the install
  command rather than advertising a command that fails today. Ownership of the
  `@vietairs` scope is also **unverified** — no authenticated registry access —
  so `npm publish` could still fail with 403 at release time, after build and
  pack have already succeeded.
- GitHub private vulnerability reporting was **disabled** on the fork, which made
  the advisory URL in `SECURITY.md` unusable by outside reporters. Enabled during
  this run and verified `{"enabled":true}`.
- `supply-chain-security.yml` uses plain-shell `npm audit` / `govulncheck` instead
  of `dependency-review-action`, because no verified SHA pin was available for it
  and `check-action-pinning.sh` rejects unpinned actions. The npm half no-ops
  honestly (no lockfile, no declared dependencies). The Go half took two
  revisions to actually cover the repository. It first scanned only `apps/` and
  missed `scripts/computer-use-cli`, the one module with third-party
  requirements. The fix for that enumerated all three modules but scanned only
  modules declaring `require` -- which skipped `apps/OpenComputerUseLinux` and
  `apps/OpenComputerUseWindows`, whose binaries are exactly what ships inside the
  npm tarballs. A module with no dependencies still links the standard library,
  and the standard library was where the real exposure sat. It now scans every
  enumerated module unconditionally and fails loudly if enumeration returns
  nothing.
- **Go toolchain pin raised, 1.22.x to 1.27.x**, in `ci.yml`, `release.yml` and
  `supply-chain-security.yml` together. Scanned under the 1.22.x that
  `release.yml` used, the two shipped runtimes reported three call-reachable
  stdlib advisories -- GO-2025-3956 (`os/exec.LookPath`), GO-2025-3750
  (`syscall`, Windows), GO-2026-4602. Under 1.27.x all three modules report no
  vulnerabilities, and both modules build unchanged; their `go` directives still
  read 1.22, so the language version is untouched. The three pins are kept equal
  deliberately: govulncheck reports the stdlib of the toolchain it runs under, so
  a scanner ahead of the builder returns a clean result for binaries that ship
  vulnerable. The patch component must float -- `go1.26.0` exactly, which
  `GOTOOLCHAIN=auto` resolves to from the CLI module's go directive, reports nine
  advisories that later 1.26 patches already fix.
- `scripts/ci.sh` could not be run end-to-end locally: its `python3 -m unittest`
  step is SIGKILLed in this agent environment. The constituent check scripts were
  run directly instead, and all pass.
- The 12 inherited Chinese `docs/*.md` process docs were left untranslated. They
  contain no wrong-repo claims; translating them is separate work.
