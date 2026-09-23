# Code Change History Recording Convention

`docs/histories/` is used to record completed code change tasks. Pure Q&A, research, or analysis tasks default to not needing a history entry, unless the repository content was actually changed in the end.

## Basic Requirements

- Every completed code change task should have a corresponding history file, or be appended to that task's existing history file.
- The user's original request may be reasonably condensed, but key information must be preserved.
- Do not write sensitive information, local paths, secrets, or raw log details directly into it.
- When the same task progresses across multiple rounds, keep maintaining the same history entry; do not create a duplicate file.

## Directory and Naming

- Directory: `docs/histories/YYYY-MM/`
- File name: `YYYYMMDD-HHmm-task-slug.md`
- Template: `docs/histories/template.md`

Example:

```text
docs/histories/
  2026-04/
    20260408-1430-bootstrap-template.md
```

## What to Write

- The user's request verbatim, or a condensed, desensitized version of it.
- The main code and documentation changes made this round.
- The design motivation, and why it was done this way.
- The most critical affected files.
