# Plan Archive

This tree is a **historical record, not the current source of truth**. Nothing here
describes how the system works today — read `docs/` and the live `plans/` dirs for that.

Each archived plan dir keeps a `ledger.md`: the sanctioned summary of what that
pipeline actually shipped. Read the ledger first; the surrounding files are raw
working material and may contradict what was finally merged.

Full content of every archived dir remains in git history, so nothing here is lost
even after a `plan-gc compact` prunes bodies down to the ledger.

The `.ignore` sentinel in this directory hides the whole archive from default
ripgrep-based searches on purpose — a dead plan must not rank alongside a live spec
in an agent's search results. Reach it deliberately with `rg --no-ignore` or a direct
file read.
