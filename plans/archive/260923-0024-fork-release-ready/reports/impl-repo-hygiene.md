# Repo hygiene files — implementation report

Worktree: `.claude/worktrees/fork-release-ready` (branch `chore/fork-release-ready`). No commits made; all changes left in working tree.

## Files created

- `.editorconfig` — root=true, base 2-space/lf/utf-8; overrides: Swift 4-space (matches `Package.swift`), Go tabs (matches gofmt output in `apps/*/main.go`), Python 4-space, Makefile tabs, Markdown keeps trailing whitespace (hard line breaks used in repo).
- `.markdownlint.json` — `default: true` with MD013 (line-length), MD033 (inline HTML), MD034 (bare URLs), MD041 (first-line heading) disabled — repo's Chinese docs and README use inline `<img>`/`<a>` badges, bare GitHub asset URLs, and long CJK lines that would otherwise fail. MD024 set to `siblings_only`.
- `.github/PULL_REQUEST_TEMPLATE.md` — summary, type of change, checklist (`make check-docs`, `make ci`, docs/history/release-note updates), risk/rollback, related-links section.
- `.github/dependency-review-config.yml` — written in `actions/dependency-review-action`'s config schema (fail-on-severity: high, license allowlist) even though no workflow calls that action yet (see below); documented in-file why, so it drops in cleanly if a pinned reference is added later.
- `.github/ISSUE_TEMPLATE/bug_report.yml` — typed issue form (description, expected behavior, repro steps, version, platform dropdown, logs, context).
- `.github/ISSUE_TEMPLATE/feature_request.yml` — typed issue form (problem, proposal, alternatives, context), nudges toward `docs/exec-plans/active/` for larger asks.
- `.github/ISSUE_TEMPLATE/config.yml` — chooser config (`blank_issues_enabled: false`, discussions + security-advisory contact links), correctly using the chooser schema, not the form schema. Links verified against `SECURITY.md` and `git remote -v` (`vietairs/open-codex-computer-use`).
- `.github/workflows/ci.yml` — `pull_request` + push-to-`main`, single `macos-26` job (matches `release.yml`'s toolchain), sets up Node 24 + Go 1.22.x, then runs `./scripts/ci.sh` directly (the same script `make ci` runs). Chose to call `ci.sh` wholesale rather than reimplement `swift build`/`swift test`/`go test`/`python3 -m unittest` steps: it's the single source of truth so a local `make ci` run matches CI exactly. Trade-off documented in-file: this re-runs `check-docs.sh`/`check-repo-hygiene.sh`/`check-action-pinning.sh`, duplicating `docs-check.yml`/`repo-hygiene.yml` — accepted deliberately for consistency over saving a few seconds of CI time.
- `.github/workflows/docs-check.yml` — `ubuntu-24.04`, runs `./scripts/check-docs.sh`.
- `.github/workflows/repo-hygiene.yml` — `ubuntu-24.04`, runs `./scripts/check-repo-hygiene.sh` then `./scripts/check-action-pinning.sh`.
- `.github/workflows/supply-chain-security.yml` — `ubuntu-24.04`, Node + Go setup, then plain shell: `npm audit --audit-level=high` only if `package-lock.json` exists (it doesn't — `package.json` has no `dependencies` field and no lockfile, so this step currently just prints that there's nothing to check); Go step scans each `apps/*/go.mod` for a `require` block and runs `go run golang.org/x/vuln/cmd/govulncheck@latest ./...` only where one exists (currently neither `go.mod` has third-party requires, so it also no-ops with an explicit message). Comment block at the top states plainly this is real-but-currently-empty coverage, not a stand-in for `dependency-review-action`.

## Where I used shell instead of an unpinned action

- `dependency-review-action` (GitHub's PR dependency-review action): no verified SHA pin was given and I was told not to guess one. Implemented `supply-chain-security.yml` with `npm audit` / `govulncheck` shell steps instead, gated on evidence actually existing (lockfile / `require` block) rather than always running a no-op. Kept `.github/dependency-review-config.yml` in that action's schema so it can be wired up directly once a pin is verified.
- No other action beyond the four pre-verified pins (`checkout`, `setup-node`, `setup-go`, `upload-artifact`) was needed for any workflow — `upload-artifact` wasn't needed either since none of these four workflows produce build artifacts.

## Verification run (from worktree root)

```
$ ./scripts/check-repo-hygiene.sh; echo "exit=$?"
仓库基础卫生检查通过
exit=0

$ ./scripts/check-action-pinning.sh; echo "exit=$?"
GitHub Action 固定 SHA 检查通过
exit=0

$ ./scripts/check-docs.sh; echo "exit=$?"
文档骨架检查通过
exit=0
```

YAML/JSON parse check (python3 is SIGKILLed in this environment per project instructions; used `ruby -ryaml` for YAML and `node -e` for JSON instead — no other YAML parser was found on PATH):

```
.github/dependency-review-config.yml: OK
.github/ISSUE_TEMPLATE/bug_report.yml: OK
.github/ISSUE_TEMPLATE/feature_request.yml: OK
.github/ISSUE_TEMPLATE/config.yml: OK
.github/workflows/ci.yml: OK
.github/workflows/docs-check.yml: OK
.github/workflows/repo-hygiene.yml: OK
.github/workflows/supply-chain-security.yml: OK
.markdownlint.json: OK
```

(Note: an early hygiene-check run mid-session reported all these files "missing" — that was a transient race with other teammate agents writing to the same worktree concurrently, not a real gap. Re-run after all files were in place passed cleanly, as shown above.)

## Unresolved questions

- None blocking. Open item for a human/maintainer decision: whether to later add a verified SHA pin for `actions/dependency-review-action` and switch `supply-chain-security.yml` to call it directly (config file is already in place for that).

Status: DONE
Summary: Added all 11 assigned repo-hygiene files (editorconfig, markdownlint config, PR/issue templates, and 4 workflows), used SHA-pinned actions only from the verified set, substituted honest plain-shell checks for the unpinned dependency-review action, and verified repo-hygiene/action-pinning/docs-check scripts all pass plus every YAML/JSON file parses.
