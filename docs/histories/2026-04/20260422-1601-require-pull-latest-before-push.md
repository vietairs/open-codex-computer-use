## [2026-04-22 16:01] | Task: require syncing latest remote code before push

### Background

- The user asked for "pull the latest code before push" to be added into the repo rules, and specifically added to `AGENTS.md`.

### Changes

- **[Agent Routing]**: Added an explicit constraint into `AGENTS.md`'s work rules: sync the latest remote code before running `git push`.
- **[Canonical Repo Rule]**: Added the same rule to the Git conventions in `docs/REPO_COLLAB_GUIDE.md`, so the requirement doesn't stay confined to the entry-point navigation doc.

### Validation

- Passed: `make check-docs`

### Files Affected

- `AGENTS.md`
- `docs/REPO_COLLAB_GUIDE.md`
- `docs/histories/2026-04/20260422-1601-require-pull-latest-before-push.md`
