# Contributing

This repository is prepared for Agent-first development, but these rules apply equally to humans and agents.

## Basic collaboration approach

- Start with `AGENTS.md`, then read the corresponding docs by task type.
- Repo-level knowledge should land in version-controlled files, not only live in chat history, verbal syncs, or ticket comments.
- If behavior changes, update code, docs, tests, and release/history records together.
- For work that spans a wide scope, carries high risk, or will proceed across multiple rounds, first create an execution plan under `docs/exec-plans/active/`.

## Before opening a Pull Request

- Run `make check-docs`.
- If this change touches code or repo workflow, add or update the corresponding history entry.
- If the change is user-visible, add a release note.
- Confirm examples, scripts, and documentation are consistent with the current implementation.

## Default review requirements

- Prefer splitting into small PRs with a clear scope.
- Clearly state risk points, migration impact, and follow-up TODOs.
- If the context is complex, link directly to the corresponding plan, spec, or history instead of relying on the reviewer to guess.
