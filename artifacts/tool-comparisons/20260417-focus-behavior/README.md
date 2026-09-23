# 2026-04-17 Focus Behavior Comparison

This set of samples compares the impact of the official `computer-use` and the repo's own `open-computer-use` on the user's foreground focus/mouse in "read-only state" and "coordinate click" scenarios.

## Directory

- `computer-use/`
  - Samples from the connected official `computer-use` MCP tool.
- `open-codex-computer-use/`
  - Samples from the repo's current implementation.
  - The directory name keeps the old naming, only to avoid changing the path of this already-archived batch of samples.
  - `get_app_state` is collected via JSON-RPC `tools/call` through the locally packaged `dist/OpenCodexComputerUse.app`.
  - `click` is likewise collected via local JSON-RPC.

## Method

- Target app: `Activity Monitor`
- Control foreground app: `iTerm2`
- Observed items:
  - tool request
  - tool result summary
  - frontmost app before and after the call
  - mouse coordinates before and after the call

## Known Limitations

- The official `computer-use` currently cannot directly recognize the bare executable fixtures in the repo, so the comparison target was switched to a system app that both sides can resolve.
- Mouse coordinates can be affected by the user's live movement, so here they are only used as a supplementary observation; "whether the foreground app was switched away" is a more stable comparison signal.
- `open-computer-use`'s coordinate click now does an AX hit-test first; if the hit fails, it still falls back to global HID.
