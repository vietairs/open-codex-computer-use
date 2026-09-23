# Repository Collaboration Conventions

This document defines the default collaboration approach for an Agent-first repository. Constraints strongly tied to a specific tech stack should be split out into adjacent topic-specific documents; do not turn this one into a catch-all.

## Development Principles

- Prefer simple, clear, observable solutions; do not pile up hard-to-maintain complexity.
- Organize the repository around Agent readability and executability; important information that lives only in chat history or in someone's head is effectively nonexistent.
- Keep code, documentation, tests, configuration, and release records updated from the same source as much as possible.
- If an Agent repeatedly fails on the same class of problem, prioritize fixing the environment, scaffolding, or conventions; don't treat "try the prompt a few more times" as the primary remedy.
- Whenever fixing a bug, also check whether tests and documentation should be strengthened, so the same kind of issue only needs fixing once.

## Documentation Discipline

- `AGENTS.md` should only do routing; don't pile a huge stack of rules into it.
- `docs/` is the authoritative source of repository-level knowledge.
- Once behavior changes, the corresponding documentation must be updated in the same change.
- Files, directories, script entry points, and documentation links within the repository must always use relative paths; never write any machine-specific absolute paths.
- Rather than continuing to pile content into a large document, it is preferable to add a new, clearly-bounded small document.

## Git and Review

- Keep commits as scoped and accurately described as possible.
- Sync with the latest remote code before `git push`, to avoid pushing a stale branch state as-is.
- Before submitting or opening a PR, confirm that documentation, examples, scripts, and history reflect the final state.
- For complex or high-risk changes, first put down an execution plan in `docs/exec-plans/`.
- Reviews should reference in-repo files as much as possible; do not rely on context known only to a few people.

## Testing and Verification

- Every substantive code change should leave verification capability a bit stronger than before the change.
- Prefer settling verification into commands and scripts that can be run directly from the repository.
- If the project includes a UI, ensure it can be started and verified independently locally.
- If the project depends on logs, metrics, or traces, ideally provide a local or CI-accessible path to them.
- Even if the project hasn't yet integrated a real production build pipeline, repository-level CI should still be runnable from the start.

## CI/CD and Delivery Method

- CI should at minimum guard repository readability and basic security; don't wait until the project grows to add this.
- The CD skeleton should prioritize producing clear artifacts and provenance, rather than prematurely assuming a deployment target.
- When a real tech stack is integrated in the future, prioritize extending the existing pipeline rather than standing up a separate temporary script to bypass it.

## Configuration Hygiene

- Example configuration should stay as consistent as possible with actual default values.
- All environment variables and external dependencies required for startup should be clearly documented.
- Don't let critical initialization steps exist only in a corner of the README; script them wherever possible.
