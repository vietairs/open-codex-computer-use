# Fix macOS Unicode type_text Ordering

### Request

Investigate the issue where using `type_text` with OCU to type Chinese text into input fields in apps like Feishu (飞书) produces out-of-order or garbled characters; locate the cause first, then fix and verify.

### Changes

- Changed macOS `type_text` from sending keyboard events for each UTF-16 code unit one at a time, to aggregating Unicode extended grapheme clusters into small batched `keyboardSetUnicodeString` events.
- Added recording of the currently focused element to the accessibility snapshot; when the focused element's `AXValue` is settable, `type_text` now prefers to append to and write back `AXValue`, as a non-foreground fallback for cases where an Electron rich-text input field unreliably receives background keyboard events.
- The `AXValue` fallback derives the existing draft from the editable child text and filters out Feishu input-field placeholder hints, avoiding the placeholder getting concatenated into the message content.
- When the currently focused element is not an editable text target, `type_text` now explicitly errors out, requiring the caller to click the text input area first or use `set_value`, instead of treating an ineffective background keyboard delivery as success.
- Added unit tests covering Chinese full-width parentheses, emoji surrogate pairs, ZWJ sequences, combining characters, and CJK extension characters, to make sure chunking round-trips losslessly and never splits a grapheme cluster.
- Updated the architecture docs to record the Unicode input boundaries of `type_text`.

### Motivation

In earlier sessions, `type_text`'s arguments were correct, but the Feishu input field would still end up with reversed parenthesis direction, wrong ordering, and leftover text for Chinese input. Code investigation showed part of the problem sits in the macOS input-injection layer: the original implementation split text into individual UTF-16 code units and sent them one at a time, and complex Unicode text was prone to being processed out of order or garbled asynchronously inside Electron rich-text controls. Sending a complete Unicode text chunk as a batch reduces event reordering.

Real Feishu verification also found that even after focusing the input field, background `CGEvent.postToPid` keyboard events could still fail to reach the Electron rich-text editor, while the `set_value` path on the same element could reliably write the full Unicode text. So `type_text` now adds a fallback to the focused element's settable `AXValue`, reusing the same settable-value capability without stealing focus or using the clipboard. Later testing also exposed another false positive: when focus was sitting on a WebArea, `type_text` would return success without actually writing anything. This state now results in an explicit error, requiring the caller to first use OCU click to focus the input field.

### Files

- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/InputSimulation.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/ARCHITECTURE.md`

### Validation

- `swift test`
- `./scripts/run-tool-smoke-tests.sh`
- Manual verification in the local fixture window: after focusing `fixture-input`, delivered `（ocu发的）👩🏽‍💻é𠀀` via batched `CGEvent.keyboardSetUnicodeString`, and the exported fixture state showed the exact same string precisely.
- Real verification against Feishu with the dev app: in the same process, clicked the input field first, then ran `type_text` to type `（ocu发的测试）👩🏽‍💻é𠀀`; the subsequent snapshot's actual draft child text fully contained the Chinese parentheses, ZWJ emoji, combining accents, and CJK extension characters intact; cleared the draft afterward with `Command+A` / `BackSpace`.
- Re-tested `type_text` over the real delivery path: when the input field wasn't focused, WebArea was no longer treated as an editable target; after first using OCU `click` to focus the text entry area, `type_text` + `press_key Return` successfully sent the full Chinese test message into the Feishu conversation.
