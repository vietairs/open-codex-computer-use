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
Prefer `run_script` when the app's scripting dictionary covers the task; check it with `get_scripting_dictionary` first. \
A turn that only uses `run_script` can skip the turn-start `get_app_state`. \
After a script changed the UI, use `find_elements` with element actions or `perform_actions`, and `get_app_state` only when those do not fit or to verify. \
Keep scripts small (one mailbox, the first N results): a timed-out script keeps running. \
Scripts show no cursor, so ask the user before sending, deleting or purchasing. \
Script text is logged; the shell-verb filter is not a security boundary.
"""
