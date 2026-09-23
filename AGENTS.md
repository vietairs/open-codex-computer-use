# open-codex-computer-use

This repository is a base template for Agent-collaborative development.

`AGENTS.md` is deliberately kept short — it only handles navigation, not every rule. The `docs/` folder inside the repository is the authoritative source of local knowledge.

If a code or process change makes a document stale, update it in the same round of work.

## Read at the start of every round

- `docs/REPO_COLLAB_GUIDE.md`: repo-level collaboration, commit, doc-sync, and testing conventions.
- `docs/ARCHITECTURE.md`: overall repository structure and expected boundaries.
- `docs/design-docs/core-beliefs.md`: Agent-first working principles and the design starting point for this template.

## Read before finishing a code change

- `docs/HISTORY_GUIDE.md`: when to record a history entry, how to name it, and how to redact it.
- `docs/QUALITY_SCORE.md`: current quality tiers and the main shortfalls.

## Read as needed per task

- `docs/PLANS_GUIDE.md`: when an execution plan is needed and how to maintain it.
- `docs/PRODUCT_SENSE.md`: product value, trade-off approach, and prioritization judgment.
- `docs/RELIABILITY.md`: runtime stability, observability, and baseline pre-launch requirements.
- `docs/SECURITY.md`: default security constraints for auth, data handling, external integrations, etc.
- `docs/SUPPLY_CHAIN_SECURITY.md`: dependencies, SBOM, artifact provenance, and repo-level default supply-chain security practices.
- `docs/CICD.md`: the repository's CI/CD skeleton and how to wire in a real project later.
- `docs/FRONTEND.md`: if the repository includes a frontend UI, this records the corresponding conventions.
- `CONTRIBUTING.md`: default checks and collaboration requirements before/after opening a PR.
- `docs/releases/README.md`: how to maintain user-facing release records.
- `docs/releases/RELEASE_GUIDE.md`: whenever a task involves bumping a version, tagging, or pushing a release, read this must-read first.
- `docs/references/README.md`: external reference material archived into the repository.

## Working rules

- Prefer small, clear abstractions that are friendly to both the repository and Agents.
- Replies default to the language the user's question used; if the user switches language, replies switch too.
- If the user's input this round is in English, reply directly in English.
- Write all repository documents in English — including `docs/histories/`, execution plans, and release records — regardless of the language used in conversation. `README.zh-CN.md` is the one deliberate exception.
- Sync with the latest remote code before running `git push`.
- Keep prompts, rules, and architectural constraints version-controlled in the repository as much as possible.
- Don't rely on chat context alone for complex tasks — write an execution plan.
- Record completed code changes in `docs/histories/`.
