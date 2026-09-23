## [2026-04-22 11:24] | Task: Add a TextEdit overlay cursor test sequence

### Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5.4`
* **Runtime**: `Codex CLI on macOS + SwiftPM`

### User Query
> Help me put together `examples/textedit-overlay-seq.json`, a sequence of multiple tool calls, to test the latest cursor behavior.

### Changes Overview
**Scope:** manual test sample

**Key Actions:**
- **[Root examples]**: Added `examples/textedit-overlay-seq.json` at the repo root, filling in the sample path referenced by the docs.
- **[Cursor-focused sequence]**: Arranged `get_app_state -> set_value -> click -> set_value -> click -> set_value`, interleaved with state refreshes, to make it easy to observe whether the cursor keeps its idle position between consecutive `click` / `set_value` calls.
- **[Visible target spread]**: Changed the click targets to TextEdit's rich-text toolbar alignment buttons, avoiding the case where a window-center click nearly coincides with the body-text center and makes subsequent movement invisible.
- **[Observation text]**: Clearly marked sections A/B/C in the text written into TextEdit, making it easy to manually observe the start and end point of each overlay movement.

### Files Modified
- `examples/textedit-overlay-seq.json`
- `docs/histories/2026-04/20260422-1124-add-textedit-overlay-sequence.md`
