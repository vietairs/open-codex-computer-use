# Execution Plan Usage Guide

An execution plan is suited to tasks that exceed a single chat context, need multiple rounds of progress, or carry higher risk.

## When to create a plan

- The task will progress across multiple commits or multiple rounds of work.
- The change affects architecture, protocols, data migration, or other high-risk areas.
- Completing the task depends on staged verification, a rollback strategy, or a record of key decisions.
- Multiple people or multiple agents may work on it together over a period of time.

## Storage locations

- In-progress plans go in `docs/exec-plans/active/`
- Completed plans move to `docs/exec-plans/completed/`
- The reusable template is at `docs/exec-plans/templates/execution-plan.md`
- Debt that isn't being addressed now but is worth keeping track of goes in `docs/exec-plans/tech-debt-tracker.md`

## Maintenance requirements

- Write the goal, scope, constraints, risks, and verification method clearly.
- Progress and key decisions should be recorded in the repository, not only kept in chat history.
- Status changes should be kept in sync.
- Stale plans should be closed, archived, or cleaned up promptly to keep the active directory trustworthy.
