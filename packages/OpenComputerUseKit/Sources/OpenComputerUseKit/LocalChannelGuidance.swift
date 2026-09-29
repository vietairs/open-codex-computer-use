import Foundation

/// The instruction line the base server instructions carry today. It must stay byte-identical to the line in
/// `baseComputerUseServerInstructions`, because the relay swaps it for `scriptFirstInstructionGuide` by exact match
/// when the scripting channel is enabled.
let appleScriptAvoidanceInstructionLine =
    "Avoid falling back to AppleScript during a computer use session. "
    + "Prefer Computer Use tools as much as possible to complete tasks."

/// Replaces `appleScriptAvoidanceInstructionLine` in the relay's `initialize` response when the scripting channel is
/// enabled, so the host is never told both to avoid AppleScript and to prefer it.
let scriptFirstInstructionGuide = """
When the app's scripting dictionary covers the task, prefer `run_script` over driving the UI; check the available terms with `get_scripting_dictionary` first. \
The turn-start `get_app_state` call described above applies to UI work; a turn that only uses `run_script` can skip it. \
For UI work, after that turn-start `get_app_state`, use `find_elements` plus element-targeted actions. \
After a script changed the UI, use `find_elements` to locate the control you need next rather than re-reading the whole tree, and call `get_app_state` again only when neither fits or to verify. \
Keep script queries small (one mailbox, the first N results), because a timed-out script keeps running inside the target app. \
Scripts act without the visible cursor, so ask the user before sending, deleting or purchasing. \
Script text is logged, and the shell-verb filter is best-effort friction, not a security boundary.
"""
