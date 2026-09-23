# Release Notes Guide

`feature-release-notes.md` records user-facing new features, experience improvements, and notable fixes.

`github/vX.Y.Z.md` is the reviewed English copy for the GitHub Release body. Every public release must create the target tag's file from `github/TEMPLATE.md` and run the release-notes check before tagging.

If the task is "prepare a release / bump version / tag / investigate a release failure," read `RELEASE_GUIDE.md` first.

## Rules

- Group by month, using the `## YYYY-MM` format.
- Within the same month, put the newest entry at the top.
- Lead with user value, then follow with a summary of the change.
- Do not clutter this file with pure internal refactors or implementation noise.
- The GitHub Release body defaults to reviewed English text; it is not generated directly from PR titles.

## Suggested columns

- Date
- Feature area
- User value
- Change summary
