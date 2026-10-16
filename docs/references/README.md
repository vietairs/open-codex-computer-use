# External Reference Material

This directory is for external reference material worth keeping long-term in the repo, for agents to read directly.

Content suitable for this directory includes:

- Framework, deployment, or integration notes the team relies on repeatedly.
- Design-system references, API usage conventions.
- Condensed summaries of external standards, partner agreements, or external docs.
- Reverse-engineering analysis and write-ups of closed-source dependencies, third-party binaries, or external tools.

Don't dump large chunks of vendor docs in here verbatim. This should be curated, distilled material.

## Current Directory

- `codex-computer-use-reverse-engineering/`
  - Ongoing reverse-engineering analysis material for the official `Codex Computer Use.app` / `SkyComputerUseClient`; large one-off analysis artifacts are regenerated locally under `research/` by default and not committed to the repo.
- `codex-network-capture.md`
  - Capturing Codex's upstream HTTP / WebSocket traffic with `mitmdump` + `scripts/codex_dump.py`, and persisting the corresponding `session_id`'s local `function_call` / `function_call_output` summaries alongside it in `artifacts/codex-dumps/` for ongoing analysis.
- `codex-local-runtime-logs.md`
  - When the `websocket/` + `local-sessions/` in the capture directory still aren't enough to explain local tool / MCP behavior, check Codex's local `logs_2.sqlite` as well.
- `codex-computer-use-cli.md`
  - The purpose and usage of the in-repo `scripts/computer-use-cli/`, and why probing the official bundled `computer-use` should go through the `codex app-server` proxy first rather than direct stdio.
- `macos-skylight-background-click.md`
  - Sources for the `click_method=sky_click` write-up and open-source implementation, the pinned source version, the Chromium primer event sequence, scope not adopted, and macOS private-SPI compatibility checks.
- `macos-skylight-background-keyboard.md`
  - How `key_method=sky_key` types into a covered Chromium / Electron window: the key-window record pair, the accessibility key-window confirmation, the bounded menu-bar walk for command chords, the live findings, the approaches ruled out, and compatibility checks.
- `macos-window-visibility-and-spaces.md`
  - Why covered and other-Space Chromium / Electron / WebKit windows lose their web tree (WindowServer occlusion, not the Space), how the `get_app_state` keep-alive pins a window's visible state and restores it, other-Space and hardware window capture, the Chromium lazy web tree wait, `sky_click` / `sky_key` on such windows, and the macOS version gate.
